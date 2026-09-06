# Original User Request

## 2026-09-06T11:17:23Z

Implement the baseline P-core (`big_core`) and E-core (`little_core`) processors in SystemVerilog (IEEE 1800-2012) with a 64-bit datapath, 32 general-purpose registers (64-bit width), and compact 32-bit fixed-length instructions executing a clean 16-instruction orthogonal RISC ISA.

Working directory: /home/tunathefish_b/Code/S-256
Integrity mode: development

## Requirements

### R1. 16-Instruction Orthogonal ISA Definition & 32-bit Encoding
Define the ISA opcodes and 32-bit instruction format in `include/soc_pkg.sv`. The ISA is partitioned into four 2^2 groups:
- **Arithmetic (`2'b00`)**: `ADD` (`2'b00`), `SUB` (`2'b01`), `SHL` (`2'b10`), `SHR` (`2'b11`)
- **Logic (`2'b01`)**: `AND` (`2'b00`), `OR` (`2'b01`), `XOR` (`2'b10`), `NOT` (`2'b11`)
- **Memory/Data (`2'b10`)**: `LOAD` (`2'b00`), `STORE` (`2'b01`), `MOV` (`2'b10`), `LDI` (`2'b11`)
- **Control Flow (`2'b11`)**: `BEQ` (`2'b00`), `BNE` (`2'b01`), `CALL` (`2'b10`), `JMP` (`2'b11`)

Each instruction is a compact 32-bit word (`inst[31:0]`) containing:
- 4-bit opcode (2-bit group, 2-bit operation)
- 5-bit register destination `rd` (or target)
- 5-bit source register 1 `rs1`
- 5-bit source register 2 `rs2`
- Immediate / branch offset field (e.g. 13-bit or format-appropriate immediate sign/zero-extended to 64-bit)

### R2. Core Microarchitecture & Shared Execution Primitives
- Implement reusable execution units in `core/common/`:
  - 64-bit ALU supporting all arithmetic and logical operations.
  - 32-entry × 64-bit register file (`r0` through `r31`, with `r0` hardwired to 0).
  - 32-bit instruction decoder producing control signals and sign-extended 64-bit immediates.
- Implement `core/big_core.sv` and `core/little_core.sv`. Both cores execute the identical 64-bit datapath ISA and pipeline baseline, laying the foundation for future P-core coprocessor/SIMD extensions.
- Core logic must strictly observe S-256 clock/reset disciplines (active-low asynchronous assert, synchronous deassert reset `rst_ni`).

### R3. Automated Verification Testsuite
- Implement a comprehensive testbench in `tb/core_tb.sv` that instantiates both cores and verifies:
  - All 16 instructions for correct arithmetic, logic, flag, and memory behavior on 64-bit data.
  - Data hazard handling, register persistence, and branch/call/jump jump-target calculations.
  - End-to-end execution of a sample test program containing loops and function calls.
- Integrate a new `test_cores` target into Makefile using `iverilog` (-g2012) and `vvp`.

## Acceptance Criteria

### Correct Execution Across All 16 Instructions
- [ ] Every instruction (`ADD`, `SUB`, `SHL`, `SHR`, `AND`, `OR`, `XOR`, `NOT`, `LOAD`, `STORE`, `MOV`, `LDI`, `BEQ`, `BNE`, `CALL`, `JMP`) decodes from 32-bit instruction words and executes with verified 64-bit arithmetic and register state updates.

### Core Implementation Parity & Future-Ready Foundation
- [ ] Both `core/big_core.sv` and `core/little_core.sv` compile and run identically under the common test suite.
- [ ] Resets adhere strictly to S-256 active-low conventions (`rst_ni`).

### Automated Testsuite & Clean Build
- [ ] `make test_cores` builds with zero compiler errors or warnings in `iverilog` and finishes with all testbench checks passing (`TEST PASSED`).
