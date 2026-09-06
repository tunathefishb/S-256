# Handoff Report: Milestone 2 (Execution Primitives in core/common/)

**Author**: Teamwork Worker M2 (`worker_m2`)  
**Role**: Implementer / QA / Specialist  
**Date**: 2026-09-06T11:29:00Z  
**Task**: Milestone 2 — Shared Execution Primitives (`core/common/alu.sv`, `core/common/regfile.sv`, `core/common/decoder.sv`)  
**Handoff Type**: Hard (Task Complete)  

---

## 1. Observation

1. **RTL Source Files Implemented**:
   - **`core/common/alu.sv`** (77 lines):
     - Implements 64-bit ALU executing all arithmetic operations (`ALU_ADD`, `ALU_SUB`, `ALU_SHL`, `ALU_SHR`), logic operations (`ALU_AND`, `ALU_OR`, `ALU_XOR`, `ALU_NOT`), and pass-through modes (`ALU_PASSA`, `ALU_PASSB`).
     - Shift amounts pre-sliced outside `always_comb`: `wire [5:0] shamt = op_b[5:0];` strictly limiting shifts to 0..63 bits.
     - Signed 64-bit overflow calculations:
       - ADD: `wire add_ovf = (~(op_a_msb ^ op_b_msb)) & (op_a_msb ^ add_res_msb);`
       - SUB: `wire sub_ovf = (op_a_msb ^ op_b_msb) & (op_a_msb ^ sub_res_msb);`
     - Condition flags packed into `alu_flags_t`: `zero`, `negative`, `carry` (`add_cout` on ADD, `sub_borrow` on SUB), and `overflow`.
   - **`core/common/regfile.sv`** (43 lines):
     - Implements 32-entry × 64-bit general-purpose register array (`rf_mem [0:31]`).
     - Hardwired `r0` invariant: writes with `waddr == 5'd0` are ignored (`else if (wen && (waddr != 5'd0)) rf_mem[waddr] <= wdata;`), reads of `r0` unconditionally return `64'd0`.
     - Dual asynchronous read ports (`raddr1`/`rdata1`, `raddr2`/`rdata2`) and single synchronous write port (`clk`, `rst_ni`, `wen`, `waddr`, `wdata`).
     - Internal write-through forwarding:
       ```systemverilog
       assign rdata1 = (raddr1 == 5'd0) ? 64'd0 :
                       ((wen && (waddr == raddr1)) ? wdata : rf_mem[raddr1]);
       assign rdata2 = (raddr2 == 5'd0) ? 64'd0 :
                       ((wen && (waddr == raddr2)) ? wdata : rf_mem[raddr2]);
       ```
   - **`core/common/decoder.sv`** (114 lines):
     - Decodes 32-bit instruction word `inst[31:0]`.
     - Continuous pre-sliced wires outside `always_comb` avoiding Icarus Verilog 12.0 constant select warnings:
       ```systemverilog
       wire [3:0]  op_w    = inst[31:28];
       wire [1:0]  group_w = inst[31:30];
       wire [4:0]  rd_w    = inst[27:23];
       wire [4:0]  rs1_w   = inst[22:18];
       wire [4:0]  rs2_w   = inst[17:13];
       wire [12:0] imm13_w = inst[12:0];
       wire        sign_w  = inst[12];
       ```
     - Sign extension of 13-bit immediate to 64-bit: `assign imm64_sext = {{51{sign_w}}, imm13_w};`.
     - Full 16-instruction control matrix producing: `reg_write`, `mem_read`, `mem_write`, `is_branch`, `is_jump`, `is_call`, `alu_src_imm`, `illegal_inst`.

2. **Verification Suite & Commands Executed**:
   - **Syntax & Warning Check**:
     ```bash
     iverilog -tnull -g2012 -I include -Wall -Wno-timescale include/soc_pkg.sv core/common/alu.sv core/common/regfile.sv core/common/decoder.sv
     ```
     Result: Exit code 0, zero errors, zero warnings.
   - **Unit Testbench (`tb/execution_primitives_tb.sv`)**:
     ```bash
     make test_execution_primitives
     ```
     Result: Output:
     ```text
     ================================================================================
      VERIFICATION SUMMARY
     ================================================================================
      TOTAL CHECKS : 129
      PASSED       : 129
      FAILED       : 0

      *** TEST PASSED: ALL EXECUTION PRIMITIVES CHECKS PASSED ***
     ```
     Exit code 0.
   - **Regression Check on Existing Subsystems**:
     ```bash
     make test_cmu && make test_cmu_adversarial
     ```
     Result:
     - `make test_cmu`: `TOTAL CHECKS PASSED : 152, TOTAL CHECKS FAILED : 0`
     - `make test_cmu_adversarial`: `TOTAL ADVERSARIAL CHECKS PASSED : 85, TOTAL ADVERSARIAL CHECKS FAILED : 0`

---

## 2. Logic Chain

1. **Strict Conformance to Interface Contracts**:
   - Module port signatures for `alu`, `regfile`, and `decoder` match `PROJECT.md` interface specifications and `include/soc_pkg.sv` types exactly.
   - ALU operations directly use `alu_op_e` enum values (`ALU_ADD`, `ALU_SUB`, `ALU_SHL`, `ALU_SHR`, `ALU_AND`, `ALU_OR`, `ALU_XOR`, `ALU_NOT`, `ALU_PASSA`, `ALU_PASSB`).
2. **Icarus Verilog 12.0 Compatibility Guarantee**:
   - As documented in `AGENTS.md` and survey reports, selecting bits inside `always_comb` triggers `sorry: constant selects in always_* processes are not currently supported`.
   - By declaring intermediate continuous wires outside procedural blocks (`shamt`, `op_a_msb`, `op_b_msb`, `op_w`, `rd_w`, etc.), the entire codebase compiles cleanly under `-Wall -Wno-timescale` without a single compiler notice or warning.
3. **Hardware Invariant Verification**:
   - In `regfile.sv`, the hardwired `r0 == 0` invariant was verified both during write cycles (write forwarding clamps r0 to 0) and in post-clock persistent storage.
   - Internal forwarding was verified for same-cycle read-after-write (RAW) access across multiple registers, ensuring updated data is available to execution stages without inserting bubble cycles.
4. **Decoder Semantic Completeness**:
   - All 16 orthogonal RISC instructions were tested individually in `tb/execution_primitives_tb.sv` for correct opcode, group, immediate sign extension, and control flag assertions (`reg_write`, `mem_read`, `mem_write`, `is_branch`, `is_jump`, `is_call`, `alu_src_imm`, `illegal_inst`).

---

## 3. Caveats

- No caveats. All execution primitives are implemented with real synthesizable logic (no stubs, no dummy values, no bypasses). All 129 checks pass deterministically.

---

## 4. Conclusion

Milestone 2 is complete. `core/common/alu.sv`, `core/common/regfile.sv`, and `core/common/decoder.sv` are fully implemented, adhere strictly to S-256 coding standards and IEEE 1800-2012 SystemVerilog, and pass 100% of unit tests with zero compiler warnings and zero regressions. Downstream workers for Milestone 3 (`core/big_core.sv` and `core/little_core.sv`) can immediately instantiate these primitives.

---

## 5. Verification Method

To independently verify this milestone:

1. **Verify Compilation & Zero Warnings**:
   ```bash
   iverilog -tnull -g2012 -I include -Wall -Wno-timescale include/soc_pkg.sv core/common/alu.sv core/common/regfile.sv core/common/decoder.sv
   ```
   *Expected result*: Exit code 0, zero warnings, zero errors.

2. **Run Execution Primitives Unit Testbench**:
   ```bash
   make test_execution_primitives
   ```
   *Expected result*: Exit code 0, `TOTAL CHECKS : 129, PASSED : 129, FAILED : 0`, terminating with `*** TEST PASSED: ALL EXECUTION PRIMITIVES CHECKS PASSED ***`.

3. **Verify Existing Regression Suites**:
   ```bash
   make test_cmu
   make test_cmu_adversarial
   ```
   *Expected result*: All checks pass (152/152 CMU, 85/85 adversarial).
