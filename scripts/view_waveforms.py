#!/usr/bin/env python3
"""
ProtoPlex-8 ASIC Cross-Platform Waveform Viewer
Launches GTKWave with pre-configured signal save files on Windows, macOS, and Linux.
"""

import sys
import os
import subprocess
import shutil

WAVES = {
    "uart": {
        "vcd": "uart_loopback.vcd",
        "gtkw": os.path.join("waves", "uart_loopback.gtkw"),
        "title": "UART Loopback Simulation"
    },
    "spi": {
        "vcd": "spi_loopback.vcd",
        "gtkw": os.path.join("waves", "spi_loopback.gtkw"),
        "title": "SPI Master/Slave Loopback Simulation"
    },
    "i2c": {
        "vcd": "i2c_bus.vcd",
        "gtkw": os.path.join("waves", "i2c_bus.gtkw"),
        "title": "I2C Bus Open-Drain Simulation"
    },
    "top": {
        "vcd": "tinytapeout_top.vcd",
        "gtkw": os.path.join("waves", "tinytapeout_top.gtkw"),
        "title": "Tiny Tapeout Top-Level Integration"
    }
}

def launch_wave(vcd, gtkw, title):
    if not os.path.isfile(vcd):
        print(f"[ERROR] Waveform dump '{vcd}' not found. Please run simulations first ('python scripts/run_all_tests.py').")
        return False

    print(f"Opening {title} ({vcd}) in GTKWave...")

    env = os.environ.copy()
    if sys.platform.startswith("linux"):
        # Auto-configure Wayland / X11 defaults if present
        if "WAYLAND_DISPLAY" in env and "GDK_BACKEND" not in env:
            env["GDK_BACKEND"] = "wayland"

    cmd = ["gtkwave", vcd]
    if os.path.isfile(gtkw):
        cmd.append(gtkw)

    try:
        if sys.platform == "win32":
            subprocess.Popen(cmd, creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS)
        elif sys.platform == "darwin":
            # On macOS, check if command-line gtkwave exists, or use open -a
            if shutil.which("gtkwave"):
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            else:
                subprocess.Popen(["open", "-a", "gtkwave", "--args"] + cmd[1:])
        else:
            subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        print("  -> GTKWave window launched successfully.")
        return True
    except Exception as e:
        print(f"[ERROR] Failed to launch GTKWave: {e}")
        print("Please ensure 'gtkwave' is installed and added to your system PATH.")
        return False

def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    os.chdir(repo_root)

    target = sys.argv[1].lower() if len(sys.argv) > 1 else "all"

    if not shutil.which("gtkwave"):
        print("[WARNING] 'gtkwave' executable was not detected in your PATH.")
        print("Installation instructions:")
        print("  - Windows: choco install gtkwave  OR  scoop install gtkwave")
        print("  - macOS  : brew install --cask gtkwave")
        print("  - Linux  : sudo apt install gtkwave  OR  sudo dnf install gtkwave")

    if target == "all":
        for k in ["uart", "spi", "i2c", "top"]:
            launch_wave(WAVES[k]["vcd"], WAVES[k]["gtkw"], WAVES[k]["title"])
    elif target in WAVES:
        launch_wave(WAVES[target]["vcd"], WAVES[target]["gtkw"], WAVES[target]["title"])
    else:
        print(f"Unknown target: '{target}'")
        print("Usage: python scripts/view_waveforms.py [uart|spi|i2c|top|all]")
        sys.exit(1)

if __name__ == "__main__":
    main()
