`default_nettype none

//=============================================================================
// Module: proto_fifo
// Description: Parameterized Synchronous FIFO Queue for Protocol Emulator ASIC
// Features: Single-cycle push and pop, configurable depth, status flags
//=============================================================================

module proto_fifo #(
    parameter DATA_WIDTH = 16,
    parameter FIFO_DEPTH = 4,
    parameter ADDR_WIDTH = 2
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  push,
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  pop,
    output reg  [DATA_WIDTH-1:0] data_out,
    output wire                  empty,
    output wire                  full,
    output wire [ADDR_WIDTH:0]   level
);

    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0]   count;

    assign empty = (count == 0);
    assign full  = (count == FIFO_DEPTH);
    assign level = count;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr   <= {ADDR_WIDTH{1'b0}};
            rd_ptr   <= {ADDR_WIDTH{1'b0}};
            count    <= {(ADDR_WIDTH+1){1'b0}};
            data_out <= {DATA_WIDTH{1'b0}};
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            // Write operation
            if (push && !full) begin
                mem[wr_ptr] <= data_in;
                wr_ptr      <= wr_ptr + 1'b1;
            end

            // Read operation
            if (pop && !empty) begin
                data_out <= mem[rd_ptr];
                rd_ptr   <= rd_ptr + 1'b1;
            end else if (!empty) begin
                // Expose current head data when not empty
                data_out <= mem[rd_ptr];
            end

            // Count tracking
            case ({push && !full, pop && !empty})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count; // 2'b00 or 2'b11 (simultaneous push & pop)
            endcase
        end
    end

endmodule
