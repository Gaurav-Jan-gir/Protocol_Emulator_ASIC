`timescale 1ns / 1ps
`default_nettype none

//=============================================================================
// Testbench: tb_i2c_bus
// Description: Verification of I2C Master (ProtoPlex-8 Engine 0) operating with
// an external behavioral I2C Slave across open-drain bidirectional SDA and SCL
// lines with pull-up resistors and clock stretching.
//=============================================================================

module tb_i2c_bus;

    reg        clk;
    reg        rst_n;

    // Host SPI Interface
    reg        host_sclk;
    reg        host_cs_n;
    reg        host_mosi;
    wire       host_miso;
    wire       host_irq;

    // Tiny Tapeout Pins
    wire [7:0] ui_in;
    wire [7:0] uo_out;
    wire [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // Host SPI pin mapping
    assign ui_in[0] = host_sclk;
    assign ui_in[1] = host_cs_n;
    assign ui_in[2] = host_mosi;
    assign ui_in[7:3] = 5'b00000;

    // Open-Drain Bus Signals with Pull-ups
    // uio[0] = SDA, uio[1] = SCL
    reg slave_sda_oe;
    reg slave_scl_oe;

    // When either DUT or Slave drives 0 (oe=1, out=0), the bus is 0;
    // otherwise the external pull-up pulls it high to 1.
    wire bus_sda = !((uio_oe[0] && !uio_out[0]) || slave_sda_oe);
    wire bus_scl = !((uio_oe[1] && !uio_out[1]) || slave_scl_oe);

    assign uio_in[0]   = bus_sda;
    assign uio_in[1]   = bus_scl;
    assign uio_in[7:2] = 6'b000000;

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

    // 50 MHz Clock (20ns period)
    always #10 clk = ~clk;

    // SPI Helper Tasks
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

    // Behavioral I2C Slave Model
    reg start_detected;
    reg stop_detected;
    reg [7:0] slave_rx_byte;
    integer bit_idx;
    reg prev_sda;
    reg prev_scl;

    // Detect START condition: falling edge of SDA while SCL is high
    always @(negedge bus_sda) begin
        if (bus_scl && rst_n) begin
            start_detected <= 1'b1;
            $display("t=%0t [I2C SLAVE] START condition detected on bus!", $time);
        end
    end

    // Detect STOP condition: rising edge of SDA while SCL is high
    always @(posedge bus_sda) begin
        if (bus_scl && rst_n) begin
            stop_detected <= 1'b1;
            $display("t=%0t [I2C SLAVE] STOP condition detected on bus!", $time);
        end
    end

    // Slave byte reception & ACK generation
    initial begin
        slave_sda_oe   = 0;
        slave_scl_oe   = 0;
        start_detected = 0;
        stop_detected  = 0;
        slave_rx_byte  = 8'd0;

        forever begin
            @(posedge start_detected);
            start_detected = 0;

            // Sample 8 data bits on rising edges of SCL
            for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                @(posedge bus_scl);
                slave_rx_byte[bit_idx] = bus_sda;
            end

            $display("t=%0t [I2C SLAVE] Received Address/Data byte: 0x%02X", $time, slave_rx_byte);

            // Wait for SCL to fall before driving ACK
            @(negedge bus_scl);
            slave_sda_oe = 1'b1; // Pull SDA low to ACK

            // Clock stretching demonstration: hold SCL low for 100ns
            slave_scl_oe = 1'b1;
            #100;
            slave_scl_oe = 1'b0; // Release SCL

            // Hold ACK through SCL rising edge
            @(posedge bus_scl);
            $display("t=%0t [I2C SLAVE] ACK asserted to Master", $time);

            // Release SDA after SCL falls
            @(negedge bus_scl);
            slave_sda_oe = 1'b0; // Release SDA
        end
    end

    integer errors = 0;
    reg [15:0] i2c_master_code [0:31];
    reg [15:0] ack_result;
    integer idx;

    initial begin
        $dumpfile("i2c_bus.vcd");
        $dumpvars(0, tb_i2c_bus);

        clk       = 0;
        rst_n     = 0;
        host_sclk = 0;
        host_cs_n = 1;
        host_mosi = 0;

        $readmemh("asm/protocols/i2c_master.hex", i2c_master_code);

        #100;
        rst_n = 1;
        #100;

        $display("=== Step 1: Programming Engine 0 with I2C Master Firmware ===");
        for (idx = 0; idx < 22; idx = idx + 1) begin
            spi_write_reg(7'h10 + idx, i2c_master_code[idx]);
        end

        $display("=== Step 2: Configuring Clock Prescaler & Open-Drain Pin Mode ===");
        // Master clock divider = 10 (5 MHz core instruction rate, ~500 kHz I2C SCL)
        spi_write_reg(7'h02, 16'd10);

        // Configure uio[0] (SDA) and uio[1] (SCL) as open-drain
        spi_write_reg(7'h07, 16'h0003);

        // Shift Left (MSB first)
        spi_write_reg(7'h05, 16'h0000);

        $display("=== Step 3: Enabling Engine 0 ===");
        spi_write_reg(7'h00, 16'h0001); // Enable E0

        #2000;

        $display("=== Step 4: Transmitting I2C Slave Address 0xA6 ===");
        // Load Address 0xA6 into TX FIFO (MSB first at bits [15:8] -> 0xA600)
        spi_write_reg(7'h08, 16'hA600);

        // Wait for I2C frame (START + 8 bits + ACK + STOP) to complete
        #80000;

        $display("=== Step 5: Verifying I2C Bus Transaction & ACK Status ===");
        if (slave_rx_byte === 8'hA6) begin
            $display("[PASS] I2C Slave correctly decoded address: 0x%02X", slave_rx_byte);
        end else begin
            $display("[FAIL] I2C Slave received: 0x%02X, expected: 0xA6", slave_rx_byte);
            errors = errors + 1;
        end

        if (stop_detected) begin
            $display("[PASS] STOP condition successfully detected on I2C bus");
        end else begin
            $display("[FAIL] STOP condition not observed on I2C bus!");
            errors = errors + 1;
        end

        // Read ACK result from Engine 0 RX FIFO
        spi_read_reg(7'h08, ack_result);
        if (ack_result[0] === 1'b0) begin
            $display("[PASS] Master successfully captured Slave ACK (ACK bit = 0)");
        end else begin
            $display("[FAIL] Master captured NACK (ACK bit = %b)", ack_result[0]);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("=================================================");
            $display("    I2C BUS OPEN-DRAIN TEST PASSED (100%%)        ");
            $display("=================================================");
        end else begin
            $display("I2C BUS TEST FAILED WITH %0d ERRORS", errors);
        end

        $finish;
    end

endmodule