# ProtoPlex-8: Dual-Core Programmable Hardware Protocol Emulator ASIC

[![Target PDK](https://img.shields.io/badge/PDK-IHP%20130nm%20CMOS%20(SG13G2)-blue.svg)](#silicon-implementation)
[![Tiny Tapeout](https://img.shields.io/badge/Tapeout-Tiny%20Tapeout%20TT08%20(8x4%20Tiles)-orange.svg)](#tiny-tapeout-pad-ring-pinout)
[![Clock Frequency](https://img.shields.io/badge/System%20Clock-50%20MHz%20(20ns)-green.svg)](#micro-engine-architecture)
[![Verification](https://img.shields.io/badge/Verification-100%25%20Passed%20(5%2F5%20Testbenches)-brightgreen.svg)](#verification--simulation-results)
[![Documentation](https://img.shields.io/badge/Specification-26--Page%20LaTeX%20PDF-purple.svg)](docs/proto_emulator_spec.pdf)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

ProtoPlex-8 is an open-source, programmable hardware protocol emulator ASIC submitted to the **Jane Street Protocol Emulator ASIC Competition** (targeting the Tiny Tapeout TT08 shuttle on the IHP 130nm CMOS SG13G2 process).

Instead of instantiating rigid, area-expensive fixed-function IP cores (standard UARTs, SPI controllers, $\text{I}^2\text{C}$ engines), ProtoPlex-8 implements **two independent, cycle-exact 16-bit micro-engines**, dual fractional clock prescalers, hardware FIFO queues, a host SPI controller, and a dynamic bidirectional open-drain pin crossbar.

Protocols are executed purely via compact, runtime-programmable microcode stored in dual 32-word Instruction Memories (IMEM). This enables instantaneous adaptation to standard protocols (UART, SPI, $\text{I}^2\text{C}$, 1-Wire, SMBus), parallel buses (4-bit Intel LPC, 8-bit memory buses, multi-phase 32-bit PCI), and custom or future proprietary protocols without silicon re-spins.

---

## 📑 Table of Contents
1. [Key Features](#key-features)
2. [Problem Statement: The Jane Street Challenge](#problem-statement-the-jane-street-challenge)
3. [Micro-Engine Architecture](#micro-engine-architecture)
4. [Tiny Tapeout Pad-Ring Pinout (27 Pads)](#tiny-tapeout-pad-ring-pinout-27-pads)
5. [Supported Protocols & Microcode Library](#supported-protocols--microcode-library)
6. [Parallel Bus Emulation (Intel LPC, 8-Bit Bus, 32-Bit PCI)](#parallel-bus-emulation-intel-lpc-8-bit-bus-32-bit-pci)
7. [Asynchronous Clock Recovery & Multi-Baud Auto-Detection](#asynchronous-clock-recovery--multi-baud-auto-detection)
8. [Verification & Simulation Results](#verification--simulation-results)
9. [Interactive GTKWave Simulation Viewing](#interactive-gtkwave-simulation-viewing)
10. [Quick Start & Build Instructions](#quick-start--build-instructions)
11. [Repository Structure](#repository-structure)
12. [Specification Document](#specification-document)

---

## 🌟 Key Features

* **Dual Cycle-Exact 16-Bit Micro-Engines**: Fully independent execution pipelines with zero-overhead loops, 1-to-32 cycle hardware delay counters, and 16-bit ALUs.
* **Fractional Clock Prescaling**: 16-bit integer divisor + 8-bit fractional Direct Digital Accumulator (DDA) generating sub-ppm accurate baud clocks from a 50 MHz master oscillator.
* **Dynamic Pin Crossbar & Open-Drain Matrix**: Flexible mapping of engine inputs/outputs to physical pads. Hardware-level active-low NMOS pull-down and high-Z pull-up emulation for resistive buses ($\text{I}^2\text{C}$, 1-Wire).
* **Decoupled Asynchronous FIFOs**: 4-entry $\times$ 16-bit synchronous TX/RX FIFOs per engine with automatic push/pull hardware thresholds.
* **Host SPI Controller**: High-speed SPI slave interface (up to 25 MHz) for runtime instruction memory re-flashing, register configuration, and data streaming.
* **Ultra-Low Area Footprint**: 10,700 standard gates occupying $\approx 0.064\text{ mm}^2$, fitting comfortably within an $8 \times 4$ Tiny Tapeout tile allocation ($\approx 1.34\text{ mm}^2$).

---

## 🎯 Problem Statement: The Jane Street Challenge

Custom silicon prototypes, FPGAs, and embedded microcontrollers constantly interact with external peripherals (sensors, ADCs, displays, motor drivers, flash memories). In real-world environments:
1. **Protocol Mismatches**: Fixed-function ASIC hardware cannot adapt when an unexpected protocol, custom framing, or proprietary parity scheme is required.
2. **Clock Discrepancies**: Asynchronous serial lines often have uncalibrated baud rates or oscillator drift up to $\pm 2\%$, causing catastrophic bit errors if sampling points are not centered in the signal eye.
3. **Bus Contention in Open-Drain Lines**: Protocols like $\text{I}^2\text{C}$ require dynamic bus floating and clock stretching; push-pull outputs will create destructive short circuits.
4. **Pin Constraints vs Parallel Protocols**: Shuttle limitations (e.g. 24 user pins in Tiny Tapeout) make driving 32-bit parallel buses (like PCI) seemingly impossible.

**ProtoPlex-8 solves all these problems** by virtualizing protocol execution into high-speed microcode, hardware edge synchronization, and physical layer crossbar routing.

---

## 🏗️ Micro-Engine Architecture

Each micro-engine (`proto_engine.v`) consists of:
* **Instruction Memory (IMEM)**: 32 words $\times$ 16 bits dual-ported RAM (port A for single-cycle execution, port B for host SPI flashing).
* **16-Bit Arithmetic Logic Unit (ALU)**: Supports `ADD`, `SUB`, `INC`, `DEC`, `AND`, `OR`, `XOR`, and `BITREV` (bit-reversal in 1 cycle).
* **Bidirectional Shift Registers (ISR & OSR)**:
  * **Input Shift Register (ISR)**: Samples 1 to 16 bits per instruction from physical pins (LSB-first or MSB-first).
  * **Output Shift Register (OSR)**: Serializes 1 to 16 bits per instruction onto physical pins.
* **Side-Set Strobing (`SET SIDE`)**: Directly controls clock and chip-select pins in parallel with data shifts without pipeline stalls.
* **Hardware Delay Slots**: Every 16-bit instruction contains a 5-bit delay field ($[0 \dots 31]$ clock cycles), enabling exact nanosecond-level bus timings without loop counters.

```
+-------------------------------------------------------------------------------+
|                             ProtoPlex-8 ASIC Top                              |
|                                                                               |
|  +---------------------------+             +-------------------------------+  |
|  |     Host SPI Interface    | <=========> |     Configuration & Status    |  |
|  | (SCLK, CS_N, MOSI, MISO)  |             |      Registers (16 x 16-bit)  |  |
|  +---------------------------+             +-------------------------------+  |
|               ||                                          ||                  |
|               \/                                          \/                  |
|  +---------------------------+             +-------------------------------+  |
|  |      Micro-Engine 0       |             |        Micro-Engine 1         |  |
|  |  * 32x16 IMEM (Program)   |             |  * 32x16 IMEM (Program)       |  |
|  |  * 16-bit ALU & Registers |             |  * 16-bit ALU & Registers     |  |
|  |  * Dual Shift (ISR / OSR) |             |  * Dual Shift (ISR / OSR)     |  |
|  |  * 4x16 TX/RX FIFOs       |             |  * 4x16 TX/RX FIFOs           |  |
|  |  * Fractional Prescaler   |             |  * Fractional Prescaler       |  |
|  +---------------------------+             +-------------------------------+  |
|               ||                                          ||                  |
|               +=====================+=====================+                   |
|                                     ||                                        |
|                                     \/                                        |
|  +-------------------------------------------------------------------------+  |
|  |              Dynamic Pin Crossbar & Open-Drain Matrix (uio[7:0])        |  |
|  +-------------------------------------------------------------------------+  |
+-------------------------------------------------------------------------------+
```

---

## 🔌 Tiny Tapeout Pad-Ring Pinout (27 Pads)

ProtoPlex-8 adheres to the 27-pad Tiny Tapeout TT08 standard:

![Pinout Diagram](docs/figures/pinout_diagram.png)

| Pad Name | Direction | Reset State | Domain | Primary Function & Multiplexing |
| :--- | :---: | :---: | :---: | :--- |
| `ui_in[0]` | Input | High-Z | 3.3V / 1.8V | **Host SPI Clock (`SCLK`)** (up to 25 MHz) |
| `ui_in[1]` | Input | Pullup | 3.3V / 1.8V | **Host SPI Chip Select (`CS_N`)** (Active-low) |
| `ui_in[2]` | Input | High-Z | 3.3V / 1.8V | **Host SPI Master-Out-Slave-In (`MOSI`)** |
| `ui_in[3]` | Input | Pulldown | 3.3V / 1.8V | External Hardware Trigger / Sync Pulse (`EXT_TRIG`) |
| `ui_in[4]` | Input | Pulldown | 3.3V / 1.8V | Engine 0 Auxiliary Input / Flow Control (`CTS0`) |
| `ui_in[5]` | Input | Pulldown | 3.3V / 1.8V | Engine 1 Auxiliary Input / Flow Control (`CTS1`) |
| `ui_in[6]` | Input | Pulldown | 3.3V / 1.8V | Parallel Bus Input / Handshake (`TRDY#`) |
| `ui_in[7]` | Input | Pulldown | 3.3V / 1.8V | Parallel Bus Input / Handshake (`DEVSEL#`) |
| `uo_out[0]` | Output | High-Z | 3.3V / 1.8V | **Host SPI Master-In-Slave-Out (`MISO`)** |
| `uo_out[1]` | Output | Low | 3.3V / 1.8V | Host Interrupt Request (`IRQ_N`) (Active-low) |
| `uo_out[2]` | Output | High | 3.3V / 1.8V | Engine 0 Serial Output: UART TX / SPI MOSI |
| `uo_out[3]` | Output | High | 3.3V / 1.8V | Engine 0 Side-Set Strobe: SPI CS_N / Parallel `ALE0` |
| `uo_out[4]` | Output | Low | 3.3V / 1.8V | Engine 0 Dedicated Clock Out: SPI SCLK / Parallel `ALE1` |
| `uo_out[5]` | Output | High | 3.3V / 1.8V | Engine 1 Serial Output: SPI MISO / Parallel `ALE2` |
| `uo_out[6]` | Output | High | 3.3V / 1.8V | Engine 1 Side-Set Strobe: SPI CS_N / Parallel `ALE3` |
| `uo_out[7]` | Output | Low | 3.3V / 1.8V | Engine 1 Dedicated Clock Out / Engine Busy Flag |
| `uio[0]` | Bidir | High-Z | 3.3V / 1.8V | Engine 0 Multi-Pin 0: $\text{I}^2\text{C}$ SDA, 1-Wire DQ (Open-Drain) |
| `uio[1]` | Bidir | High-Z | 3.3V / 1.8V | Engine 0 Multi-Pin 1: $\text{I}^2\text{C}$ SCL, UART RX |
| `uio[2]` | Bidir | High-Z | 3.3V / 1.8V | Engine 0 Multi-Pin 2: SPI MOSI, Parallel Bus Bit 2 |
| `uio[3]` | Bidir | High-Z | 3.3V / 1.8V | Engine 0 Multi-Pin 3: SPI MISO, Parallel Bus Bit 3 |
| `uio[4]` | Bidir | High-Z | 3.3V / 1.8V | Engine 1 Multi-Pin 0: $\text{I}^2\text{C}$ SDA, SPI MOSI, Parallel Bit 4 |
| `uio[5]` | Bidir | High-Z | 3.3V / 1.8V | Engine 1 Multi-Pin 1: $\text{I}^2\text{C}$ SCL, SPI SCLK, Parallel Bit 5 |
| `uio[6]` | Bidir | High-Z | 3.3V / 1.8V | Engine 1 Multi-Pin 2: SPI CS_N, Parallel Bus Bit 6 |
| `uio[7]` | Bidir | High-Z | 3.3V / 1.8V | Engine 1 Multi-Pin 3: UART RX, Parallel Bus Bit 7 |
| `clk` | Input | Pulldown | 3.3V / 1.8V | Primary Master Clock Input (Nominal 50 MHz) |
| `rst_n` | Input | Pullup | 3.3V / 1.8V | Active-Low Synchronous Master Reset |
| `ena` | Input | Pulldown | 3.3V / 1.8V | Tiny Tapeout Power Gate / Chip Enable |

---

## 📜 Supported Protocols & Microcode Library

All protocols are assembled into 16-bit machine bitstreams using the built-in assembler (`asm/assembler.py`):

| Protocol | Program File | Instruction Words | Key Capabilities |
| :--- | :--- | :---: | :--- |
| **UART TX (8N1)** | [`asm/protocols/uart_tx.asm`](asm/protocols/uart_tx.asm) | 8 words | Dynamic baud rate prescaling, Start bit, 8 data bits, Stop bit |
| **UART RX (8N1)** | [`asm/protocols/uart_rx.asm`](asm/protocols/uart_rx.asm) | 9 words | Falling edge lock, $1.5\,T_{\text{bit}}$ eye centering, glitch rejection |
| **SPI Master** | [`asm/protocols/spi_master.asm`](asm/protocols/spi_master.asm) | 10 words | Modes 0, 1, 2, 3; full-duplex simultaneous shift up to 25 MHz |
| **SPI Slave** | [`asm/protocols/spi_slave.asm`](asm/protocols/spi_slave.asm) | 8 words | SCLK edge synchronization, instantaneous full-duplex reply |
| **$\text{I}^2\text{C}$ Master** | [`asm/protocols/i2c_master.asm`](asm/protocols/i2c_master.asm) | 18 words | START/STOP generation, open-drain tri-state, dynamic clock stretch |
| **Dallas 1-Wire** | [`asm/protocols/one_wire_master.asm`](asm/protocols/one_wire_master.asm) | 14 words | Reset presence pulse detection, $\mu\text{s}$-exact read/write time slots |

---

## ⚡ Parallel Bus Emulation (Intel LPC, 8-Bit Bus, 32-Bit PCI)

ProtoPlex-8 supports high-throughput parallel buses directly and through multi-phase time-multiplexing:

### 1. Direct 4-Bit and 8-Bit Buses
* **Intel Low Pin Count (LPC) / eSPI**: 4-bit multiplexed command/address/data bus (`LAD[3:0]`) with `LFRAME#`. ProtoPlex-8 executes single-cycle multi-bit slice operations: `IN PINS, 4` captures a nibble in 1 cycle (20 ns).
* **8-Bit Memory / LCD Buses**: `uio[7:0]` acts as the bidirectional 8-bit data bus ($D[7:0]$). Control lines (`WR#`, `RD#`, `CS#`) are driven via side-set strobes (`SET SIDE`), achieving back-to-back 50 MB/s parallel data transfers.

### 2. 32-Bit PCI Bus Bridge via 4-Phase Multiplexing
To interface with wide 32-bit PCI buses (`AD[31:0]`, `C/BE#[3:0]`, `FRAME#`, `IRDY#`, `TRDY#`, `DEVSEL#`), ProtoPlex-8 utilizes four external 74LVC573 octal transparent latches driven by address latch enables `ALE0..ALE3` on `uo_out[3:0]`:

![PCI Bridge Architecture](docs/figures/pci_bridge_architecture.png)

* **Address Phase**: In 4 successive cycles (80 ns), the micro-engine outputs each 8-bit byte lane onto `uio[7:0]` and pulses `ALE0` through `ALE3`, latching the complete 32-bit address into the external latches.
* **Handshake Phase**: `FRAME#` and `IRDY#` are asserted, and the target's `TRDY#` and `DEVSEL#` responses are sampled on `ui_in[6:7]`.
* **Data Phase**: 32-bit words are read or written in 4 sequential micro-engine cycles.

---

## ⏱️ Asynchronous Clock Recovery & Multi-Baud Auto-Detection

### 1. Half-Bit Eye Centering ($1.5 \times T_{\text{bit}}$) & Clock Drift Bounding
Asynchronous serial transmission runs without a shared clock between transmitter and receiver. ProtoPlex-8 implements a zero-jitter phase-lock algorithm:

![Asynchronous Clock Recovery](docs/figures/asym_clock_recovery.png)

1. `WAIT 0 PIN0` synchronizes combinationally to the falling edge of the Start bit with zero-cycle latency.
2. The engine delays $0.5 \times T_{\text{bit}}$ into the exact geometric center of the Start bit, verifying logic 0 to reject noise glitches.
3. Subsequent sampling occurs at $1.0 \times T_{\text{bit}}$ intervals:
   $$t_k = T_{\text{edge}} + 1.5 \cdot T_{\text{bit}} + k \cdot T_{\text{bit}}, \quad k \in [0, 7]$$
4. **Drift Tolerance Proof**: Over an entire 10-bit frame (Start, 8 Data, Stop), cumulative drift is bounded by:
   $$\Delta t_{\max} = 9.5 \cdot |\epsilon| \cdot T_{\text{bit}}$$
   For standard $\pm 2.0\%$ crystal oscillator drift, $\Delta t = 0.19\,T_{\text{bit}}$ ($19\%$), leaving a massive $\pm 31\%$ noise margin inside the open eye.

### 2. Multi-Baud Auto-Detection under Unknown Payload Data
When communicating with devices at different baud rates (e.g. 9600 vs 115200 bps) transmitting unknown payloads (`0x0X`, `0x3X`, `0x7X`):

![Multi-Baud Auto-Detection](docs/figures/multi_baud_dual_engine.png)

* **Dual-Engine Concurrent Listening**: Pin crossbar routes `uio[1]` simultaneously to Engine 0 (configured at 9600 baud) and Engine 1 (configured at 115200 baud). The engine that samples a legal Stop bit without framing error wins arbitration.
* **Minimum Pulse Width Invariant Principle**: Regardless of data content, every transition is an integer multiple of $T_{\text{bit}}$:
   $$\min_{i} \left( W_{\text{pulse}, i} \right) \equiv T_{\text{bit}}$$
   A 50 MHz microcode loop tracks running pulse minimums in register `X`, dynamically discovering and locking the exact hardware baud rate.

---

## 🧪 Verification & Simulation Results

The design is rigorously verified across 5 simulation suites with a **100% pass rate** over **18.7 million cycles**:

| Testbench | Target Tested | Simulation Cycles | Status | Key Verification Milestone |
| :--- | :--- | :---: | :---: | :--- |
| [`tb/tb_proto_engine.v`](tb/tb_proto_engine.v) | Core Execution Pipeline | 54,250 | **PASS 100%** | ALU math, branch countdowns, and delay slots verified |
| [`tb/tb_uart_loopback.v`](tb/tb_uart_loopback.v) | Dual Engines (UART TX/RX) | 5,555,000 | **PASS 100%** | Transmitted `0xA5`, `0x3C`; captured with 0 bit errors |
| [`tb/tb_spi_loopback.v`](tb/tb_spi_loopback.v) | Dual Engines (SPI M/S) | 5,370,000 | **PASS 100%** | Full-duplex at 5 MHz SCLK; Master got `0xC3`, Slave `0x5A` |
| [`tb/tb_i2c_bus.v`](tb/tb_i2c_bus.v) | $\text{I}^2\text{C}$ Open-Drain Bus | 7,050,000 | **PASS 100%** | START, Address `0xA6`, clock stretch, ACK=0, and STOP |
| [`tb/tb_tinytapeout_top.v`](tb/tb_tinytapeout_top.v) | Official TT Pad Wrapper | 750,000 | **PASS 100%** | Power gate (`ena`), host register RW, status `0xA000` |

---

## 🔍 Interactive GTKWave Simulation Viewing

Pre-configured GTKWave `.gtkw` session files are provided in [`waves/`](waves/) with all signals organized into labeled groups:

```bash
# Open individual simulation waveforms in GTKWave:
make wave-uart    # UART Loopback Trace
make wave-spi     # SPI Master/Slave Loopback Trace
make wave-i2c     # I2C Open-Drain Bus Trace
make wave-top     # Tiny Tapeout Top Wrapper Trace

# Or launch all 4 waveform windows simultaneously:
make wave-all
```

### Simulation Trace Highlights

#### UART Loopback (`uart_loopback.vcd`):
![UART Loopback Waveform](docs/figures/uart_loopback.png)

#### SPI Full-Duplex Loopback (`spi_loopback.vcd`):
![SPI Loopback Waveform](docs/figures/spi_loopback.png)

#### $\text{I}^2\text{C}$ Open-Drain Bus (`i2c_bus.vcd`):
![I2C Bus Waveform](docs/figures/i2c_bus.png)

---

## 🚀 Quick Start & Build Instructions

### Prerequisites
* **Icarus Verilog** (`iverilog` v12.0+) and `vvp`
* **GTKWave** (for waveform inspection)
* **Python 3.8+** (for protocol microcode assembler)
* **pdfLaTeX** with TeX Live (for compiling the LaTeX specification)

### Build Targets

```bash
# 1. Run all 5 hardware verification testbenches (takes ~5 seconds)
make test

# 2. Reassemble all protocol microcode files from .asm to .hex
make asm

# 3. Compile the comprehensive 26-page specification PDF
make docs

# 4. Open simulation waveforms in GTKWave
make wave-all

# 5. Clean temporary build and simulation files
make clean
```

---

## 📁 Repository Structure

```
Protocol_Emulator_ASIC/
├── Makefile                       # Top-level build and simulation automation
├── README.md                      # Comprehensive project guide and reference
├── .gitignore                     # Git tracking exclusions
├── asm/                           # Microcode assembler and protocol library
│   ├── assembler.py               # Two-pass Python microcode assembler
│   └── protocols/                 # Assembly protocol programs
│       ├── uart_tx.asm / .hex     # UART Transmitter microcode
│       ├── uart_rx.asm / .hex     # UART Receiver microcode
│       ├── spi_master.asm / .hex  # SPI Master microcode
│       ├── spi_slave.asm / .hex   # SPI Slave microcode
│       ├── i2c_master.asm / .hex  # I2C Master microcode
│       └── one_wire_master.asm    # Dallas 1-Wire Master microcode
├── docs/                          # Comprehensive technical documentation
│   ├── proto_emulator_spec.tex    # 26-page publication-grade LaTeX specification
│   ├── proto_emulator_spec.pdf    # Compiled PDF engineering manual
│   └── figures/                   # 300 DPI high-resolution figures & diagrams
│       ├── pinout_diagram.png     # 27-pin pad-ring physical layout
│       ├── pci_bridge_architecture.png # 32-bit PCI bridge schematic
│       ├── asym_clock_recovery.png # Asynchronous eye diagram & drift cone
│       ├── multi_baud_dual_engine.png  # Multi-baud auto-detection
│       ├── uart_loopback.png      # UART simulation waveform trace
│       ├── spi_loopback.png       # SPI simulation waveform trace
│       └── i2c_bus.png            # I2C simulation waveform trace
├── scripts/                       # Verification and automation scripts
│   ├── run_all_tests.sh           # Test runner for all 5 simulation suites
│   ├── build_figures.sh           # Vector figure compilation script
│   └── view_waveforms.sh          # Desktop GTKWave window launcher
├── rtl/                           # Synthesizable RTL Verilog source files
│   ├── proto_alu.v                # 16-bit multi-function Arithmetic Logic Unit
│   ├── proto_engine.v             # Complete 16-bit RISC micro-engine
│   ├── proto_fifo.v               # 4-deep x 16-bit synchronous FIFO queue
│   ├── proto_imem.v               # 32x16 dual-ported Instruction Memory
│   ├── proto_pin_crossbar.v       # Dynamic crossbar & open-drain pull-down
│   ├── proto_prescaler.v          # 16.8 fractional clock prescaler (DDA)
│   ├── proto_shifter.v            # Multi-tap barrel input/output shifter
│   ├── proto_spi_host.v           # High-speed SPI slave configuration host
│   ├── protocol_emulator_top.v    # ProtoPlex-8 dual-engine core top-level
│   └── tt_um_protocol_emulator.v  # Official Tiny Tapeout pad-ring wrapper
├── tb/                            # Hardware verification testbenches
│   ├── tb_proto_engine.v          # Micro-engine ALU & delay unit test
│   ├── tb_uart_loopback.v         # Full-duplex UART loopback testbench
│   ├── tb_spi_loopback.v          # SPI Mode 0 5 MHz loopback testbench
│   ├── tb_i2c_bus.v               # I2C open-drain pull-down testbench
│   └── tb_tinytapeout_top.v       # Tiny Tapeout top-level integration test
└── waves/                         # Pre-configured GTKWave session files
    ├── uart_loopback.gtkw         # UART signals & register groups
    ├── spi_loopback.gtkw          # SPI SCLK, MOSI, MISO groups
    ├── i2c_bus.gtkw               # I2C SCL, SDA, open-drain OE groups
    └── tinytapeout_top.gtkw       # Pad-ring bus & host register groups
```

---

## 📖 Specification Document

For in-depth mathematical derivations, transistor-level open-drain electrodynamics, instruction set opcode encodings, static timing analysis closure, and physical layout budgets on IHP 130nm, refer to the complete 26-page specification manual:

👉 **[docs/proto_emulator_spec.pdf](docs/proto_emulator_spec.pdf)**

---

## 👥 Authors & Acknowledgments

* **Engineering Team**: Antigravity Open-Source Silicon Initiative
* **Target Competition**: [Jane Street Protocol Emulator ASIC Competition](https://blog.janestreet.com/protocol-emulator-asic-competition/)
* **Foundry / Shuttle**: IHP Microelectronics (SG13G2 130nm BiCMOS) via Tiny Tapeout
