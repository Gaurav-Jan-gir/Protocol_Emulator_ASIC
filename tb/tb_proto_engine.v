`timescale 1ns / 1ps
`default_nettype none

//=============================================================================
// Testbench: tb_proto_engine
// Description: Unit testbench verifying the ProtoPlex-8 micro-engine core.
// Validates single-cycle execution, delay counting, ALU, and branching.
//=============================================================================

module tb_proto_engine;

    reg         clk;
    reg         rst_n;
    reg         en;
    reg         tick;
    reg  [15:0] test_imem [0:31];
    wire [4:0]  imem_addr;
    wire [15:0] imem_inst = test_imem[imem_addr];

    reg  [3:0]  virt_in;
    wire [3:0]  virt_out;
    wire [3:0]  virt_oe;
    wire [1:0]  side_out;
    reg  [1:0]  irq_in;
    wire [1:0]  irq_out;

    reg         rx_fifo_full;
    wire        rx_fifo_push;
    wire [15:0] rx_fifo_din;

    reg         tx_fifo_empty;
    reg  [15:0] tx_fifo_dout;
    wire        tx_fifo_pop;

    wire [4:0]  pc_out;
    wire [15:0] reg_x;
    wire [15:0] reg_y;
    wire        is_waiting;

    proto_engine u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .en             (en),
        .tick           (tick),
        .imem_addr      (imem_addr),
        .imem_inst      (imem_inst),
        .virt_in        (virt_in),
        .virt_out       (virt_out),
        .virt_oe        (virt_oe),
        .side_out       (side_out),
        .irq_in         (irq_in),
        .irq_out        (irq_out),
        .rx_fifo_full   (rx_fifo_full),
        .rx_fifo_push   (rx_fifo_push),
        .rx_fifo_din    (rx_fifo_din),
        .tx_fifo_empty  (tx_fifo_empty),
        .tx_fifo_dout   (tx_fifo_dout),
        .tx_fifo_pop    (tx_fifo_pop),
        .shift_in_dir   (1'b0),
        .shift_out_dir  (1'b0),
        .autopush_en    (1'b0),
        .autopull_en    (1'b0),
        .push_threshold (5'd8),
        .pull_threshold (5'd8),
        .pc_out         (pc_out),
        .reg_x_out      (reg_x),
        .reg_y_out      (reg_y),
        .is_waiting     (is_waiting)
    );

    // 100 MHz clock (10ns period)
    always #5 clk = ~clk;

    integer i;
    integer errors = 0;

    initial begin
        $dumpfile("proto_engine_test.vcd");
        $dumpvars(0, tb_proto_engine);

        clk           = 0;
        rst_n         = 0;
        en            = 0;
        tick          = 1;
        virt_in       = 4'b0000;
        irq_in        = 2'b00;
        rx_fifo_full  = 0;
        tx_fifo_empty = 1;
        tx_fifo_dout  = 16'h0000;

        for (i = 0; i < 32; i = i + 1) begin
            test_imem[i] = 16'h0000;
        end

        // Program microcode for Unit Tests:
        // 0x00: SET X, 5       (Opcode SET: 3'b110, Delay: 0, Dst X: 001, Data: 5) -> 0xC025
        // 0x01: SET Y, 3       (Opcode SET: 3'b110, Delay: 0, Dst Y: 010, Data: 3) -> 0xC043
        // 0x02: ALU ADD        (Opcode ALU: 3'b111, Delay: 0, Op ADD: 000)         -> 0xE000
        // 0x03: SET PINS, 10   (Opcode SET: 3'b110, Delay: 2, Dst PINS: 000, Data: 10) -> 0xC20A
        // 0x04: JMP !X, 0x07   (Opcode JMP: 3'b000, Cond !X: 001, Target: 7)       -> 0x0027
        // 0x05: ALU DEC        (Opcode ALU: 3'b111, Delay: 0, Op DEC: 110)         -> 0xE0C0
        // 0x06: JMP ALWAYS, 0x04 (Opcode JMP: 3'b000, Cond ALWAYS: 000, Target: 4) -> 0x0004
        // 0x07: SET PINS, 15   (Done marker)                                       -> 0xC00F

        test_imem[0] = 16'hC025; // SET X, 5
        test_imem[1] = 16'hC043; // SET Y, 3
        test_imem[2] = 16'hE000; // ADD X, Y -> X = 8
        test_imem[3] = 16'hC20A; // SET PINS, 10 [delay 2]
        test_imem[4] = 16'h0027; // JMP !X, 0x07
        test_imem[5] = 16'hE0C0; // DEC X
        test_imem[6] = 16'h0004; // JMP ALWAYS, 4
        test_imem[7] = 16'hC00F; // SET PINS, 15
        test_imem[8] = 16'h0008; // JMP ALWAYS, 8 (Halt/Loop on self)

        #20;
        rst_n = 1;
        #10;
        en = 1;

        // Step 1: Execute SET X, 5
        @(posedge clk); #1;
        if (reg_x !== 16'd5) begin
            $display("[FAIL] Expected X=5, got %d", reg_x);
            errors = errors + 1;
        end else begin
            $display("[PASS] SET X, 5 verified. X = %d", reg_x);
        end

        // Step 2: Execute SET Y, 3
        @(posedge clk); #1;
        if (reg_y !== 16'd3) begin
            $display("[FAIL] Expected Y=3, got %d", reg_y);
            errors = errors + 1;
        end else begin
            $display("[PASS] SET Y, 3 verified. Y = %d", reg_y);
        end

        // Step 3: Execute ADD X, Y -> X should be 8
        @(posedge clk); #1;
        if (reg_x !== 16'd8) begin
            $display("[FAIL] Expected X=8 after ADD, got %d", reg_x);
            errors = errors + 1;
        end else begin
            $display("[PASS] ALU ADD verified. X = %d", reg_x);
        end

        // Step 4: Execute SET PINS, 10 with delay 2
        @(posedge clk); #1;
        if (virt_out !== 4'd10) begin
            $display("[FAIL] Expected virt_out=10, got %d", virt_out);
            errors = errors + 1;
        end else begin
            $display("[PASS] SET PINS, 10 output verified. virt_out = %d", virt_out);
        end

        // Check delay execution: PC holds at 3 on delay cycle 1, then advances
        @(posedge clk); #1;
        if (pc_out !== 5'd3) begin
            $display("[FAIL] Delay cycle 1 failed! PC = %d", pc_out);
            errors = errors + 1;
        end else begin
            $display("[PASS] Delay cycle 1 verified: PC = 3, delay active");
        end

        @(posedge clk); #1;
        if (pc_out !== 5'd4) begin
            $display("[FAIL] Delay cycle 2 failed! PC = %d", pc_out);
            errors = errors + 1;
        end else begin
            $display("[PASS] Delay cycle 2 verified: PC = 4, delay active");
        end

        // Step 5: Wait for countdown loop to reach PC 7 (SET PINS, 15)
        repeat (100) @(posedge clk);

        if (virt_out === 4'd15 && pc_out === 5'd8) begin
            $display("[PASS] Conditional jump JMP !X loop successfully reached termination! X = %d", reg_x);
        end else begin
            $display("[FAIL] Loop failed to terminate properly! PC=%d, virt_out=%d, X=%d", pc_out, virt_out, reg_x);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("=================================================");
            $display("  ALL PROTO_ENGINE UNIT TESTS PASSED (100%%)     ");
            $display("=================================================");
        end else begin
            $display("TEST FAILED WITH %0d ERRORS", errors);
        end

        $finish;
    end

endmodule
