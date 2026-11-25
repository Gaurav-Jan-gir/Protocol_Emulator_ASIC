`default_nettype none

//=============================================================================
// Module: proto_engine
// Description: Deterministic Micro-Engine Core for Protocol Emulation
// Features: Single-cycle base execution, 5-bit hardware delay counter,
// conditional jumps, scratch registers X & Y, shift registers, and cycle-exact I/O.
//=============================================================================

module proto_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        tick,              // Prescaled clock strobe

    // Instruction Memory Interface
    output wire [4:0]  imem_addr,
    input  wire [15:0] imem_inst,

    // Virtual I/O Pins
    input  wire [3:0]  virt_in,
    output reg  [3:0]  virt_out,
    output reg  [3:0]  virt_oe,
    output reg  [1:0]  side_out,

    // Inter-engine IRQ flags
    input  wire [1:0]  irq_in,
    output reg  [1:0]  irq_out,

    // FIFO Interface
    input  wire        rx_fifo_full,
    output wire        rx_fifo_push,
    output wire [15:0] rx_fifo_din,

    input  wire        tx_fifo_empty,
    input  wire [15:0] tx_fifo_dout,
    output wire        tx_fifo_pop,

    // Shifter configuration
    input  wire        shift_in_dir,
    input  wire        shift_out_dir,
    input  wire        autopush_en,
    input  wire        autopull_en,
    input  wire [4:0]  push_threshold,
    input  wire [4:0]  pull_threshold,

    // Diagnostics & State
    output wire [4:0]  pc_out,
    output wire [15:0] reg_x_out,
    output wire [15:0] reg_y_out,
    output wire        is_waiting
);

    // Engine Registers
    reg [4:0]  pc;
    reg [4:0]  next_pc;
    reg [4:0]  delay_ctr;
    reg [15:0] reg_x;
    reg [15:0] reg_y;

    assign pc_out    = pc;
    assign imem_addr = pc;
    assign reg_x_out = reg_x;
    assign reg_y_out = reg_y;

    // Instruction Decode Fields
    wire [2:0] opcode   = imem_inst[15:13];
    wire [4:0] inst_dly = imem_inst[12:8];
    wire [7:0] payload  = imem_inst[7:0];

    // Sub-fields for instructions
    wire [2:0] jmp_cond   = payload[7:5];
    wire [4:0] jmp_target = payload[4:0];

    wire       wait_pol   = payload[7];
    wire [2:0] wait_src   = payload[6:4];

    wire [2:0] in_src     = payload[7:5];
    wire [4:0] in_len_raw = payload[4:0];
    wire [4:0] in_nbits   = (in_len_raw == 5'd0) ? 5'd16 : in_len_raw;

    wire [2:0] out_dst    = payload[7:5];
    wire [4:0] out_len_raw= payload[4:0];
    wire [4:0] out_nbits  = (out_len_raw == 5'd0) ? 5'd16 : out_len_raw;

    wire       push_pull_sel = payload[7]; // 0=push, 1=pull

    wire [3:0] mov_dst    = payload[7:4];
    wire [3:0] mov_src    = payload[3:0];

    wire [2:0] set_dst    = payload[7:5];
    wire [4:0] set_data   = payload[4:0];

    wire [2:0] alu_op     = payload[7:5];

    // ALU instantiation
    wire [15:0] alu_result;
    wire        alu_zero, alu_neg, alu_carry;
    proto_alu u_alu (
        .op         (alu_op),
        .in_a       (reg_x),
        .in_b       (reg_y),
        .result     (alu_result),
        .zero_flag  (alu_zero),
        .neg_flag   (alu_neg),
        .carry_flag (alu_carry)
    );

    // Shifter signals
    wire [15:0] out_data_slice;
    wire [15:0] isr_val;
    wire [15:0] osr_val;
    wire        osr_empty;
    wire [4:0]  osr_remain;

    // IN source multiplexer
    reg  [15:0] in_data_mux;
    always @(*) begin
        case (in_src)
            3'b000: in_data_mux = {15'd0, virt_in[0]};
            3'b001: in_data_mux = {15'd0, virt_in[1]};
            3'b010: in_data_mux = {15'd0, virt_in[2]};
            3'b011: in_data_mux = {15'd0, virt_in[3]};
            3'b100: in_data_mux = {15'd0, reg_x[0]};
            3'b101: in_data_mux = {15'd0, reg_y[0]};
            3'b110: in_data_mux = 16'h0000;
            3'b111: in_data_mux = 16'h0001;
        endcase
    end

    // MOV source multiplexer
    reg [15:0] mov_src_val;
    always @(*) begin
        case (mov_src)
            4'd0: mov_src_val = reg_x;
            4'd1: mov_src_val = reg_y;
            4'd2: mov_src_val = isr_val;
            4'd3: mov_src_val = osr_val;
            4'd4: mov_src_val = {12'd0, virt_in};
            4'd5: mov_src_val = ~reg_x;
            4'd6: mov_src_val = ~reg_y;
            4'd7: mov_src_val = {reg_x[7:0], reg_x[15:8]}; // byte swap
            default: mov_src_val = 16'h0000;
        endcase
    end

    wire exec_active = (en && tick && (delay_ctr == 5'd0));

    wire        in_en       = exec_active && (opcode == 3'b010);
    wire        out_en      = exec_active && (opcode == 3'b011);
    wire        cmd_push    = exec_active && (opcode == 3'b100) && (push_pull_sel == 1'b0);
    wire        cmd_pull    = exec_active && (opcode == 3'b100) && (push_pull_sel == 1'b1);
    wire        mov_isr_we  = exec_active && (opcode == 3'b101) && (mov_dst == 4'd2);
    wire [15:0] mov_isr_din = mov_src_val;
    wire        mov_osr_we  = exec_active && (opcode == 3'b101) && (mov_dst == 4'd3);
    wire [15:0] mov_osr_din = mov_src_val;

    proto_shifter u_shifter (
        .clk            (clk),
        .rst_n          (rst_n),
        .shift_in_dir   (shift_in_dir),
        .shift_out_dir  (shift_out_dir),
        .autopush_en    (autopush_en),
        .autopull_en    (autopull_en),
        .push_threshold (push_threshold),
        .pull_threshold (pull_threshold),
        .in_en          (in_en),
        .in_nbits       (in_nbits),
        .in_data        (in_data_mux),
        .out_en         (out_en),
        .out_nbits      (out_nbits),
        .out_data       (out_data_slice),
        .mov_isr_we     (mov_isr_we),
        .mov_isr_din    (mov_isr_din),
        .mov_osr_we     (mov_osr_we),
        .mov_osr_din    (mov_osr_din),
        .isr_val        (isr_val),
        .osr_val        (osr_val),
        .rx_fifo_full   (rx_fifo_full),
        .rx_fifo_push   (rx_fifo_push),
        .rx_fifo_din    (rx_fifo_din),
        .tx_fifo_empty  (tx_fifo_empty),
        .tx_fifo_dout   (tx_fifo_dout),
        .tx_fifo_pop    (tx_fifo_pop),
        .cmd_push       (cmd_push),
        .cmd_pull       (cmd_pull),
        .osr_empty      (osr_empty),
        .osr_remain     (osr_remain)
    );

    // WAIT condition resolution
    reg wait_val;
    always @(*) begin
        case (wait_src)
            3'b000: wait_val = virt_in[0];
            3'b001: wait_val = virt_in[1];
            3'b010: wait_val = virt_in[2];
            3'b011: wait_val = virt_in[3];
            3'b100: wait_val = irq_in[0];
            3'b101: wait_val = irq_in[1];
            3'b110: wait_val = !tx_fifo_empty;
            3'b111: wait_val = !rx_fifo_full;
        endcase
    end
    wire wait_satisfied = (wait_val == wait_pol);
    assign is_waiting   = (opcode == 3'b001) && !wait_satisfied;

    // JUMP condition resolution
    reg jmp_taken;
    always @(*) begin
        case (jmp_cond)
            3'b000: jmp_taken = 1'b1;                          // Always
            3'b001: jmp_taken = (reg_x == 16'h0000);           // !X
            3'b010: jmp_taken = (reg_x != 16'h0000);           // X-- (loop until 0)
            3'b011: jmp_taken = (reg_y == 16'h0000);           // !Y
            3'b100: jmp_taken = (reg_y != 16'h0000);           // Y--
            3'b101: jmp_taken = virt_in[0];                    // PIN 0 high
            3'b110: jmp_taken = !osr_empty;                    // !OSRE
            3'b111: jmp_taken = !rx_fifo_full;                 // !RXF
        endcase
    end

    // Execution State Machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc         <= 5'd0;
            next_pc    <= 5'd0;
            delay_ctr  <= 5'd0;
            reg_x      <= 16'h0000;
            reg_y      <= 16'h0000;
            virt_out   <= 4'b0000;
            virt_oe    <= 4'b0000;
            side_out   <= 2'b00;
            irq_out    <= 2'b00;
        end else if (en && tick) begin
            if (delay_ctr > 5'd0) begin
                delay_ctr <= delay_ctr - 5'd1;
                if (delay_ctr == 5'd1) begin
                    pc <= next_pc;
                end
            end else begin
                // Execute current instruction
                case (opcode)
                    3'b000: begin // JMP
                        if (jmp_taken) begin
                            if (inst_dly > 5'd0) begin
                                delay_ctr <= inst_dly;
                                next_pc   <= jmp_target;
                            end else begin
                                pc <= jmp_target;
                            end
                        end else begin
                            if (inst_dly > 5'd0) begin
                                delay_ctr <= inst_dly;
                                next_pc   <= pc + 5'd1;
                            end else begin
                                pc <= pc + 5'd1;
                            end
                        end
                        if (jmp_cond == 3'b010) reg_x <= reg_x - 16'd1;
                        if (jmp_cond == 3'b100) reg_y <= reg_y - 16'd1;
                    end

                    3'b001: begin // WAIT
                        if (wait_satisfied) begin
                            if (inst_dly > 5'd0) begin
                                delay_ctr <= inst_dly;
                                next_pc   <= pc + 5'd1;
                            end else begin
                                pc <= pc + 5'd1;
                            end
                        end
                    end

                    3'b010: begin // IN
                        if (inst_dly > 5'd0) begin
                            delay_ctr <= inst_dly;
                            next_pc   <= pc + 5'd1;
                        end else begin
                            pc <= pc + 5'd1;
                        end
                    end

                    3'b011: begin // OUT
                        case (out_dst)
                            3'b000: virt_out <= out_data_slice[3:0];
                            3'b001: reg_x    <= out_data_slice;
                            3'b010: reg_y    <= out_data_slice;
                            3'b011: virt_oe  <= out_data_slice[3:0];
                            3'b100: pc       <= out_data_slice[4:0];
                            3'b101: irq_out  <= out_data_slice[1:0];
                            default: ;
                        endcase
                        if (inst_dly > 5'd0) begin
                            delay_ctr <= inst_dly;
                            next_pc   <= pc + 5'd1;
                        end else begin
                            pc <= pc + 5'd1;
                        end
                    end

                    3'b100: begin // PUSH / PULL
                        if (inst_dly > 5'd0) begin
                            delay_ctr <= inst_dly;
                            next_pc   <= pc + 5'd1;
                        end else begin
                            pc <= pc + 5'd1;
                        end
                    end

                    3'b101: begin // MOV
                        case (mov_dst)
                            4'd0: reg_x <= mov_src_val;
                            4'd1: reg_y <= mov_src_val;
                            4'd4: virt_out <= mov_src_val[3:0];
                            4'd5: virt_oe  <= mov_src_val[3:0];
                            default: ;
                        endcase
                        if (inst_dly > 5'd0) begin
                            delay_ctr <= inst_dly;
                            next_pc   <= pc + 5'd1;
                        end else begin
                            pc <= pc + 5'd1;
                        end
                    end

                    3'b110: begin // SET
                        case (set_dst)
                            3'b000: virt_out <= set_data[3:0];
                            3'b001: reg_x    <= {11'd0, set_data};
                            3'b010: reg_y    <= {11'd0, set_data};
                            3'b011: virt_oe  <= set_data[3:0];
                            3'b100: side_out <= set_data[1:0];
                            3'b101: irq_out  <= set_data[1:0];
                            default: ;
                        endcase
                        if (inst_dly > 5'd0) begin
                            delay_ctr <= inst_dly;
                            next_pc   <= pc + 5'd1;
                        end else begin
                            pc <= pc + 5'd1;
                        end
                    end

                    3'b111: begin // ALU
                        reg_x <= alu_result;
                        if (inst_dly > 5'd0) begin
                            delay_ctr <= inst_dly;
                            next_pc   <= pc + 5'd1;
                        end else begin
                            pc <= pc + 5'd1;
                        end
                    end
                endcase
            end
        end
    end

endmodule
