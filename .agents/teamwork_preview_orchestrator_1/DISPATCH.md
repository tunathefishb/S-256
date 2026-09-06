# Dispatch Log

## 2026-09-06T11:17:58Z

You are the Project Orchestrator for S-256 SoC development.

Your working directory is: /home/tunathefish_b/Code/S-256/.agents/teamwork_preview_orchestrator_1
The project root is: /home/tunathefish_b/Code/S-256
The authoritative request is recorded in: /home/tunathefish_b/Code/S-256/.agents/ORIGINAL_REQUEST.md

Your mission:
Implement the baseline P-core (`big_core`) and E-core (`little_core`) processors in SystemVerilog (IEEE 1800-2012) with a 64-bit datapath, 32 general-purpose registers (64-bit width), and compact 32-bit fixed-length instructions executing a clean 16-instruction orthogonal RISC ISA, plus automated verification testsuite.

Strict requirements:
1. R1: Define 16-instruction orthogonal ISA opcodes, groups, and 32-bit format in `include/soc_pkg.sv`:
   - Arithmetic (2'b00): ADD (2'b00), SUB (2'b01), SHL (2'b10), SHR (2'b11)
   - Logic (2'b01): AND (2'b00), OR (2'b01), XOR (2'b10), NOT (2'b11)
   - Memory/Data (2'b10): LOAD (2'b00), STORE (2'b01), MOV (2'b10), LDI (2'b11)
   - Control Flow (2'b11): BEQ (2'b00), BNE (2'b01), CALL (2'b10), JMP (2'b11)
   - 32-bit instruction word: opcode [31:28] (2-bit group, 2-bit op), rd [27:23], rs1 [22:18], rs2 [17:13], immediate/offset field (e.g. 13-bit imm[12:0] sign/zero extended to 64-bit).
2. R2: Implement reusable execution units in `core/common/`:
   - 64-bit ALU supporting all arithmetic and logical operations.
   - 32-entry x 64-bit register file (r0..r31, with r0 hardwired to 0).
   - 32-bit instruction decoder producing control signals and sign-extended 64-bit immediates.
   - Implement `core/big_core.sv` and `core/little_core.sv`. Both cores execute the identical 64-bit datapath ISA and pipeline baseline.
   - Observe S-256 clock/reset disciplines: active-low asynchronous assert, synchronous deassert reset `rst_ni`.
3. R3: Automated Verification Testsuite:
   - Implement testbench in `tb/core_tb.sv` instantiating both cores and verifying:
     - All 16 instructions for correct arithmetic, logic, flag, and memory behavior on 64-bit data.
     - Data hazard handling, register persistence, branch/call/jump jump-target calculations.
     - End-to-end execution of a sample test program containing loops and function calls.
   - Add `test_cores` target in `Makefile` using `iverilog` (-g2012) and `vvp`.
   - `make test_cores` must build with zero compiler errors/warnings in `iverilog` and finish with `TEST PASSED`.

Operational rules:
- Respect AGENTS.md (do NOT run `python3 scripts/generate_stubs.py`, compile with `-I include`, active-low reset `rst_ni`, etc.).
- Maintain `BRIEFING.md` and `progress.md` in your working directory (`/home/tunathefish_b/Code/S-256/.agents/teamwork_preview_orchestrator_1/`).
- Actively manage specialists/subagents as needed.
- When all work is done and verified with `make test_cores`, report completion back to the Sentinel.
