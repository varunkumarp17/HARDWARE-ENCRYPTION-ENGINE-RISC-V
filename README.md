# Hardware AES-128 Encryption Engine (RISC-V)

A fully combinational AES-128 encryption/decryption core written in Verilog HDL, integrated as a memory-mapped peripheral on a RISC-V RV32I SoC (Ultra-Embedded core) running on an FPGA. The RISC-V processor writes plaintext + key over UART, the hardware core computes the ciphertext in a single combinational pass, and the result is read back and verified — all live, on real FPGA hardware.

> **FPGA Technology and Architecture — Project Report**
> Dept. of Electronics & Communication Engineering, NMAM Institute of Technology, Nitte (2025-2026)

---

## Overview

AES (Advanced Encryption Standard) is the industry-standard symmetric block cipher (NIST FIPS PUB 197), operating on 128-bit blocks through 10 rounds of SubBytes, ShiftRows, MixColumns, and AddRoundKey transformations.

This project implements:
- A **fully combinational** AES-128 encryption engine (all 10 rounds unrolled, no clock needed for the core logic)
- A matching **AES-128 decryption engine** (inverse cipher) for closed-loop round-trip verification
- A **memory-mapped register interface** so a RISC-V soft-core can drive the engine like any other peripheral
- **Bare-metal C firmware** that reads plaintext/key over UART, drives the hardware, and prints the ciphertext/decrypted result back to the console
- End-to-end verification in **simulation (Vivado XSim)** and on **live FPGA hardware**

```
Plaintext + Key  →  [RISC-V core, UART]  →  [AES-128 HW Engine, 0x95000000]  →  Ciphertext
                                                        ↓
                                             [AES-128 Decrypt Engine]  →  Recovered Plaintext
```

---

## Features

- ✅ NIST FIPS-197 compliant AES-128, ECB mode
- ✅ Fully combinational datapath — encryption and decryption resolve without a clock
- ✅ Inline key expansion (key schedule computed within the same combinational block)
- ✅ Closed-loop verification: decrypt module fed directly from encrypt module's ciphertext output
- ✅ Memory-mapped register interface for RISC-V integration
- ✅ Verified against NIST test vectors in Vivado XSim (simulation) and on real FPGA hardware over UART
- ✅ Interactive UART console for entering plaintext/key and viewing ciphertext/decrypted output live

---

## Repository Structure

```
├── aes128_encrypt.v      # AES-128 encryption core (10 rounds, combinational)
├── aes128_decrypt.v      # AES-128 decryption core (inverse cipher, combinational)
├── counter.v             # Memory-mapped register/AXI-lite style wrapper for peripheral access
├── counter_defs.v        # Register address/bit-field definitions
├── aes128.c              # Bare-metal C firmware: UART I/O + AES register driver
├── AnmayaTechReport.pdf  # Project report
└── screenshots/          # Simulation & hardware verification captures
    ├── waveform.png              # Vivado XSim waveform (encrypt/decrypt signals)
    ├── tcl_console.png           # Vivado XSim TCL console simulation log
    ├── wsl_op_image.png          # WSL console output (firmware run over UART)
    ├── powershell_image.png      # usbipd USB passthrough setup for WSL
    └── TCL_CONSOLE_RISC.png      # AXI-Lite waveform trace (register read/write)
```

> Note: `aes128.v` (top-level wrapper instantiating encrypt + decrypt) and the testbench `aes128_tb.v` referenced in the report should also live at the repo root alongside the files above.

---

## Architecture

### Top-Level Module — `aes128`

A structural wrapper instantiating both sub-modules and sharing the plaintext/key inputs:

```verilog
module aes128 (
    input  [127:0] plaintext,
    input  [127:0] key,
    output [127:0] ciphertext,
    output [127:0] decryptedtext
);
    aes128_encrypt ENC (.plaintext(plaintext), .key(key), .ciphertext(ciphertext));
    aes128_decrypt DEC (.ciphertext(ciphertext), .key(key), .plaintext(decryptedtext));
endmodule
```

### Encryption Datapath (`aes128_encrypt`)

Implemented entirely inside a single `always @(*)` block:

1. **Key Expansion** — 128-bit key loaded into `w[0..3]`; words `w[4..43]` computed via `RotWord`, `SubWord` (S-Box), and XOR with `Rcon`.
2. **Round Key Assembly** — `round_key[0..10]` built from the word array.
3. **Initial AddRoundKey** — `state = plaintext XOR round_key[0]`.
4. **Rounds 1–9** — SubBytes → ShiftRows → MixColumns → AddRoundKey.
5. **Final Round (10)** — SubBytes → ShiftRows → AddRoundKey (MixColumns skipped).

**ShiftRows** is implemented as a compile-time constant bit-select rearrangement (no muxes needed):

```verilog
state = {
  state[127:120], state[87:80], state[47:40], state[7:0],   // Row 0: shift 0
  state[95:88],  state[55:48], state[15:8],  state[103:96], // Row 1: shift 1
  state[63:56],  state[23:16], state[111:104],state[71:64], // Row 2: shift 2
  state[31:24],  state[119:112],state[79:72], state[39:32]  // Row 3: shift 3
};
```

**MixColumns** uses the `xtime` primitive (left shift + conditional XOR with `0x1B`) over GF(2⁸).

### Decryption Datapath (`aes128_decrypt`)

Applies the inverse cipher (InvShiftRows, InvSubBytes, InvMixColumns, AddRoundKey) in reverse round order, using a general GF(2⁸) multiplier `mul(a, b)` with fixed multipliers `{0x0E, 0x0B, 0x0D, 0x09}` for InvMixColumns.

---

## Memory Map

The AES engine is exposed as a memory-mapped peripheral at base address **`0x95000000`**; UART is mapped separately at **`0x92000000`**.

### UART Registers

| Register | Address | Function |
|---|---|---|
| `UART_RX` | `0x92000000` | Receive register |
| `UART_TX` | `0x92000004` | Transmit register |
| `UART_STAT` | `0x92000008` | Status register |

### AES Encryption Registers

| Register | Offset | Function |
|---|---|---|
| `AES_PT3..PT0` | `0x00–0x0C` | Plaintext input words |
| `AES_KEY3..KEY0` | `0x10–0x1C` | Key (shared by encrypt + decrypt) |
| `AES_CT3..CT0` | `0x20–0x2C` | Ciphertext output words |
| `AES_STATUS` | `0x30` | Status (bit 0 = `DONE`) |
| `AES_CTRL` | `0x34` | Control (bit 0 = `START`, bit 1 = `RESET`) |

### AES Decryption Registers

| Register | Offset | Function |
|---|---|---|
| `DEC_CT3..CT0` | `0x38–0x44` | Ciphertext input words |
| `DEC_PT3..PT0` | `0x48–0x54` | Recovered plaintext output words |
| `DEC_STATUS` | `0x58` | Status (bit 0 = `DONE`) |
| `DEC_CTRL` | `0x5C` | Control (bit 0 = `START`, bit 1 = `RESET`) |

---

## Firmware (`aes128.c`)

A self-contained bare-metal C program (no external symbols) that:

1. Waits for UART to settle after boot
2. Prompts for a 16-character plaintext and 16-character key over UART
3. Packs each into four big-endian 32-bit words
4. Writes them to the AES encrypt registers, pulses `START`, polls `DONE`
5. Reads back the ciphertext, feeds it into the decrypt registers, pulses `START` again
6. Reads back the decrypted plaintext and prints it in both hex and ASCII for verification

**Build:**

```bash
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
  -nostdlib -nostartfiles -Wl,--build-id=none \
  start.S aes128.c -T linker.ld -o counter.elf
```

**Run on FPGA (over UART via load scripts):**

```bash
python3 run.py -d /dev/ttyUSB1 -f counter.elf
```

---

## Verification

### 1. Simulation (Vivado XSim)

Test vector used (NIST-style):

| Field | Hex Value |
|---|---|
| Plaintext | `68656c6c6f20766172756e0505050505` |
| Key | `000102030405060708090a0b0c0d0e0f` |
| Expected Ciphertext | `7c94e6e55564f0e003b6a73553371d2e` |
| Decrypted | `68656c6c6f20766172756e0505050505` ✅ matches plaintext |

TCL console confirms all four modules (`aes128_encrypt`, `aes128_decrypt`, `aes128`, `tb_aes`) compiled and elaborated without errors, and the waveform viewer shows all four 128-bit buses (`plaintext`, `key`, `ciphertext`, `decryptedtext`) settling to stable, glitch-free values by 10 ns.

| Test | Stimulus | Expected | Actual | Result |
|---|---|---|---|---|
| TC-01 | Encrypt(PT, K) | `7c94e6e5...71d2e` | `7c94e6e5...71d2e` | ✅ PASS |
| TC-02 | Decrypt(CT) | `68656c6c...050505` | `68656c6c...050505` | ✅ PASS |

### 2. Live FPGA Hardware

Firmware was cross-compiled, loaded via UART (`usbipd` used to pass the USB-serial device through to WSL/Ubuntu), and run interactively on the live FPGA target. Example session:

```
================================
  AES-128 Hardware Engine
  Base: 0x95000000
================================

Enter Plaintext (exactly 16 chars): varunkumarp1702
Enter Key       (exactly 16 chars): 1212121212121212

Plaintext : 00766172756E6B756D6172703137303
Key       : 31323132313231323132313231323132

Ciphertext: FCB7CA253DD5570BAE9E912B7C291DB4
Decrypted : 00766172756E6B756D6172703137303
Decrypted ASCII: .varunkumarp1702
================================
  Done.
================================
```

Different keys were confirmed to produce distinct ciphertexts, and the decrypted output matched the original input in every run — confirming correct round-trip behavior on real hardware, not just in simulation.

| Criterion | Result |
|---|---|
| AES-128 simulation correctness | ✅ PASS — matches NIST FIPS-197 Appendix B vector |
| Encrypt/decrypt round trip | ✅ PASS |
| FPGA hardware execution | ✅ PASS — ELF loaded and executed on live FPGA |
| UART communication (1 Mbaud) | ✅ PASS — stable, no framing errors |
| Key-dependent ciphertext variation | ✅ PASS |
| ASCII plaintext recovery | ✅ PASS |

---

## Tools & Environment

| Parameter | Details |
|---|---|
| EDA Tool | Xilinx Vivado 2023.x |
| Simulator | Vivado XSim (behavioral) |
| HDL | Verilog (IEEE 1364-2001) |
| Target Device | `xc7s50csga324-1` |
| Host OS | Windows 10 + WSL (Ubuntu 22.04) |
| Toolchain | `riscv64-unknown-elf-gcc` (RV32IM, ILP32 ABI) |
| RISC-V Core | Ultra-Embedded RISC-V (RV32I) |

USB-to-serial passthrough into WSL was configured using `usbipd`:

```powershell
usbipd bind --busid 2-3
usbipd attach --wsl --busid 2-3
```

---

## Design Notes

- **Combinational architecture**: all 10 rounds are unrolled in a single `always @(*)` block, maximizing throughput per combinational delay at the cost of a larger logic cone — an acceptable tradeoff for an FPGA-targeted accelerator.
- **LUT-based S-Box**: the AES S-Box is a 256×8 `reg` array initialized in an `initial` block; synthesis typically maps this to block RAM or distributed LUTs.
- **Inline key expansion**: computed as part of the same combinational block rather than pre-stored, simplifying the top-level interface.
- **General GF(2⁸) multiplication**: `mul(a, b)` in the decrypt module uses a shift-and-accumulate loop, unrolled by Vivado into pure combinational logic.

---

## Planned RISC-V SoC Integration

| Step | Action |
|---|---|
| 1 | Define register map — base `0x4000_0000`, 4×32-bit regs each for plaintext/key/ciphertext |
| 2 | Write an AXI-Lite wrapper (`aes128_axi.v`) mapping AXI transactions to the registers |
| 3 | Instantiate the wrapper in the SoC top-level, connect to the Wishbone/AXI interconnect |
| 4 | Write a RISC-V driver to write plaintext+key and read back ciphertext |
| 5 | Full SoC simulation with the RISC-V core executing the driver |
| 6 | Synthesize & implement on Arty A7, verify with a hardware loopback test |

---

## Future Work

- AES-256 support
- DMA-capable burst mode for multi-block throughput
- AES-GCM authenticated encryption
- Integration with a lightweight RTOS (e.g., FreeRTOS) on the RISC-V core
- Proper PKCS#7 padding in firmware (currently implicit zero-padding for short inputs)

---

## References

1. NIST, *Specification for the Advanced Encryption Standard (AES)*, FIPS PUB 197, 2001.
2. J. Daemen and V. Rijmen, *AES Proposal: Rijndael*, Version 2, 1999.
3. Ultra-Embedded RISC-V Core — [github.com/ultraembedded/riscv](https://github.com/ultraembedded/riscv)
4. Xilinx Inc., *Vivado Design Suite User Guide: Logic Simulation* (UG900), 2023.
5. C. Paar and J. Pelzl, *Understanding Cryptography*, Springer, 2010 — Ch. 4: AES.
6. P. P. Chu, *FPGA Prototyping by Verilog Examples*, Wiley-IEEE Press, 2008.
7. IEEE Standard 1364-2001, *IEEE Standard for Verilog HDL*.

---

*Project Report — FPGA Technology and Architecture, Dept. of Electronics & Communication Engineering, NMAM Institute of Technology, Nitte — 2025-2026.*
