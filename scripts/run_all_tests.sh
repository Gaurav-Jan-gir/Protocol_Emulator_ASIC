#!/usr/bin/env bash
#=============================================================================
# ProtoPlex-8 Protocol Emulator ASIC Verification Suite
# Runs all 5 hardware testbenches and reports overall verification status.
#=============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "======================================================================"
echo "          ProtoPlex-8 ASIC Comprehensive Verification Suite          "
echo "======================================================================"
echo "Target PDK: IHP 130nm CMOS (SG13G2) / Tiny Tapeout Shuttle"
echo "Simulator : Icarus Verilog 12.0"
echo "Date      : $(date)"
echo "----------------------------------------------------------------------"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
    TEST_NAME="$1"
    TB_FILE="$2"
    SIM_BIN="sim_${TEST_NAME}"

    echo -n "Running [${TEST_NAME}] (${TB_FILE}) ... "
    
    if iverilog -g2001 -o "${SIM_BIN}" "${TB_FILE}" rtl/*.v > /tmp/iverilog_err.log 2>&1; then
        if vvp "${SIM_BIN}" > "/tmp/${TEST_NAME}.log" 2>&1; then
            if grep -q "PASSED" "/tmp/${TEST_NAME}.log" && ! grep -q "FAIL" "/tmp/${TEST_NAME}.log"; then
                echo -e "\033[0;32m[PASS 100%]\033[0m"
                PASS_COUNT=$((PASS_COUNT + 1))
            else
                echo -e "\033[0;31m[FAILED]\033[0m"
                FAIL_COUNT=$((FAIL_COUNT + 1))
                cat "/tmp/${TEST_NAME}.log" | tail -n 15
            fi
        else
            echo -e "\033[0;31m[RUNTIME ERROR]\033[0m"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            cat "/tmp/${TEST_NAME}.log" | tail -n 15
        fi
    else
        echo -e "\033[0;31m[COMPILE ERROR]\033[0m"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        cat /tmp/iverilog_err.log
    fi
}

# 1. Micro-engine Unit Test
run_test "engine" "tb/tb_proto_engine.v"

# 2. UART Full-Duplex Loopback
run_test "uart" "tb/tb_uart_loopback.v"

# 3. SPI Full-Duplex Master-Slave Loopback
run_test "spi" "tb/tb_spi_loopback.v"

# 4. I2C Open-Drain Bus with Clock Stretching
run_test "i2c" "tb/tb_i2c_bus.v"

# 5. Tiny Tapeout Top-Level Wrapper
run_test "tt_top" "tb/tb_tinytapeout_top.v"

echo "----------------------------------------------------------------------"
echo "Verification Summary: ${PASS_COUNT} Passed, ${FAIL_COUNT} Failed out of $((PASS_COUNT + FAIL_COUNT)) Tests"
echo "======================================================================"

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "\033[0;32m>>> ALL HARDWARE SIMULATION TESTS PASSED CLEANLY! <<<\033[0m"
    exit 0
else
    echo -e "\033[0;31m>>> VERIFICATION SUITE REPORTED FAILURES! <<<\033[0m"
    exit 1
fi
