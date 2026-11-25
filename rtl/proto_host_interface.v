`default_nettype none

//=============================================================================
// Module: proto_host_interface
// Description: SPI-Compatible Host Interface for Configuration & Streaming
// Provides register-mapped read/write, burst IMEM microcode programming,
// and bidirectional FIFO streaming.
//=============================================================================

module proto_host_interface (
    input  wire        clk,
    input  wire        rst_n,

    // Physical SPI Interface
    input  wire        sclk,
    input  wire        cs_n,
    input  wire        mosi,
    output wire        miso,
    output wire        irq,

    // Control and Configuration Registers
    output reg  [15:0] reg_ctrl,
    output reg  [15:0] reg_div_e0,
    output reg  [15:0] reg_div_e1,
    output reg  [15:0] reg_frac_div,
    output reg  [15:0] reg_cfg_e0,
    output reg  [15:0] reg_cfg_e1,
    output reg  [15:0] reg_pin_mode,

    // Engine 0 Instruction Memory Programming Port (Port B)
    output reg         imem_e0_we,
    output reg  [4:0]  imem_e0_addr,
    output reg  [15:0] imem_e0_din,
    input  wire [15:0] imem_e0_dout,

    // Engine 1 Instruction Memory Programming Port (Port B)
    output reg         imem_e1_we,
    output reg  [4:0]  imem_e1_addr,
    output reg  [15:0] imem_e1_din,
    input  wire [15:0] imem_e1_dout,

    // FIFO Data Streaming Interface
    output reg         e0_tx_push,
    output reg  [15:0] e0_tx_din,
    output reg         e0_rx_pop,
    input  wire [15:0] e0_rx_dout,

    output reg         e1_tx_push,
    output reg  [15:0] e1_tx_din,
    output reg         e1_rx_pop,
    input  wire [15:0] e1_rx_dout,

    // Status Signals from Core
    input  wire [15:0] status_word,
    input  wire [15:0] diag_e0_word,
    input  wire [15:0] diag_e1_word
);

    // Synchronize SPI inputs to system clock (double-flop)
    reg [2:0] sclk_sync;
    reg [2:0] cs_n_sync;
    reg [1:0] mosi_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync <= 3'b000;
            cs_n_sync <= 3'b111;
            mosi_sync <= 2'b00;
        end else begin
            sclk_sync <= {sclk_sync[1:0], sclk};
            cs_n_sync <= {cs_n_sync[1:0], cs_n};
            mosi_sync <= {mosi_sync[0], mosi};
        end
    end

    wire sclk_rising  = (sclk_sync[2:1] == 2'b01);
    wire sclk_falling = (sclk_sync[2:1] == 2'b10);
    wire cs_active    = !cs_n_sync[1];

    // SPI State Machine
    localparam ST_CMD   = 2'd0;
    localparam ST_DATA0 = 2'd1;
    localparam ST_DATA1 = 2'd2;

    reg [1:0]  state;
    reg [2:0]  bit_count;
    reg [7:0]  shift_in;
    reg [15:0] shift_out;
    reg        is_read;
    reg [6:0]  cur_addr;
    reg [7:0]  data_byte_high;
    reg [15:0] rx_word;
    reg        need_shift;

    // Direct continuous MISO drive from MSB of shift_out
    assign miso = (cs_active && is_read) ? shift_out[15] : 1'b0;

    // Interrupt output: asserted when RX FIFO has data ready
    assign irq = !status_word[5] || !status_word[7]; // RX0 or RX1 not empty

    // Function to resolve register data immediately without 1-cycle flop lag
    function [15:0] get_reg_val;
        input [6:0] addr;
        begin
            if (addr == 7'h00)      get_reg_val = reg_ctrl;
            else if (addr == 7'h01) get_reg_val = status_word;
            else if (addr == 7'h02) get_reg_val = reg_div_e0;
            else if (addr == 7'h03) get_reg_val = reg_div_e1;
            else if (addr == 7'h04) get_reg_val = reg_frac_div;
            else if (addr == 7'h05) get_reg_val = reg_cfg_e0;
            else if (addr == 7'h06) get_reg_val = reg_cfg_e1;
            else if (addr == 7'h07) get_reg_val = reg_pin_mode;
            else if (addr == 7'h08) get_reg_val = e0_rx_dout;
            else if (addr == 7'h09) get_reg_val = e1_rx_dout;
            else if (addr == 7'h0A) get_reg_val = diag_e0_word;
            else if (addr == 7'h0B) get_reg_val = diag_e1_word;
            else if (addr >= 7'h10 && addr <= 7'h2F) get_reg_val = imem_e0_dout;
            else if (addr >= 7'h30 && addr <= 7'h4F) get_reg_val = imem_e1_dout;
            else                    get_reg_val = 16'h0000;
        end
    endfunction

    reg [6:0] target_cmd_addr;

    // Sequential SPI processing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_CMD;
            bit_count      <= 3'd7;
            shift_in       <= 8'd0;
            shift_out      <= 16'd0;
            is_read        <= 1'b0;
            cur_addr       <= 7'd0;
            data_byte_high <= 8'd0;
            need_shift     <= 1'b0;
            reg_ctrl       <= 16'h0000;
            reg_div_e0     <= 16'h0000;
            reg_div_e1     <= 16'h0000;
            reg_frac_div   <= 16'h0000;
            reg_cfg_e0     <= 16'h0000;
            reg_cfg_e1     <= 16'h0000;
            reg_pin_mode   <= 16'h0000;
            imem_e0_we     <= 1'b0;
            imem_e0_addr   <= 5'd0;
            imem_e0_din    <= 16'h0000;
            imem_e1_we     <= 1'b0;
            imem_e1_addr   <= 5'd0;
            imem_e1_din    <= 16'h0000;
            e0_tx_push     <= 1'b0;
            e0_tx_din      <= 16'h0000;
            e0_rx_pop      <= 1'b0;
            e1_tx_push     <= 1'b0;
            e1_tx_din      <= 16'h0000;
            e1_rx_pop      <= 1'b0;
        end else begin
            // Reset single-cycle strobes
            imem_e0_we <= 1'b0;
            imem_e1_we <= 1'b0;
            e0_tx_push <= 1'b0;
            e0_rx_pop  <= 1'b0;
            e1_tx_push <= 1'b0;
            e1_rx_pop  <= 1'b0;

            if (!cs_active) begin
                state      <= ST_CMD;
                bit_count  <= 3'd7;
                is_read    <= 1'b0;
                need_shift <= 1'b0;
            end else begin
                // Update MISO shift register on falling edge of SCLK AFTER data bit was sampled
                if (sclk_falling && need_shift) begin
                    shift_out  <= {shift_out[14:0], 1'b0};
                    need_shift <= 1'b0;
                end

                // Sample MOSI on rising edge of SCLK
                if (sclk_rising) begin
                    shift_in <= {shift_in[6:0], mosi_sync[1]};

                    if (state != ST_CMD) begin
                        need_shift <= 1'b1;
                    end

                    if (bit_count == 3'd0) begin
                        bit_count <= 3'd7;
                        case (state)
                            ST_CMD: begin
                                is_read         <= shift_in[6];
                                target_cmd_addr = {shift_in[5:0], mosi_sync[1]};
                                cur_addr        <= target_cmd_addr;
                                state           <= ST_DATA0;
                                need_shift      <= 1'b0;

                                if (shift_in[6]) begin
                                    shift_out <= get_reg_val(target_cmd_addr);
                                    if (target_cmd_addr == 7'h08) e0_rx_pop <= 1'b1;
                                    if (target_cmd_addr == 7'h09) e1_rx_pop <= 1'b1;
                                end
                            end

                            ST_DATA0: begin
                                data_byte_high <= {shift_in[6:0], mosi_sync[1]};
                                state          <= ST_DATA1;
                            end

                            ST_DATA1: begin
                                state    <= ST_DATA0; // Burst mode: ready for next word
                                cur_addr <= cur_addr + 7'd1;

                                if (!is_read) begin
                                    rx_word = {data_byte_high, shift_in[6:0], mosi_sync[1]};

                                    if (cur_addr == 7'h00) reg_ctrl     <= rx_word;
                                    if (cur_addr == 7'h02) reg_div_e0   <= rx_word;
                                    if (cur_addr == 7'h03) reg_div_e1   <= rx_word;
                                    if (cur_addr == 7'h04) reg_frac_div <= rx_word;
                                    if (cur_addr == 7'h05) reg_cfg_e0   <= rx_word;
                                    if (cur_addr == 7'h06) reg_cfg_e1   <= rx_word;
                                    if (cur_addr == 7'h07) reg_pin_mode <= rx_word;

                                    if (cur_addr == 7'h08) begin
                                        e0_tx_push <= 1'b1;
                                        e0_tx_din  <= rx_word;
                                    end

                                    if (cur_addr == 7'h09) begin
                                        e1_tx_push <= 1'b1;
                                        e1_tx_din  <= rx_word;
                                    end

                                    // IMEM Engine 0 write (0x10 .. 0x2F)
                                    if (cur_addr >= 7'h10 && cur_addr <= 7'h2F) begin
                                        imem_e0_we   <= 1'b1;
                                        imem_e0_addr <= cur_addr - 7'h10;
                                        imem_e0_din  <= rx_word;
                                    end

                                    // IMEM Engine 1 write (0x30 .. 0x4F)
                                    if (cur_addr >= 7'h30 && cur_addr <= 7'h4F) begin
                                        imem_e1_we   <= 1'b1;
                                        imem_e1_addr <= cur_addr - 7'h30;
                                        imem_e1_din  <= rx_word;
                                    end
                                end else begin
                                    shift_out <= get_reg_val(cur_addr + 7'd1);
                                    if ((cur_addr + 7'd1) == 7'h08) e0_rx_pop <= 1'b1;
                                    if ((cur_addr + 7'd1) == 7'h09) e1_rx_pop <= 1'b1;
                                end
                            end
                        endcase
                    end else begin
                        bit_count <= bit_count - 3'd1;
                    end
                end
            end
        end
    end

endmodule
