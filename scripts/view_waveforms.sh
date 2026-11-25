#!/usr/bin/env bash
#=============================================================================
# Script to launch GTKWave with proper display configuration under Wayland / X11
# Usage:
#   ./scripts/view_waveforms.sh [uart|spi|i2c|top|all]
#=============================================================================

set -e

# Export host display variables for Wayland or X11
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export GDK_BACKEND="${GDK_BACKEND:-wayland}"

TARGET="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

echo "========================================================================"
echo "ProtoPlex-8 Waveform Viewer"
echo "Project Root: ${PROJECT_ROOT}"
echo "Display: WAYLAND_DISPLAY=${WAYLAND_DISPLAY}, GDK_BACKEND=${GDK_BACKEND}"
echo "========================================================================"

launch_wave() {
    local vcd="$1"
    local gtkw="$2"
    local name="$3"

    if [ ! -f "${vcd}" ]; then
        echo "Error: Simulation waveform '${vcd}' not found. Run 'make test' first."
        exit 1
    fi

    echo "Opening ${name} (${vcd}) in GTKWave..."
    if [ -f "${gtkw}" ]; then
        setsid gtkwave "${vcd}" "${gtkw}" </dev/null &>/dev/null &
    else
        setsid gtkwave "${vcd}" </dev/null &>/dev/null &
    fi
    echo "  -> Launched on active display (PID: $!)."
}

case "${TARGET}" in
    uart)
        launch_wave "uart_loopback.vcd" "waves/uart_loopback.gtkw" "UART Loopback Simulation"
        ;;
    spi)
        launch_wave "spi_loopback.vcd" "waves/spi_loopback.gtkw" "SPI Master/Slave Loopback Simulation"
        ;;
    i2c)
        launch_wave "i2c_bus.vcd" "waves/i2c_bus.gtkw" "I2C Bus Open-Drain Simulation"
        ;;
    top)
        launch_wave "tinytapeout_top.vcd" "waves/tinytapeout_top.gtkw" "Tiny Tapeout Top-Level Wrapper"
        ;;
    all)
        launch_wave "uart_loopback.vcd" "waves/uart_loopback.gtkw" "UART Loopback Simulation"
        sleep 0.5
        launch_wave "spi_loopback.vcd" "waves/spi_loopback.gtkw" "SPI Master/Slave Loopback Simulation"
        sleep 0.5
        launch_wave "i2c_bus.vcd" "waves/i2c_bus.gtkw" "I2C Bus Open-Drain Simulation"
        sleep 0.5
        launch_wave "tinytapeout_top.vcd" "waves/tinytapeout_top.gtkw" "Tiny Tapeout Top-Level Wrapper"
        ;;
    *)
        echo "Unknown target: ${TARGET}"
        echo "Usage: $0 [uart|spi|i2c|top|all]"
        exit 1
        ;;
esac

echo ""
echo "Waveform windows are now open on your desktop display."
echo "You can inspect the signals, zoom in/out, and take screenshots for docs/figures/."
