`default_nettype none

//=============================================================================
// Module: proto_imem
// Description: Dual-Port Instruction RAM for Protocol Emulator Execution Core
// Port A: Synchronous read for the execution pipeline
// Port B: Synchronous write / read by Host Interface
//=============================================================================

module proto_imem #(
    parameter ADDR_WIDTH = 5,   // 32 instructions
    parameter DATA_WIDTH = 16   // 16-bit instruction word
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Port A: Engine execution interface (asynchronous combinational read)
    input  wire [ADDR_WIDTH-1:0] addr_a,
    output wire [DATA_WIDTH-1:0] dout_a,

    // Port B: Host programming interface
    input  wire                  we_b,
    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [DATA_WIDTH-1:0] din_b,
    output reg  [DATA_WIDTH-1:0] dout_b
);

    localparam MEM_DEPTH = (1 << ADDR_WIDTH);
    reg [DATA_WIDTH-1:0] ram [0:MEM_DEPTH-1];

    integer i;

    // Asynchronous read for execution pipeline (zero latency combinational lookup)
    assign dout_a = ram[addr_a];

    // Synchronous memory operations for Host Port B
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_b <= 16'h0000;
            for (i = 0; i < MEM_DEPTH; i = i + 1) begin
                ram[i] <= 16'h0000; // Default NOP
            end
        end else begin
            if (we_b) begin
                ram[addr_b] <= din_b;
                dout_b      <= din_b;
            end else begin
                dout_b      <= ram[addr_b];
            end
        end
    end

endmodule
