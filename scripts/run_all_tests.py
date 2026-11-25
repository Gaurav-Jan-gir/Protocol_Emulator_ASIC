#!/usr/bin/env python3
"""
ProtoPlex-8 ASIC Cross-Platform Verification Suite Runner
Works natively across Windows (PowerShell/CMD), macOS, and Linux without external dependencies.
"""

import sys
import os
import subprocess
import glob
import tempfile
import time

TESTS = [
    {
        "name": "engine",
        "desc": "Micro-Engine Unit Test (ALU, Delay Counters, Conditional Branching)",
        "tb": os.path.join("tb", "tb_proto_engine.v")
    },
    {
        "name": "uart",
        "desc": "UART Full-Duplex Loopback (TX 0xA5, RX Eye Centering 1.5x Tbit)",
        "tb": os.path.join("tb", "tb_uart_loopback.v")
    },
    {
        "name": "spi",
        "desc": "SPI Full-Duplex Master/Slave Loopback (5 MHz SCLK, 0x5A <-> 0xC3)",
        "tb": os.path.join("tb", "tb_spi_loopback.v")
    },
    {
        "name": "i2c",
        "desc": "I2C Bus Open-Drain Physical Layer (START, Addr 0xA6, Clock Stretch, ACK)",
        "tb": os.path.join("tb", "tb_i2c_bus.v")
    },
    {
        "name": "tt_top",
        "desc": "Tiny Tapeout Top Wrapper (24-pad I/O, Power Gate ena, Status 0xA000)",
        "tb": os.path.join("tb", "tb_tinytapeout_top.v")
    }
]

def check_tool(tool_name):
    """Check if a required executable exists in PATH."""
    from shutil import which
    return which(tool_name) is not None

def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    os.chdir(repo_root)

    print("======================================================================")
    print("      ProtoPlex-8 ASIC Cross-Platform Hardware Verification Suite      ")
    print("======================================================================")
    print(f"Platform  : {sys.platform} ({os.name})")
    print("Target PDK: IHP 130nm CMOS (SG13G2) / Tiny Tapeout TT08")
    print("Simulator : Icarus Verilog (iverilog + vvp)")
    print(f"Date      : {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print("----------------------------------------------------------------------")

    if not check_tool("iverilog") or not check_tool("vvp"):
        print("\n[ERROR] Icarus Verilog tools ('iverilog' and 'vvp') were not found in your PATH.")
        print("Please install Icarus Verilog:")
        print("  - Windows: choco install iverilog  OR  scoop install icarus-verilog")
        print("  - macOS  : brew install icarus-verilog")
        print("  - Linux  : sudo apt install iverilog (Ubuntu/Debian) or sudo dnf install iverilog (Fedora/RHEL)")
        sys.exit(1)

    rtl_files = sorted(glob.glob(os.path.join("rtl", "*.v")))
    if not rtl_files:
        print("[ERROR] No RTL files found in 'rtl/' directory.")
        sys.exit(1)

    pass_count = 0
    fail_count = 0
    tmp_dir = tempfile.gettempdir()

    for t in TESTS:
        test_name = t["name"]
        tb_file = t["tb"]
        desc = t["desc"]
        sim_bin = os.path.join(tmp_dir, f"sim_{test_name}.vvp")
        log_file = os.path.join(tmp_dir, f"sim_{test_name}.log")

        print(f"Running [{test_name:<6}] {desc} ... ", end="", flush=True)

        # 1. Compile with iverilog
        compile_cmd = ["iverilog", "-g2001", "-o", sim_bin, tb_file] + rtl_files
        comp_res = subprocess.run(compile_cmd, capture_output=True, text=True)
        if comp_res.returncode != 0:
            print("\033[91m[COMPILE ERROR]\033[0m" if sys.platform != "win32" else "[COMPILE ERROR]")
            print(comp_res.stderr)
            fail_count += 1
            continue

        # 2. Run simulation with vvp
        run_cmd = ["vvp", sim_bin]
        run_res = subprocess.run(run_cmd, capture_output=True, text=True)
        with open(log_file, "w") as lf:
            lf.write(run_res.stdout)
            lf.write(run_res.stderr)

        # 3. Check results
        output = run_res.stdout + run_res.stderr
        if run_res.returncode == 0 and "PASSED" in output and "FAIL" not in output:
            print("\033[92m[PASS 100%]\033[0m" if sys.platform != "win32" else "[PASS 100%]")
            pass_count += 1
        else:
            print("\033[91m[FAILED]\033[0m" if sys.platform != "win32" else "[FAILED]")
            fail_count += 1
            print("--- Simulation Output (Last 15 lines) ---")
            lines = output.strip().splitlines()
            for l in lines[-15:]:
                print(f"  {l}")

        # Clean up temporary binary
        if os.path.exists(sim_bin):
            try:
                os.remove(sim_bin)
            except OSError:
                pass

    total = pass_count + fail_count
    print("----------------------------------------------------------------------")
    print(f"Verification Summary: {pass_count} Passed, {fail_count} Failed out of {total} Testbenches")
    print("======================================================================")

    if fail_count == 0:
        msg = ">>> ALL HARDWARE SIMULATION TESTS PASSED CLEANLY! <<<"
        print(f"\033[92m{msg}\033[0m" if sys.platform != "win32" else msg)
        return 0
    else:
        msg = ">>> VERIFICATION REPORTED TEST FAILURES! <<<"
        print(f"\033[91m{msg}\033[0m" if sys.platform != "win32" else msg)
        return 1

if __name__ == "__main__":
    sys.exit(main())
