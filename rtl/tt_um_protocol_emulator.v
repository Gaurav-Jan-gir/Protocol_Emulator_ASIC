`default_nettype none

//=============================================================================
// Module: tt_um_protocol_emulator
// Description: Tiny Tapeout Top-Level Wrapper for ProtoPlex-8 Protocol Emulator
// Adheres strictly to Tiny Tapeout standard pinout and power specifications.
//=============================================================================

module tt_um_protocol_emulator (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // Bidirectional IOs: Input path
    output wire [7:0] uio_out,  // Bidirectional IOs: Output path
    output wire [7:0] uio_oe,   // Bidirectional IOs: Enable path (active high)
    input  wire       ena,      // Power enable (1 when powered)
    input  wire       clk,      // System clock
    input  wire       rst_n     // Active-low asynchronous reset
);

    // Gated active-low reset with enable
    wire sys_rst_n = rst_n && ena;

    proto_emulator_top u_core (
        .clk     (clk),
        .rst_n   (sys_rst_n),
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe)
    );

endmodule
