`default_nettype none

//=============================================================================
// Module: proto_pin_crossbar
// Description: Dynamic Pin Crossbar and Open-Drain Tri-State Controller
// Interfaces Engine 0, Engine 1, and the Host Controller to the Tiny Tapeout I/O.
//=============================================================================

module proto_pin_crossbar (
    // Tiny Tapeout Physical Pins
    input  wire [7:0] ui_in,
    output reg  [7:0] uo_out,
    input  wire [7:0] uio_in,
    output reg  [7:0] uio_out,
    output reg  [7:0] uio_oe,

    // Host SPI Interface Pins
    output wire       host_sclk,
    output wire       host_cs_n,
    output wire       host_mosi,
    input  wire       host_miso,
    input  wire       host_irq,

    // Engine 0 Virtual Pins
    output reg  [3:0] e0_virt_in,
    input  wire [3:0] e0_virt_out,
    input  wire [3:0] e0_virt_oe,
    input  wire [1:0] e0_side_out,

    // Engine 1 Virtual Pins
    output reg  [3:0] e1_virt_in,
    input  wire [3:0] e1_virt_out,
    input  wire [3:0] e1_virt_oe,
    input  wire [1:0] e1_side_out,

    // Crossbar Configuration Registers
    input  wire [7:0] cfg_pin_mode // Bit 0: E0 pin 0 open-drain, Bit 1: E0 pin 1 open-drain, etc.
);

    // Host pin assignments
    assign host_sclk = ui_in[0];
    assign host_cs_n = ui_in[1];
    assign host_mosi = ui_in[2];

    always @(*) begin
        // Map Physical Inputs to Engine 0 Virtual Inputs
        // In open-drain mode (cfg_pin_mode), virtual inputs read the bidirectional bus pins
        e0_virt_in[0] = cfg_pin_mode[0] ? uio_in[0] : ui_in[3];
        e0_virt_in[1] = cfg_pin_mode[1] ? uio_in[1] : ui_in[4];
        e0_virt_in[2] = uio_in[0];
        e0_virt_in[3] = uio_in[1];

        // Map Physical Inputs to Engine 1 Virtual Inputs
        e1_virt_in[0] = cfg_pin_mode[4] ? uio_in[4] : ui_in[5];
        e1_virt_in[1] = cfg_pin_mode[5] ? uio_in[5] : ui_in[6];
        e1_virt_in[2] = uio_in[4];
        e1_virt_in[3] = uio_in[5];

        // -----------------------------------------------------------------
        // Dedicated Outputs (uo_out[7:0])
        // -----------------------------------------------------------------
        uo_out[0] = host_miso;
        uo_out[1] = host_irq;
        uo_out[2] = e0_virt_out[0];  // Engine 0 primary output (e.g. UART TX)
        uo_out[3] = e0_virt_out[1];  // Engine 0 secondary output
        uo_out[4] = e0_side_out[0];  // Engine 0 side-set (e.g. SPI SCLK)
        uo_out[5] = e1_virt_out[0];  // Engine 1 primary output
        uo_out[6] = e1_virt_out[1];  // Engine 1 secondary output
        uo_out[7] = e1_side_out[0];  // Engine 1 side-set

        // -----------------------------------------------------------------
        // Bidirectional Pins (uio[7:0]) with Open-Drain Mode Emulation
        // -----------------------------------------------------------------
        // uio[0]: Engine 0 pin 2 (e.g. I2C SDA or 1-Wire DQ)
        if (cfg_pin_mode[0]) begin
            // Open-drain: 0 asserts low, 1 floats (high-Z)
            uio_out[0] = 1'b0;
            uio_oe[0]  = ~e0_virt_out[0];
        end else begin
            uio_out[0] = e0_virt_out[0];
            uio_oe[0]  = e0_virt_oe[0];
        end

        // uio[1]: Engine 0 pin 3 (e.g. I2C SCL)
        if (cfg_pin_mode[1]) begin
            // Open-drain driven by side_out[0]
            uio_out[1] = 1'b0;
            uio_oe[1]  = ~e0_side_out[0];
        end else begin
            uio_out[1] = e0_virt_out[1];
            uio_oe[1]  = e0_virt_oe[1];
        end

        // uio[2]: Engine 0 side-set pin 1
        uio_out[2] = e0_side_out[1];
        uio_oe[2]  = 1'b1;

        // uio[3]: Reserved / Loopback
        uio_out[3] = 1'b0;
        uio_oe[3]  = 1'b0;

        // uio[4]: Engine 1 pin 2 (e.g. I2C SDA)
        if (cfg_pin_mode[4]) begin
            uio_out[4] = 1'b0;
            uio_oe[4]  = ~e1_virt_out[0];
        end else begin
            uio_out[4] = e1_virt_out[0];
            uio_oe[4]  = e1_virt_oe[0];
        end

        // uio[5]: Engine 1 pin 3 (e.g. I2C SCL)
        if (cfg_pin_mode[5]) begin
            uio_out[5] = 1'b0;
            uio_oe[5]  = ~e1_side_out[0];
        end else begin
            uio_out[5] = e1_virt_out[1];
            uio_oe[5]  = e1_virt_oe[1];
        end

        // uio[6]: Engine 1 side-set pin 1
        uio_out[6] = e1_side_out[1];
        uio_oe[6]  = 1'b1;

        // uio[7]: Reserved
        uio_out[7] = 1'b0;
        uio_oe[7]  = 1'b0;
    end

endmodule
