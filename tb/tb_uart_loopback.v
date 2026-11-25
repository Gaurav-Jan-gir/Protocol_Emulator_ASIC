`timescale 1ns / 1ps
`default_nettype none

//=============================================================================
// Testbench: tb_uart_loopback
// Description: End-to-end Full-Duplex UART TX -> RX Loopback Verification
// Engine 0: Transmits 8N1 serial byte stream from TX FIFO
// Engine 1: Receives serial bit stream into RX FIFO with start-bit detection
//=============================================================================

module tb_uart_loopback;

    reg        clk;
    reg        rst_n;

    // Host SPI Dedicated Driver Signals
    reg        host_sclk;
    reg        host_cs_n;
    reg        host_mosi;

    // Physical Tiny Tapeout Wires
    wire [7:0] ui_in;
    wire [7:0] uo_out;
    wire [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // Pin Assignments:
    // ui_in[0] = host_sclk
    // ui_in[1] = host_cs_n
    // ui_in[2] = host_mosi
    // ui_in[5] = E1 RX (connected to E0 TX: uo_out[2])
    assign ui_in[0] = host_sclk;
    assign ui_in[1] = host_cs_n;
    assign ui_in[2] = host_mosi;
    assign ui_in[3] = 1'b0;
    assign ui_in[4] = 1'b0;
    assign ui_in[5] = uo_out[2]; // UART Loopback: TX -> RX
    assign ui_in[6] = 1'b0;
    assign ui_in[7] = 1'b0;

    assign uio_in   = 8'h00;

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
            spi_send_byte({1'b0, addr});     // Write command
            spi_send_byte(data[15:8]);       // Data high byte
            spi_send_byte(data[7:0]);        // Data low byte
            #40;
            host_cs_n = 1; // CS_N deassert
            #100;
        end
    endtask

    task spi_read_reg(input [6:0] addr, output [15:0] data);
        integer k;
        reg [15:0] rdata;
        begin
            host_cs_n = 0;
            #40;
            spi_send_byte({1'b1, addr}); // Read command
            rdata = 16'd0;
            for (k = 15; k >= 0; k = k - 1) begin
                #40;
                host_sclk = 1; // SCLK rising captures MISO
                #20;           // Wait for slave double-flop synchronizer
                rdata[k]  = uo_out[0];
                #20;
                host_sclk = 0;
            end
            data = rdata;
            #40;
            host_cs_n = 1; // CS_N deassert
            #100;
        end
    endtask

    integer errors = 0;
    reg [15:0] rx_word;
    reg [15:0] status_val;

    // Arrays to load compiled hex
    reg [15:0] uart_tx_code [0:31];
    reg [15:0] uart_rx_code [0:31];
    integer idx;

    
    
    
    initial begin
        $dumpfile("uart_loopback.vcd");
        $dumpvars(0, tb_uart_loopback);

        clk       = 0;
        rst_n     = 0;
        host_sclk = 0;
        host_cs_n = 1;
        host_mosi = 0;

        // Read compiled microcode from hex files
        $readmemh("asm/protocols/uart_tx.hex", uart_tx_code);
        $readmemh("asm/protocols/uart_rx.hex", uart_rx_code);

        #100;
        rst_n = 1;
        #100;

        $display("=== Step 1: Programming Engine 0 with UART TX Firmware ===");
        for (idx = 0; idx < 9; idx = idx + 1) begin
            spi_write_reg(7'h10 + idx, uart_tx_code[idx]);
        end

        $display("=== Step 2: Programming Engine 1 with UART RX Firmware ===");
        for (idx = 0; idx < 10; idx = idx + 1) begin
            spi_write_reg(7'h30 + idx, uart_rx_code[idx]);
        end

        $display("=== Step 3: Configuring Clock Prescalers & Shifters ===");
        // Fast simulation baud: Prescaler divisor = 10 (50MHz / 10 = 5 MHz baud)
        spi_write_reg(7'h02, 16'd10); // E0 clock div
        spi_write_reg(7'h03, 16'd10); // E1 clock div

        // Configure shift directions: Shift Right (LSB first for UART)
        // push_threshold = 8 (bits 8:4 = 8 -> 0x0081)
        spi_write_reg(7'h05, 16'h0002); // E0: Shift Out Right
        spi_write_reg(7'h06, 16'h0081); // E1: Shift In Right, push_threshold = 8

        $display("=== Step 4: Loading Test Bytes into E0 TX FIFO ===");
        spi_write_reg(7'h08, 16'h00A5); // Byte 1: 0xA5
        spi_write_reg(7'h08, 16'h003C); // Byte 2: 0x3C

        $display("=== Step 5: Enabling Both Engines ===");
        spi_write_reg(7'h00, 16'h0003); // Enable Engine 0 (bit 0) and Engine 1 (bit 1)

        // Wait for transmissions to complete (approx 20 bit periods per byte)
        $display("=== Step 6: Waiting for Serial Transmission & Deserialization ===");
        #50000;

        // Check if RX1 FIFO received data
        spi_read_reg(7'h01, status_val);
        $display("Status word: 0x%04X (E1 RX Empty flag = %b)", status_val, status_val[15]);

        // Pop Byte 1
        spi_read_reg(7'h09, rx_word);
        if (rx_word[7:0] === 8'hA5) begin
            $display("[PASS] Received Byte 1 matches: 0x%02X (Expected: 0xA5)", rx_word[7:0]);
        end else begin
            $display("[FAIL] Byte 1 mismatch! Got: 0x%02X, Expected: 0xA5", rx_word[7:0]);
            errors = errors + 1;
        end

        // Pop Byte 2
        spi_read_reg(7'h09, rx_word);
        if (rx_word[7:0] === 8'h3C) begin
            $display("[PASS] Received Byte 2 matches: 0x%02X (Expected: 0x3C)", rx_word[7:0]);
        end else begin
            $display("[FAIL] Byte 2 mismatch! Got: 0x%02X, Expected: 0x3C", rx_word[7:0]);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("=================================================");
            $display("  UART FULL-DUPLEX LOOPBACK TEST PASSED (100%%)   ");
            $display("=================================================");
        end else begin
            $display("UART LOOPBACK TEST FAILED WITH %0d ERRORS", errors);
        end

        $finish;
    end

endmodule
