`default_nettype none

//=============================================================================
// Module: proto_emulator_top
// Description: Core Top-Level for the Protocol Emulator ASIC
// Integrates Dual Micro-Engines, Host SPI Controller, Dual Clock Prescalers,
// Synchronous FIFOs, Dual-Port Instruction RAMs, and Dynamic Pin Crossbar.
//=============================================================================

module proto_emulator_top (
    input  wire        clk,
    input  wire        rst_n,

    // Tiny Tapeout Physical Interfaces
    input  wire [7:0]  ui_in,
    output wire [7:0]  uo_out,
    input  wire [7:0]  uio_in,
    output wire [7:0]  uio_out,
    output wire [7:0]  uio_oe
);

    // -------------------------------------------------------------------------
    // Host SPI Signals
    // -------------------------------------------------------------------------
    wire        host_sclk;
    wire        host_cs_n;
    wire        host_mosi;
    wire        host_miso;
    wire        host_irq;

    // Registers from Host Interface
    wire [15:0] reg_ctrl;
    wire [15:0] reg_div_e0;
    wire [15:0] reg_div_e1;
    wire [15:0] reg_frac_div;
    wire [15:0] reg_cfg_e0;
    wire [15:0] reg_cfg_e1;
    wire [15:0] reg_pin_mode;

    // IMEM Port B (Programming) Signals
    wire        imem_e0_we;
    wire [4:0]  imem_e0_addr;
    wire [15:0] imem_e0_din;
    wire [15:0] imem_e0_dout;

    wire        imem_e1_we;
    wire [4:0]  imem_e1_addr;
    wire [15:0] imem_e1_din;
    wire [15:0] imem_e1_dout;

    // Host FIFO Access Signals
    wire        host_e0_tx_push;
    wire [15:0] host_e0_tx_din;
    wire        host_e0_rx_pop;
    wire [15:0] host_e0_rx_dout;

    wire        host_e1_tx_push;
    wire [15:0] host_e1_tx_din;
    wire        host_e1_rx_pop;
    wire [15:0] host_e1_rx_dout;

    // Soft reset logic
    wire core_rst_n = rst_n && !reg_ctrl[2];

    // Engine enables
    wire e0_en = reg_ctrl[0];
    wire e1_en = reg_ctrl[1];

    // -------------------------------------------------------------------------
    // Prescalers
    // -------------------------------------------------------------------------
    wire e0_tick;
    proto_clock_prescaler u_prescaler_e0 (
        .clk      (clk),
        .rst_n    (core_rst_n),
        .en       (e0_en),
        .div_int  (reg_div_e0),
        .div_frac (reg_frac_div[7:0]),
        .tick     (e0_tick)
    );

    wire e1_tick;
    proto_clock_prescaler u_prescaler_e1 (
        .clk      (clk),
        .rst_n    (core_rst_n),
        .en       (e1_en),
        .div_int  (reg_div_e1),
        .div_frac (reg_frac_div[15:8]),
        .tick     (e1_tick)
    );

    // -------------------------------------------------------------------------
    // Instruction Memories
    // -------------------------------------------------------------------------
    wire [4:0]  e0_imem_pc;
    wire [15:0] e0_imem_inst;
    proto_imem #(
        .ADDR_WIDTH (5),
        .DATA_WIDTH (16)
    ) u_imem_e0 (
        .clk    (clk),
        .rst_n  (core_rst_n),
        .addr_a (e0_imem_pc),
        .dout_a (e0_imem_inst),
        .we_b   (imem_e0_we),
        .addr_b (imem_e0_addr),
        .din_b  (imem_e0_din),
        .dout_b (imem_e0_dout)
    );

    wire [4:0]  e1_imem_pc;
    wire [15:0] e1_imem_inst;
    proto_imem #(
        .ADDR_WIDTH (5),
        .DATA_WIDTH (16)
    ) u_imem_e1 (
        .clk    (clk),
        .rst_n  (core_rst_n),
        .addr_a (e1_imem_pc),
        .dout_a (e1_imem_inst),
        .we_b   (imem_e1_we),
        .addr_b (imem_e1_addr),
        .din_b  (imem_e1_din),
        .dout_b (imem_e1_dout)
    );

    // -------------------------------------------------------------------------
    // Engine 0 FIFOs
    // -------------------------------------------------------------------------
    // TX0 FIFO: Host pushes, Engine pops (via shifter pull)
    wire        e0_tx_pop;
    wire [15:0] e0_tx_dout;
    wire        e0_tx_empty;
    wire        e0_tx_full;
    wire [2:0]  e0_tx_level;

    proto_fifo #(
        .DATA_WIDTH (16),
        .FIFO_DEPTH (4),
        .ADDR_WIDTH (2)
    ) u_fifo_e0_tx (
        .clk      (clk),
        .rst_n    (core_rst_n),
        .push     (host_e0_tx_push),
        .data_in  (host_e0_tx_din),
        .pop      (e0_tx_pop),
        .data_out (e0_tx_dout),
        .empty    (e0_tx_empty),
        .full     (e0_tx_full),
        .level    (e0_tx_level)
    );

    // RX0 FIFO: Engine pushes (via shifter push), Host pops
    wire        e0_rx_push;
    wire [15:0] e0_rx_din;
    wire        e0_rx_empty;
    wire        e0_rx_full;
    wire [2:0]  e0_rx_level;

    proto_fifo #(
        .DATA_WIDTH (16),
        .FIFO_DEPTH (4),
        .ADDR_WIDTH (2)
    ) u_fifo_e0_rx (
        .clk      (clk),
        .rst_n    (core_rst_n),
        .push     (e0_rx_push),
        .data_in  (e0_rx_din),
        .pop      (host_e0_rx_pop),
        .data_out (host_e0_rx_dout),
        .empty    (e0_rx_empty),
        .full     (e0_rx_full),
        .level    (e0_rx_level)
    );

    // -------------------------------------------------------------------------
    // Engine 1 FIFOs
    // -------------------------------------------------------------------------
    // TX1 FIFO: Host pushes, Engine pops
    wire        e1_tx_pop;
    wire [15:0] e1_tx_dout;
    wire        e1_tx_empty;
    wire        e1_tx_full;
    wire [2:0]  e1_tx_level;

    proto_fifo #(
        .DATA_WIDTH (16),
        .FIFO_DEPTH (4),
        .ADDR_WIDTH (2)
    ) u_fifo_e1_tx (
        .clk      (clk),
        .rst_n    (core_rst_n),
        .push     (host_e1_tx_push),
        .data_in  (host_e1_tx_din),
        .pop      (e1_tx_pop),
        .data_out (e1_tx_dout),
        .empty    (e1_tx_empty),
        .full     (e1_tx_full),
        .level    (e1_tx_level)
    );

    // RX1 FIFO: Engine pushes, Host pops
    wire        e1_rx_push;
    wire [15:0] e1_rx_din;
    wire        e1_rx_empty;
    wire        e1_rx_full;
    wire [2:0]  e1_rx_level;

    proto_fifo #(
        .DATA_WIDTH (16),
        .FIFO_DEPTH (4),
        .ADDR_WIDTH (2)
    ) u_fifo_e1_rx (
        .clk      (clk),
        .rst_n    (core_rst_n),
        .push     (e1_rx_push),
        .data_in  (e1_rx_din),
        .pop      (host_e1_rx_pop),
        .data_out (host_e1_rx_dout),
        .empty    (e1_rx_empty),
        .full     (e1_rx_full),
        .level    (e1_rx_level)
    );

    // -------------------------------------------------------------------------
    // Protocol Engines Execution Units
    // -------------------------------------------------------------------------
    wire [3:0]  e0_virt_in;
    wire [3:0]  e0_virt_out;
    wire [3:0]  e0_virt_oe;
    wire [1:0]  e0_side_out;

    wire [3:0]  e1_virt_in;
    wire [3:0]  e1_virt_out;
    wire [3:0]  e1_virt_oe;
    wire [1:0]  e1_side_out;

    wire [1:0]  e0_irq_out;
    wire [1:0]  e1_irq_out;

    wire [4:0]  e0_pc;
    wire [15:0] e0_reg_x;
    wire [15:0] e0_reg_y;
    wire        e0_waiting;

    wire [4:0]  e1_pc;
    wire [15:0] e1_reg_x;
    wire [15:0] e1_reg_y;
    wire        e1_waiting;

    // Engine 0
    proto_engine u_engine_0 (
        .clk            (clk),
        .rst_n          (core_rst_n),
        .en             (e0_en),
        .tick           (e0_tick),
        .imem_addr      (e0_imem_pc),
        .imem_inst      (e0_imem_inst),
        .virt_in        (e0_virt_in),
        .virt_out       (e0_virt_out),
        .virt_oe        (e0_virt_oe),
        .side_out       (e0_side_out),
        .irq_in         (e1_irq_out), // Core 0 reads IRQs from Core 1
        .irq_out        (e0_irq_out),
        .rx_fifo_full   (e0_rx_full),
        .rx_fifo_push   (e0_rx_push),
        .rx_fifo_din    (e0_rx_din),
        .tx_fifo_empty  (e0_tx_empty),
        .tx_fifo_dout   (e0_tx_dout),
        .tx_fifo_pop    (e0_tx_pop),
        .shift_in_dir   (reg_cfg_e0[0]),
        .shift_out_dir  (reg_cfg_e0[1]),
        .autopush_en    (reg_cfg_e0[2]),
        .autopull_en    (reg_cfg_e0[3]),
        .push_threshold (reg_cfg_e0[8:4]),
        .pull_threshold (reg_cfg_e0[13:9]),
        .pc_out         (e0_pc),
        .reg_x_out      (e0_reg_x),
        .reg_y_out      (e0_reg_y),
        .is_waiting     (e0_waiting)
    );

    // Engine 1
    proto_engine u_engine_1 (
        .clk            (clk),
        .rst_n          (core_rst_n),
        .en             (e1_en),
        .tick           (e1_tick),
        .imem_addr      (e1_imem_pc),
        .imem_inst      (e1_imem_inst),
        .virt_in        (e1_virt_in),
        .virt_out       (e1_virt_out),
        .virt_oe        (e1_virt_oe),
        .side_out       (e1_side_out),
        .irq_in         (e0_irq_out), // Core 1 reads IRQs from Core 0
        .irq_out        (e1_irq_out),
        .rx_fifo_full   (e1_rx_full),
        .rx_fifo_push   (e1_rx_push),
        .rx_fifo_din    (e1_rx_din),
        .tx_fifo_empty  (e1_tx_empty),
        .tx_fifo_dout   (e1_tx_dout),
        .tx_fifo_pop    (e1_tx_pop),
        .shift_in_dir   (reg_cfg_e1[0]),
        .shift_out_dir  (reg_cfg_e1[1]),
        .autopush_en    (reg_cfg_e1[2]),
        .autopull_en    (reg_cfg_e1[3]),
        .push_threshold (reg_cfg_e1[8:4]),
        .pull_threshold (reg_cfg_e1[13:9]),
        .pc_out         (e1_pc),
        .reg_x_out      (e1_reg_x),
        .reg_y_out      (e1_reg_y),
        .is_waiting     (e1_waiting)
    );

    // -------------------------------------------------------------------------
    // Pin Crossbar & Open-Drain Drivers
    // -------------------------------------------------------------------------
    proto_pin_crossbar u_crossbar (
        .ui_in        (ui_in),
        .uo_out       (uo_out),
        .uio_in       (uio_in),
        .uio_out      (uio_out),
        .uio_oe       (uio_oe),
        .host_sclk    (host_sclk),
        .host_cs_n    (host_cs_n),
        .host_mosi    (host_mosi),
        .host_miso    (host_miso),
        .host_irq     (host_irq),
        .e0_virt_in   (e0_virt_in),
        .e0_virt_out  (e0_virt_out),
        .e0_virt_oe   (e0_virt_oe),
        .e0_side_out  (e0_side_out),
        .e1_virt_in   (e1_virt_in),
        .e1_virt_out  (e1_virt_out),
        .e1_virt_oe   (e1_virt_oe),
        .e1_side_out  (e1_side_out),
        .cfg_pin_mode (reg_pin_mode[7:0])
    );

    // -------------------------------------------------------------------------
    // Host Interface
    // -------------------------------------------------------------------------
    wire [15:0] status_word = {
        e1_rx_empty, e1_tx_full,
        e0_rx_empty, e0_tx_full,
        e1_waiting,  e0_waiting,
        e1_en,       e0_en,
        8'b00000000
    };

    wire [15:0] diag_e0_word = {3'b000, e0_pc, e0_reg_x[7:0]};
    wire [15:0] diag_e1_word = {3'b000, e1_pc, e1_reg_x[7:0]};

    proto_host_interface u_host (
        .clk          (clk),
        .rst_n        (rst_n),
        .sclk         (host_sclk),
        .cs_n         (host_cs_n),
        .mosi         (host_mosi),
        .miso         (host_miso),
        .irq          (host_irq),
        .reg_ctrl     (reg_ctrl),
        .reg_div_e0   (reg_div_e0),
        .reg_div_e1   (reg_div_e1),
        .reg_frac_div (reg_frac_div),
        .reg_cfg_e0   (reg_cfg_e0),
        .reg_cfg_e1   (reg_cfg_e1),
        .reg_pin_mode (reg_pin_mode),
        .imem_e0_we   (imem_e0_we),
        .imem_e0_addr (imem_e0_addr),
        .imem_e0_din  (imem_e0_din),
        .imem_e0_dout (imem_e0_dout),
        .imem_e1_we   (imem_e1_we),
        .imem_e1_addr (imem_e1_addr),
        .imem_e1_din  (imem_e1_din),
        .imem_e1_dout (imem_e1_dout),
        .e0_tx_push   (host_e0_tx_push),
        .e0_tx_din    (host_e0_tx_din),
        .e0_rx_pop    (host_e0_rx_pop),
        .e0_rx_dout   (host_e0_rx_dout),
        .e1_tx_push   (host_e1_tx_push),
        .e1_tx_din    (host_e1_tx_din),
        .e1_rx_pop    (host_e1_rx_pop),
        .e1_rx_dout   (host_e1_rx_dout),
        .status_word  (status_word),
        .diag_e0_word (diag_e0_word),
        .diag_e1_word (diag_e1_word)
    );

endmodule
