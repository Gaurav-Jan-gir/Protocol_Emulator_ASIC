#=============================================================================
# ProtoPlex-8 Protocol Emulator ASIC Makefile
# Target: Tiny Tapeout Shuttle on IHP 130nm CMOS (SG13G2)
#=============================================================================

.PHONY: all test asm docs clean help wave-uart wave-spi wave-i2c wave-top wave-all

all: test docs

help:
	@echo "ProtoPlex-8 Build & Verification Targets:"
	@echo "  make test      - Run all 5 hardware verification testbenches (iverilog/vvp)"
	@echo "  make asm       - Reassemble all microcode protocols to .hex bitstreams"
	@echo "  make docs      - Compile comprehensive LaTeX specification into PDF"
	@echo "  make wave-uart - Open UART simulation waveform in GTKWave"
	@echo "  make wave-spi  - Open SPI simulation waveform in GTKWave"
	@echo "  make wave-i2c  - Open I2C simulation waveform in GTKWave"
	@echo "  make wave-top  - Open Tiny Tapeout top waveform in GTKWave"
	@echo "  make wave-all  - Open all simulation waveforms in GTKWave"
	@echo "  make clean     - Remove simulation binaries, waveforms, and build artifacts"

test:
	@bash scripts/run_all_tests.sh

wave-uart:
	@bash scripts/view_waveforms.sh uart

wave-spi:
	@bash scripts/view_waveforms.sh spi

wave-i2c:
	@bash scripts/view_waveforms.sh i2c

wave-top:
	@bash scripts/view_waveforms.sh top

wave-all:
	@bash scripts/view_waveforms.sh all

asm:
	@echo "Assembling protocol microcode libraries..."
	python3 asm/assembler.py asm/protocols/uart_tx.asm -o asm/protocols/uart_tx.hex
	python3 asm/assembler.py asm/protocols/uart_rx.asm -o asm/protocols/uart_rx.hex
	python3 asm/assembler.py asm/protocols/spi_master.asm -o asm/protocols/spi_master.hex
	python3 asm/assembler.py asm/protocols/spi_slave.asm -o asm/protocols/spi_slave.hex
	python3 asm/assembler.py asm/protocols/i2c_master.asm -o asm/protocols/i2c_master.hex
	python3 asm/assembler.py asm/protocols/one_wire_master.asm -o asm/protocols/one_wire_master.hex
	@echo "All protocols successfully assembled!"

docs:
	@echo "Compiling LaTeX specification manual..."
	cd docs && pdflatex -interaction=nonstopmode proto_emulator_spec.tex
	cd docs && pdflatex -interaction=nonstopmode proto_emulator_spec.tex
	@echo "Documentation built: docs/proto_emulator_spec.pdf"

clean:
	rm -f sim_* *.vcd /tmp/*.log /tmp/iverilog_err.log
	cd docs && rm -f *.aux *.log *.out *.toc *.synctex.gz *.fls *.fdb_latexmk
