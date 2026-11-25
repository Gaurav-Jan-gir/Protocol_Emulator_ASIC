`timescale 1ns / 1ps
`default_nettype none

//=============================================================================
// Testbench: tb_tinytapeout_top
// Description: Official Tiny Tapeout Top-Level Integration Test
// Verifies tt_um_protocol_emulator wrapper, ena power pin, reset behavior,
// and host SPI register access through dedicated I/O pins.
//=============================================================================

module tb_tinytapeout_top;

    reg        clk;
    reg        rst_n;
    reg        ena;

    // Dedicated TT Pins
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // Host SPI signals mapped to ui_in
    reg  host_sclk;
    reg  host_cs_n;
    reg  host_mosi;
    wire host_miso = uo_out[0];
    wire host_irq  = uo_out[1];

    always @(*) begin
        ui_in[0] = host_sclk;
        ui_in[1] = host_cs_n;
        ui_in[2] = host_mosi;
        ui_in[7:3] = 5'b00000;
    end

    // Device Under Test: Official Tiny Tapeout Top Module
    tt_um_protocol_emulator u_dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    // 50 MHz Master Clock (20ns period)
    always #10 clk = ~clk;

    // Host SPI Tasks
    task spi_send_byte(input [7:0] b);
        integer k;
        begin
            for (k = 7; k >= 0; k = k - 1) begin
                host_mosi = b[k];
                #40;
                host_sclk = 1;
                #40;
                host_sclk = 0;
            end
        end
    endtask

    task spi_write_reg(input [6:0] addr, input [15:0] data);
        begin
            host_cs_n = 0;
            #40;
            spi_send_byte({1'b0, addr});
            spi_send_byte(data[15:8]);
            spi_send_byte(data[7:0]);
            #40;
            host_cs_n = 1;
            #100;
        end
    endtask

    task spi_read_reg(input [6:0] addr, output [15:0] data);
        integer k;
        reg [15:0] rdata;
        begin
            host_cs_n = 0;
            #40;
            spi_send_byte({1'b1, addr});
            rdata = 16'd0;
            for (k = 15; k >= 0; k = k - 1) begin
                #40;
                host_sclk = 1;
                #20;
                rdata[k]  = host_miso;
                #20;
                host_sclk = 0;
            end
            data = rdata;
            #40;
            host_cs_n = 1;
            #100;
        end
    endtask

    integer errors = 0;
    reg [15:0] readback_val;

    initial begin
        $dumpfile("tinytapeout_top.vcd");
        $dumpvars(0, tb_tinytapeout_top);

        clk       = 0;
        rst_n     = 0;
        ena       = 0;
        host_sclk = 0;
        host_cs_n = 1;
        host_mosi = 0;
        uio_in    = 8'h00;

        #100;

        $display("=== Step 1: Testing Power Enable (ena = 0 holds reset) ===");
        rst_n = 1; // rst_n high, but ena still 0
        #100;
        // With ena=0, writes should be ignored / reset holds
        spi_write_reg(7'h02, 16'h1234);
        spi_read_reg(7'h02, readback_val);
        if (readback_val === 16'h0000) begin
            $display("[PASS] When ena=0, core reset holds and registers remain 0");
        end else begin
            $display("[FAIL] Core operated when ena=0! Val = 0x%04X", readback_val);
            errors = errors + 1;
        end

        $display("=== Step 2: Enabling Chip (ena = 1, rst_n = 1) ===");
        ena = 1;
        #100;

        $display("=== Step 3: Register Read/Write Integrity Test ===");
        // Write prescaler 0x002A (42 decimal)
        spi_write_reg(7'h02, 16'h002A);
        spi_read_reg(7'h02, readback_val);
        if (readback_val === 16'h002A) begin
            $display("[PASS] Prescaler E0 Register readback matches: 0x%04X", readback_val);
        end else begin
            $display("[FAIL] Prescaler E0 Register readback: 0x%04X (Expected: 0x002A)", readback_val);
            errors = errors + 1;
        end

        // Write pin mode register 0x0033
        spi_write_reg(7'h07, 16'h0033);
        spi_read_reg(7'h07, readback_val);
        if (readback_val === 16'h0033) begin
            $display("[PASS] Pin Mode Configuration readback matches: 0x%04X", readback_val);
        end else begin
            $display("[FAIL] Pin Mode Register readback: 0x%04X (Expected: 0x0033)", readback_val);
            errors = errors + 1;
        end

        $display("=== Step 4: Status Word Default Verification ===");
        spi_read_reg(7'h01, readback_val);
        // Status word bits [15:12] report empty/full flags:
        // bit 15: e1_rx_empty=1, bit 14: e1_tx_full=0, bit 13: e0_rx_empty=1, bit 12: e0_tx_full=0 -> 0xA000
        if (readback_val[15] === 1'b1 && readback_val[13] === 1'b1) begin
            $display("[PASS] Status word correctly reports empty RX FIFOs: 0x%04X", readback_val);
        end else begin
            $display("[FAIL] Status word unexpected: 0x%04X", readback_val);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("=================================================");
            $display("  TINYTAPEOUT TOP-LEVEL WRAPPER TEST PASSED!     ");
            $display("=================================================");
        end else begin
            $display("TINYTAPEOUT TOP TEST FAILED WITH %0d ERRORS", errors);
        end

        $finish;
    end

endmodule