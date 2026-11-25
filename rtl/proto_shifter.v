`default_nettype none

//=============================================================================
// Module: proto_shifter
// Description: Shift Register Unit with Autopush & Autopull Mechanics
// Supports bidirectional shifting (Left/Right), variable bit widths,
// and hardware-driven automatic FIFO push/pull thresholds.
//=============================================================================

module proto_shifter (
    input  wire        clk,
    input  wire        rst_n,

    // Configuration
    input  wire        shift_in_dir,      // 0 = Shift Left (MSB first), 1 = Shift Right (LSB first)
    input  wire        shift_out_dir,     // 0 = Shift Left (MSB first), 1 = Shift Right (LSB first)
    input  wire        autopush_en,       // Automatic push to RX FIFO when threshold reached
    input  wire        autopull_en,       // Automatic pull from TX FIFO when OSR empty
    input  wire [4:0]  push_threshold,    // e.g. 8 for 8-bit bytes, 16 for words
    input  wire [4:0]  pull_threshold,    // e.g. 8 for 8-bit bytes, 16 for words

    // Shift In Control (from Engine execution)
    input  wire        in_en,             // Execute IN instruction
    input  wire [4:0]  in_nbits,          // Number of bits to shift (1..16)
    input  wire [15:0] in_data,           // Incoming bit(s) from selected pin/register

    // Shift Out Control (from Engine execution)
    input  wire        out_en,            // Execute OUT instruction
    input  wire [4:0]  out_nbits,         // Number of bits to shift out (1..16)
    output wire [15:0] out_data,          // Sliced output bits to pins/registers

    // Direct Register Read/Write (via MOV instructions)
    input  wire        mov_isr_we,
    input  wire [15:0] mov_isr_din,
    input  wire        mov_osr_we,
    input  wire [15:0] mov_osr_din,
    output wire [15:0] isr_val,
    output wire [15:0] osr_val,

    // FIFO Interface
    input  wire        rx_fifo_full,
    output reg         rx_fifo_push,
    output reg  [15:0] rx_fifo_din,

    input  wire        tx_fifo_empty,
    input  wire [15:0] tx_fifo_dout,
    output reg         tx_fifo_pop,

    // Explicit PUSH / PULL from instruction
    input  wire        cmd_push,
    input  wire        cmd_pull,
    output wire        osr_empty,
    output wire [4:0]  osr_remain
);

    reg [15:0] isr;
    reg [4:0]  isr_count;
    reg [15:0] osr;
    reg [4:0]  osr_count;

    assign isr_val    = isr;
    assign osr_val    = osr;
    assign osr_empty  = (osr_count == 5'd0);
    assign osr_remain = osr_count;

    // Sliced output data from OSR depending on shift direction
    // If shift left: top bits are shifted out
    // If shift right: bottom bits are shifted out
    assign out_data = shift_out_dir ? osr : (osr >> (5'd16 - out_nbits));

    // Sequential Shift Register Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            isr          <= 16'h0000;
            isr_count    <= 5'd0;
            osr          <= 16'h0000;
            osr_count    <= 5'd0;
            rx_fifo_push <= 1'b0;
            rx_fifo_din  <= 16'h0000;
            tx_fifo_pop  <= 1'b0;
        end else begin
            // Default strobe pulses
            rx_fifo_push <= 1'b0;
            tx_fifo_pop  <= 1'b0;

            // -------------------------------------------------------------
            // INPUT SHIFT REGISTER (ISR) HANDLING
            // -------------------------------------------------------------
            if (mov_isr_we) begin
                isr       <= mov_isr_din;
                isr_count <= 5'd0;
            end else if (cmd_push) begin
                // Explicit PUSH instruction
                if (!rx_fifo_full) begin
                    rx_fifo_push <= 1'b1;
                    rx_fifo_din  <= isr;
                    isr          <= 16'h0000;
                    isr_count    <= 5'd0;
                end
            end else if (in_en) begin
                // Shift in bits
                if (shift_in_dir == 1'b0) begin
                    // Shift Left: insert in_data at LSB
                    isr <= (isr << in_nbits) | (in_data & ((16'h0001 << in_nbits) - 16'h0001));
                end else begin
                    // Shift Right: insert in_data at top of threshold
                    if (push_threshold == 5'd8)
                        isr <= (isr >> in_nbits) | ((in_data & 16'h0001) << (5'd8 - in_nbits));
                    else
                        isr <= (isr >> in_nbits) | (in_data << (5'd16 - in_nbits));
                end

                // Check Autopush
                if (autopush_en && ((isr_count + in_nbits) >= push_threshold)) begin
                    if (!rx_fifo_full) begin
                        rx_fifo_push <= 1'b1;
                        if (shift_in_dir == 1'b0)
                            rx_fifo_din <= (isr << in_nbits) | (in_data & ((16'h0001 << in_nbits) - 16'h0001));
                        else
                            rx_fifo_din <= (isr >> in_nbits) | (in_data << (5'd16 - in_nbits));
                        isr          <= 16'h0000;
                        isr_count    <= 5'd0;
                    end
                end else begin
                    isr_count <= isr_count + in_nbits;
                end
            end

            // -------------------------------------------------------------
            // OUTPUT SHIFT REGISTER (OSR) HANDLING
            // -------------------------------------------------------------
            if (mov_osr_we) begin
                osr       <= mov_osr_din;
                osr_count <= pull_threshold;
            end else if (cmd_pull) begin
                // Explicit PULL instruction
                if (!tx_fifo_empty) begin
                    tx_fifo_pop <= 1'b1;
                    osr         <= tx_fifo_dout;
                    osr_count   <= pull_threshold;
                end
            end else if (out_en) begin
                // Shift out bits
                if (shift_out_dir == 1'b0) begin
                    // Shift Left
                    osr <= osr << out_nbits;
                end else begin
                    // Shift Right
                    osr <= osr >> out_nbits;
                end

                if (osr_count > out_nbits) begin
                    osr_count <= osr_count - out_nbits;
                end else begin
                    // OSR now empty; check Autopull
                    if (autopull_en && !tx_fifo_empty) begin
                        tx_fifo_pop <= 1'b1;
                        osr         <= tx_fifo_dout;
                        osr_count   <= pull_threshold;
                    end else begin
                        osr_count   <= 5'd0;
                    end
                end
            end else if (autopull_en && (osr_count == 5'd0) && !tx_fifo_empty) begin
                // Idle autopull when empty
                tx_fifo_pop <= 1'b1;
                osr         <= tx_fifo_dout;
                osr_count   <= pull_threshold;
            end
        end
    end

endmodule
