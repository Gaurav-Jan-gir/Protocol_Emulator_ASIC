`default_nettype none

//=============================================================================
// Module: proto_clock_prescaler
// Description: Integer and Fractional Clock Prescaler for Protocol Timing
// Generates cycle-exact 'tick' strobes to pace the micro-engine state machine
//=============================================================================

module proto_clock_prescaler (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [15:0] div_int,    // Integer divisor (1..65535). 0 = full speed
    input  wire [7:0]  div_frac,   // Fractional divisor (8-bit accumulator)
    output reg         tick        // Strobe output: 1 clock cycle pulse
);

    reg [15:0] count;
    reg [8:0]  frac_acc; // 9-bit to capture carry out
    reg        frac_carry;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count      <= 16'd0;
            frac_acc   <= 9'd0;
            frac_carry <= 1'b0;
            tick       <= 1'b0;
        end else if (!en) begin
            count      <= 16'd0;
            frac_acc   <= 9'd0;
            frac_carry <= 1'b0;
            tick       <= 1'b0;
        end else begin
            if (div_int == 16'd0) begin
                // Full speed: tick every master clock cycle
                tick  <= 1'b1;
                count <= 16'd0;
            end else begin
                // Calculate target period: div_int + (frac_carry ? 1 : 0)
                if (count >= (div_int + frac_carry - 16'd1)) begin
                    tick  <= 1'b1;
                    count <= 16'd0;

                    // Update fractional accumulator
                    frac_acc   <= frac_acc[7:0] + div_frac;
                    frac_carry <= frac_acc[8];
                end else begin
                    tick  <= 1'b0;
                    count <= count + 16'd1;
                end
            end
        end
    end

endmodule
