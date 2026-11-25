#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIG_SRC_DIR="${SCRIPT_DIR}/../docs/figures/src"
FIG_OUT_DIR="${SCRIPT_DIR}/../docs/figures"

cd "${FIG_SRC_DIR}"

FIGURES=(
    "pinout_diagram"
    "pci_bridge_architecture"
    "asym_clock_recovery"
    "multi_baud_dual_engine"
    "uart_loopback"
    "spi_loopback"
    "i2c_bus"
)

echo "Building 7 high-resolution figures for documentation..."

for fig in "${FIGURES[@]}"; do
    echo "  -> Compiling ${fig}.tex to 300 DPI PNG..."
    pdflatex -interaction=nonstopmode "${fig}.tex" > /dev/null
    pdftoppm -png -r 300 "${fig}.pdf" "${FIG_OUT_DIR}/${fig}"
    mv "${FIG_OUT_DIR}/${fig}-1.png" "${FIG_OUT_DIR}/${fig}.png"
done

echo "All figures generated successfully in ${FIG_OUT_DIR}:"
ls -lh "${FIG_OUT_DIR}"/*.png
