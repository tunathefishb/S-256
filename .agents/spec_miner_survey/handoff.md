# Specification Miner Survey Handoff Report

**Agent**: `teamwork_preview_spec_miner`  
**Working Directory**: `/home/tunathefish_b/Code/S-256/.agents/spec_miner_survey`  
**Milestone**: Survey & Feature Inventory (Baseline Core ISA & Microarchitecture)  
**Date**: 2026-09-06  

---

## 1. Observation

### 1.1 Requirements & Authoritative Specifications
Directly observed from `/home/tunathefish_b/Code/S-256/.agents/ORIGINAL_REQUEST.md`:
- **Line 5**: "Implement the baseline P-core (`big_core`) and E-core (`little_core`) processors in SystemVerilog (IEEE 1800-2012) with a 64-bit datapath, 32 general-purpose registers (64-bit width), and compact 32-bit fixed-length instructions executing a clean 16-instruction orthogonal RISC ISA."
- **Lines 13-17**: 16-Instruction Orthogonal ISA:
  - Arithmetic (`2'b00`): `ADD` (`2'b00`), `SUB` (`2'b01`), `SHL` (`2'b10`), `SHR` (`2'b11`)
  - Logic (`2'b01`): `AND` (`2'b00`), `OR` (`2'b01`), `XOR` (`2'b10`), `NOT` (`2'b11`)
  - Memory/Data (`2'b10`): `LOAD` (`2'b00`), `STORE` (`2'b01`), `MOV` (`2'b10`), `LDI` (`2'b11`)
  - Control Flow (`2'b11`): `BEQ` (`2'b00`), `BNE` (`2'b01`), `CALL` (`2'b10`), `JMP` (`2'b11`)
- **Lines 19-24**: 32-bit Instruction Word:
  - 4-bit opcode (2-bit group, 2-bit operation): `inst[31:28]`
  - 5-bit register destination `rd`: `inst[27:23]`
  - 5-bit source register 1 `rs1`: `inst[22:18]`
  - 5-bit source register 2 `rs2`: `inst[17:13]`
  - 13-bit Immediate / branch offset: `inst[12:0]`
- **Lines 26-32**: Common execution primitives required in `core/common/`:
  - 64-bit ALU (`core/common/alu.sv`)
  - 32-entry × 64-bit register file (`core/common/regfile.sv`), `r0` hardwired to 0
  - 32-bit instruction decoder (`core/common/decoder.sv`) producing control signals and sign-extended 64-bit immediates
  - Cores in `core/big_core.sv` and `core/little_core.sv` executing identical baseline 64-bit datapath
  - Active-low asynchronous assert, synchronous deassert reset `rst_ni`
- **Lines 35-40**: Verification test suite in `tb/core_tb.sv` verifying all 16 instructions, hazards, loops, function calls, dual-core parity, and Makefile target `test_cores`.

### 1.2 Codebase State
- `/home/tunathefish_b/Code/S-256/include/soc_pkg.sv` (103 lines) currently only defines CMU parameters (lines 8-101). No ISA types or instructions are defined yet.
- `/home/tunathefish_b/Code/S-256/core/big_core.sv` and `/home/tunathefish_b/Code/S-256/core/little_core.sv` are minimal 9-line stubs.
- `/home/tunathefish_b/Code/S-256/core/common/` does not exist yet.
- Active CMU regression tests (`make test_cmu`) pass cleanly (152 checks passed, 0 failures).
- Toolchain: `iverilog 12.0 (stable)` installed at system path.

### 1.3 Empirical Probing Results
- Running SystemVerilog 2012 test simulations on `iverilog 12.0` demonstrated:
  1. Signed bitfield replication `{{51{inst[12]}}, inst[12:0]}` correctly sign-extends 13-bit immediates to 64-bit two's complement integers.
  2. Bit-slicing inside `always_comb` triggers compiler notices (`sorry: constant selects in always_* processes are not currently supported`). Using pre-sliced continuous assignments outside procedural blocks or `always @*` compiles with zero warnings under `iverilog -g2012 -Wall`.
  3. Register file write-through forwarding transparently avoids same-cycle read-after-write hazards.

---

## 2. Logic Chain

1. **Instruction Word Slicing**:
   - The total bit budget of the 32-bit instruction is $4 \text{ (opcode)} + 5 \text{ (rd)} + 5 \text{ (rs1)} + 5 \text{ (rs2)} + 13 \text{ (imm)} = 32 \text{ bits}$.
   - Because all 16 instructions share this exact bit allocation, decoding is strictly orthogonal and uniform across all instructions.

2. **Immediate & Sign Extension**:
   - 13-bit two's complement immediate covers range $[-4096, +4095]$.
   - Sign extension bit 12 replicated 51 times produces the exact 64-bit operand required by the 64-bit datapath for `LOAD`, `STORE`, `LDI`, and branch/jump offset calculations.

3. **Branch & Jump Mechanics**:
   - For `BEQ` and `BNE`, PC-relative branch target is $PC + (\text{SignExt}(imm13) \ll 2)$, covering a $\pm 16\text{ KB}$ range.
   - For `CALL`, return address $PC + 4$ is saved into link register `r31` (or `rd`), and $PC$ jumps to $PC + (\text{SignExt}(imm13) \ll 2)$.
   - For `JMP`, if $rs1 == 0$, PC-relative jump $PC + (\text{SignExt}(imm13) \ll 2)$ occurs. If $rs1 \neq 0$, register-indirect jump $R[rs1] + \text{SignExt}(imm13)$ occurs, synthesizing subroutine return via `JMP r31, 0`.

4. **Register File Invariants**:
   - Hardwiring `r0 == 64'd0` guarantees that reading `r0` returns 0 even if a prior instruction wrote to `r0` (`waddr == 0`).
   - Internal forwarding (`rdata = (wen && waddr == raddr && waddr != 0) ? wdata : regs[raddr]`) prevents single-cycle pipeline stalls on register dependencies.

5. **Toolchain & Build Compatibility**:
   - Makefile requires `-I include` and flags `-g2012 -Wall -Wno-timescale`.
   - Adhering to the verified zero-warning SystemVerilog idioms ensures the user acceptance criterion ("zero compiler errors or warnings in iverilog") is met.

---

## 3. Caveats

1. **Memory Bus Handshake**:
   - The specification defines `LOAD` and `STORE` as 64-bit operations. The baseline core assumes single-cycle synchronous memory access. If arbitration or wait states are later required by the Ring Bus or L2 cache, memory stall logic (`ready`/`valid`) will need to be introduced.
2. **Big Core vs Little Core Microarchitecture**:
   - In this baseline milestone, both `big_core.sv` and `little_core.sv` execute the identical 64-bit baseline RISC ISA. Future SIMD or coprocessor extensions should be encapsulated via clean parameter hooks in `big_core.sv` without breaking baseline ISA parity.
3. **No Branch Delay Slots**:
   - Branching is modern RISC style (no branch delay slots). Taken branches redirect the PC immediately.

---

## 4. Conclusion

- An exhaustive specification survey has been completed and documented in `/home/tunathefish_b/Code/S-256/.agents/spec_miner_survey/spec_analysis.md`.
- **33 discrete features** across 9 categories and **34 edge cases** have been identified, characterized, and empirically probed.
- The design requirements are unambiguous, orthogonal, and fully ready for implementation dispatch:
  - **Milestone 1**: `include/soc_pkg.sv` ISA enums, struct, and constants.
  - **Milestone 2**: Reusable execution units in `core/common/` (`alu.sv`, `regfile.sv`, `decoder.sv`).
  - **Milestone 3**: `core/big_core.sv` and `core/little_core.sv` core datapaths.
  - **Milestone 4**: Automated dual-core test suite in `tb/core_tb.sv` and `Makefile` target `test_cores`.

---

## 5. Verification Method

### 5.1 Artifact Inspection
- Inspect the generated survey and feature inventory:
  ```bash
  cat /home/tunathefish_b/Code/S-256/.agents/spec_miner_survey/spec_analysis.md
  ```
- Verify completeness of the `Features Discovered` (33 rows) and `Edge Cases` (34 rows) tables.

### 5.2 Toolchain Verification
- Verify baseline compilation and existing CMU regression:
  ```bash
  cd /home/tunathefish_b/Code/S-256 && make test_cmu
  ```
- When Milestone 1 through 4 implementations are created, verify with:
  ```bash
  cd /home/tunathefish_b/Code/S-256 && make test_cores
  ```
  Expected result: 0 compiler errors, 0 compiler warnings, output concludes with `TEST PASSED`.
