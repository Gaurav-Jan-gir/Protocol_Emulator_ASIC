`timescale 1ns / 1ps
`default_nettype none

//=============================================================================
// Testbench: tb_spi_loopback
// Description: Full-Duplex SPI Master (Engine 0) <-> SPI Slave (Engine 1)
// Mode 0: CPOL=0, CPHA=0, simultaneous bidirectional byte exchange
//=============================================================================

module tb_spi_loopback;

    reg        clk;
    reg        rst_n;

    // Host interface dedicated registers
    reg        host_sclk;
    reg        host_cs_n;
    reg        host_mosi;
    wire       host_miso;
    wire       host_irq;

    // Physical wires
    wire [7:0] ui_in;
    wire [7:0] uo_out;
    wire [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // Connect Host signals and loopback wires to ui_in cleanly
    // ui_in[0] = host_sclk
    // ui_in[1] = host_cs_n
    // ui_in[2] = host_mosi
    // ui_in[3] = E0 MISO (from E1 MISO: uo_out[5])
    // ui_in[4] = 0
    // ui_in[5] = E1 SCLK (from E0 SCLK: uo_out[4])
    // ui_in[6] = E1 CS_N (0 = selected)
    // ui_in[7] = 0
    assign ui_in[0] = host_sclk;
    assign ui_in[1] = host_cs_n;
    assign ui_in[2] = host_mosi;
    assign ui_in[3] = uo_out[5]; // E1 MISO -> E0 MISO
    assign ui_in[4] = 1'b0;
    assign ui_in[5] = uo_out[4]; // E0 SCLK -> E1 SCLK
    assign ui_in[6] = 1'b0;      // E1 Slave Select active low
    assign ui_in[7] = 1'b0;

    // uio_in[4] = E1 MOSI (from E0 MOSI: uo_out[2])
    assign uio_in = {3'b000, uo_out[2], 4'b0000};

    // Instantiate Top Module
    proto_emulator_top u_dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe)
    );

    // 50 MHz Master Clock (20ns period)
    always #10 clk = ~clk;

    // Host SPI Helper Tasks
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
                rdata[k]  = uo_out[0];
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
    reg [15:0] rx_word_e0;
    reg [15:0] rx_word_e1;

    reg [15:0] spi_master_code [0:31];
    reg [15:0] spi_slave_code [0:31];
    integer idx;

    
    always @(posedge clk) begin
        if (u_dut.u_engine_0.u_shifter.rx_fifo_push)
            $display("t=%0t [E0 PUSH] data=%h", $time, u_dut.u_engine_0.u_shifter.rx_fifo_din);
        if (u_dut.u_engine_1.u_shifter.rx_fifo_push)
            $display("t=%0t [E1 PUSH] data=%h", $time, u_dut.u_engine_1.u_shifter.rx_fifo_din);
    end
    initial begin

        $dumpfile("spi_loopback.vcd");
        $dumpvars(0, tb_spi_loopback);

        clk       = 0;
        rst_n     = 0;
        host_sclk = 0;
        host_cs_n = 1;
        host_mosi = 0;

        // Read compiled microcode
        $readmemh("asm/protocols/spi_master.hex", spi_master_code);
        $readmemh("asm/protocols/spi_slave.hex", spi_slave_code);

        #100;
        rst_n = 1;
        #100;

        $display("=== Step 1: Programming Engine 0 with SPI Master Firmware ===");
        for (idx = 0; idx < 11; idx = idx + 1) begin
            spi_write_reg(7'h10 + idx, spi_master_code[idx]);
        end

        $display("=== Step 2: Programming Engine 1 with SPI Slave Firmware ===");
        for (idx = 0; idx < 12; idx = idx + 1) begin
            spi_write_reg(7'h30 + idx, spi_slave_code[idx]);
        end

        $display("=== Step 3: Configuring Prescalers & Shifters ===");
        // Master clock divider = 10 (5 MHz SPI SCLK)
        // Slave clock divider = 0 (full 50 MHz speed to track SCLK edges)
        spi_write_reg(7'h02, 16'd10);
        spi_write_reg(7'h03, 16'd0);

        // Shift Left (MSB first)
        spi_write_reg(7'h05, 16'h0000);
        spi_write_reg(7'h06, 16'h0000);

        $display("=== Step 4: Loading Transmit Data into Queues ===");
        // Master sends 0x5A (MSB-first at bits [15:8] -> 0x5A00)
        spi_write_reg(7'h08, 16'h5A00);
        // Slave sends 0xC3 (MSB-first at bits [15:8] -> 0xC300)
        spi_write_reg(7'h09, 16'hC300);

        $display("=== Step 5: Enabling Engines ===");
        spi_write_reg(7'h00, 16'h0003); // Enable E0 and E1

        // Wait for 8-bit SPI transmission to complete
        #40000;

        $display("=== Step 6: Verifying Full-Duplex Data Transfer ===");
        // Read received data in Engine 0 (should be what Slave sent: 0xC3)
        spi_read_reg(7'h08, rx_word_e0);
        if (rx_word_e0[7:0] === 8'hC3) begin
            $display("[PASS] SPI Master received expected Slave byte: 0x%02X", rx_word_e0[7:0]);
        end else begin
            $display("[FAIL] SPI Master received: 0x%02X, expected: 0xC3", rx_word_e0[7:0]);
            errors = errors + 1;
        end

        // Read received data in Engine 1 (should be what Master sent: 0x5A)
        spi_read_reg(7'h09, rx_word_e1);
        if (rx_word_e1[7:0] === 8'h5A) begin
            $display("[PASS] SPI Slave received expected Master byte: 0x%02X", rx_word_e1[7:0]);
        end else begin
            $display("[FAIL] SPI Slave received: 0x%02X, expected: 0x5A", rx_word_e1[7:0]);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("=================================================");
            $display("  SPI FULL-DUPLEX LOOPBACK TEST PASSED (100%%)    ");
            $display("=================================================");
        end else begin
            $display("SPI LOOPBACK TEST FAILED WITH %0d ERRORS", errors);
        end

        $finish;
    end

endmodule
