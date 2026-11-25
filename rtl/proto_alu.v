`default_nettype none

//=============================================================================
// Module: proto_alu
// Description: Arithmetic and Logic Unit for Protocol Execution Engine
// Operations: ADD, SUB, AND, OR, XOR, INC, DEC, CMP, BITREV, NOT
//=============================================================================

module proto_alu (
    input  wire [2:0]  op,        // ALU operation selector
    input  wire [15:0] in_a,      // Operand A (typically register X)
    input  wire [15:0] in_b,      // Operand B (typically register Y or immediate)
    output reg  [15:0] result,    // ALU calculation output
    output wire        zero_flag, // Asserted when result is 0
    output wire        neg_flag,  // Asserted when MSB of result is 1
    output wire        carry_flag // Carry/Borrow output
);

    // Operation codes
    localparam ALU_ADD    = 3'b000;
    localparam ALU_SUB    = 3'b001;
    localparam ALU_AND    = 3'b010;
    localparam ALU_OR     = 3'b011;
    localparam ALU_XOR    = 3'b100;
    localparam ALU_INC    = 3'b101;
    localparam ALU_DEC    = 3'b110;
    localparam ALU_BITREV = 3'b111;

    reg [16:0] ext_result;

    always @(*) begin
        case (op)
            ALU_ADD:    ext_result = {1'b0, in_a} + {1'b0, in_b};
            ALU_SUB:    ext_result = {1'b0, in_a} - {1'b0, in_b};
            ALU_AND:    ext_result = {1'b0, (in_a & in_b)};
            ALU_OR:     ext_result = {1'b0, (in_a | in_b)};
            ALU_XOR:    ext_result = {1'b0, (in_a ^ in_b)};
            ALU_INC:    ext_result = {1'b0, in_a} + 17'd1;
            ALU_DEC:    ext_result = {1'b0, in_a} - 17'd1;
            ALU_BITREV: ext_result = {1'b0,
                in_a[0],  in_a[1],  in_a[2],  in_a[3],
                in_a[4],  in_a[5],  in_a[6],  in_a[7],
                in_a[8],  in_a[9],  in_a[10], in_a[11],
                in_a[12], in_a[13], in_a[14], in_a[15]
            };
            default: ext_result = 17'd0;
        endcase
        result = ext_result[15:0];
    end

    assign zero_flag  = (result == 16'h0000);
    assign neg_flag   = result[15];
    assign carry_flag = ext_result[16];

endmodule
