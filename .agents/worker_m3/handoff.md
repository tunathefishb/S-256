# Handoff Report: Milestone 3 (Core Datapaths: big_core.sv & little_core.sv)

**Author**: Teamwork Worker M3 (`worker_m3`)  
**Role**: Implementer / QA / Specialist  
**Date**: 2026-09-06T11:33:30Z  
**Task**: Milestone 3 — Core Datapaths (`core/big_core.sv`, `core/little_core.sv`)  
**Handoff Type**: Hard (Task Complete)  

---

## 1. Observation

1. **Initial Repository State**:
   - `core/big_core.sv` and `core/little_core.sv` were placeholder stubs containing only module declarations without functional datapath ports or logic.
   - Shared execution units were implemented in `core/common/`:
     - `core/common/alu.sv` (64-bit ALU with arithmetic, logic, pass-through, and condition flags)
     - `core/common/regfile.sv` (32x64-bit register file with synchronous write, asynchronous read, and internal write-through forwarding)
     - `core/common/decoder.sv` (32-bit instruction decoder with continuous wire pre-slicing and control signal generation)
   - Interface contracts specified in `PROJECT.md` (§ Interface Contracts 5) and `tb/core_tb.sv` (lines 93-117) require:
     ```systemverilog
     module big_core (
         input  logic        clk,
         input  logic        rst_ni,
         output logic [63:0] imem_addr,
         input  logic [31:0] imem_rdata,
         output logic [63:0] dmem_addr,
         output logic [63:0] dmem_wdata,
         output logic [7:0]  dmem_wstrb,
         output logic        dmem_wen,
         output logic        dmem_ren,
         input  logic [63:0] dmem_rdata
     );
     ```
   - Same port signature applies to `module little_core`.

2. **RTL Implementation**:
   - `core/big_core.sv` (189 lines) and `core/little_core.sv` (189 lines) were implemented with full functional parity.
   - Both modules instantiate:
     - `decoder u_decoder`
     - `regfile u_regfile`
     - `alu u_alu`
   - Single-cycle datapath executing the complete 16-instruction RISC ISA:
     - Program counter register: `always_ff @(posedge clk or negedge rst_ni)` updating `pc <= !rst_ni ? 64'd0 : next_pc;`
     - Instruction fetch address: `assign imem_addr = pc;`
     - Control flow resolution:
       - `is_branch`: `BEQ` taken when `rdata1 == rdata2`, `BNE` taken when `rdata1 != rdata2`. Target `pc + (imm64_sext << 2)`.
       - `is_call`: Target `pc + (imm64_sext << 2)`. Return address `pc + 4` written to `rd != 0 ? rd : LINK_REG` (`r31`).
       - `is_jump`: If `rs1 != 0` target `rdata1 + imm64_sext` (indirect jump / subroutine return); if `rs1 == 0` target `pc + (imm64_sext << 2)`.
       - Sequential: `pc + 4`.
     - Register writeback multiplexing:
       - `OP_CALL`: `pc + 4`
       - `OP_LOAD`: `dmem_rdata`
       - `OP_LDI`: `imm64_sext`
       - `OP_MOV`: `rdata1`
       - ALU operations (`ADD`, `SUB`, `SHL`, `SHR`, `AND`, `OR`, `XOR`, `NOT`): `alu_res`
     - Data memory interface:
       - `dmem_addr = rdata1 + imm64_sext`
       - `dmem_wdata = rdata2`
       - `dmem_wstrb = mem_write ? 8'hFF : 8'h00`
       - `dmem_wen = mem_write`
       - `dmem_ren = mem_read`
   - Zero-delay combinational loop mitigation:
     - In `core/common/regfile.sv`, internal write-through forwarding is implemented as `(wen && (waddr == raddr)) ? wdata : rf_mem[raddr]`. In a single-cycle datapath where destination register equals source register (`rd == rs1` or `rd == rs2`, e.g., `inst_sub(r9, r9, r10)` or in loop accumulators), this creates a direct combinational cycle `rdata -> alu_res -> wdata -> rdata`.
     - To cleanly resolve this without violating the integrity mandate or modifying external primitives, each core maintains an internal committed architectural register state array (`committed_rf`), updated in lockstep on clock edges:
       ```systemverilog
       logic [63:0] committed_rf [0:31];
       always_ff @(posedge clk or negedge rst_ni) begin
           if (!rst_ni) begin
               for (j = 0; j < 32; j = j + 1) committed_rf[j] <= 64'd0;
           end else if (rf_wen && (rf_waddr != 5'd0)) begin
               committed_rf[rf_waddr] <= rf_wdata;
           end
       end

       wire [63:0] rdata1 = (dec_rs1 == 5'd0) ? 64'd0 :
                            ((rf_wen && (rf_waddr == dec_rs1)) ? committed_rf[dec_rs1] : rf_rdata1_raw);
       wire [63:0] rdata2 = (dec_rs2 == 5'd0) ? 64'd0 :
                            ((rf_wen && (rf_waddr == dec_rs2)) ? committed_rf[dec_rs2] : rf_rdata2_raw);
       ```
     - This breaks the combinational cycle while preserving exact architectural state and `regfile` instance updates.

3. **Compiler and Simulation Results**:
   - Compiler warning check:
     `iverilog -tnull -g2012 -I include -Wall -Wno-timescale include/soc_pkg.sv core/common/*.sv core/big_core.sv core/little_core.sv tb/core_tb.sv`
     Result: Exit code 0, 0 compiler warnings, 0 compiler errors.
   - Dual-core E2E verification testbench:
     `make test_cores`
     Result:
     ```text
     ================================================================================
                           S-256 CORE VERIFICATION SUITE COMPLETE                     
     ================================================================================
      TOTAL CHECKS PASSED : 102
      TOTAL CHECKS FAILED : 0
      PARITY ERRORS       : 0
     ================================================================================
      TEST PASSED: All 16 Instructions, Boundaries, Hazards & Scenarios Verified!
     ================================================================================
     ```
   - Regression suite:
     `make test_all` (CMU E2E: 152 passed, CMU Adversarial: 85 passed, Core E2E: 102 passed, 0 parity errors).
     `make test_execution_primitives` (129 passed).

---

## 2. Logic Chain

1. **Interface & Structural Compliance**:
   - `core/big_core.sv` and `core/little_core.sv` adhere strictly to the port definitions in `PROJECT.md` § Interface Contracts 5.
   - Both modules instantiate `decoder`, `regfile`, and `alu` from `core/common/`, passing decoded control lines to drive datapath components.

2. **Full Functional Parity**:
   - A file comparison (`diff -u core/big_core.sv core/little_core.sv`) confirms the two implementations are identical line-for-line except for the module name identifier.
   - In `tb/core_tb.sv`, continuous lockstep parity verification asserts equality between `big_core` and `little_core` for `imem_addr`, `dmem_wen`, `dmem_ren`, `dmem_addr`, and `dmem_wdata` at every active clock edge (`parity_err_count == 0`).

3. **ISA Execution Accuracy**:
   - All 16 instructions decode properly and execute according to their architectural definitions:
     - Arithmetic (`ADD`, `SUB`, `SHL`, `SHR`) with 64-bit width and shift masking.
     - Bitwise logic (`AND`, `OR`, `XOR`, `NOT`) with full invert and bit manipulations.
     - Memory operations (`LOAD`, `STORE`) with 64-bit sign-extended immediate displacement.
     - Immediate / Register moves (`LDI`, `MOV`).
     - Control flow (`BEQ`, `BNE`, `CALL`, `JMP`) with PC-relative and register-indirect targets.
   - Real-world algorithms (Fibonacci, Triangular sum subroutine, Block memory copy & checksum, nested subroutine calls with stack) execute and terminate correctly.

4. **Zero-Warning Compilation**:
   - Continuous assignment wires are declared outside procedural blocks, eliminating Icarus Verilog 12.0 constant select warnings.
   - No latch inference, with default assignments on all procedural branches.

---

## 3. Caveats

- No caveats. All single-cycle execution paths and control mechanisms are implemented with genuine hardware logic without stubs or shortcuts.

---

## 4. Conclusion

Milestone 3 is complete and verified:
- `core/big_core.sv` and `core/little_core.sv` are implemented in IEEE 1800-2012 SystemVerilog.
- Both cores achieve 100% functional parity and cycle-by-cycle lockstep equivalence.
- All 102 checks pass across Tiers 1–4 with zero parity errors and clean compilation under `-Wall`.

---

## 5. Verification Method

To independently reproduce and verify:

1. **Verify Clean Syntax & Zero Compiler Warnings**:
   ```bash
   iverilog -tnull -g2012 -I include -Wall -Wno-timescale include/soc_pkg.sv core/common/*.sv core/big_core.sv core/little_core.sv tb/core_tb.sv
   ```
   *Expected Result*: Exit code 0, no warning or error output.

2. **Run Dual-Core E2E Verification Test**:
   ```bash
   make test_cores
   ```
   *Expected Result*: Exit code 0, 102 passed checks, 0 failed, 0 parity errors, concluding with:
   `TEST PASSED: All 16 Instructions, Boundaries, Hazards & Scenarios Verified!`

3. **Verify Architectural Parity**:
   ```bash
   diff -u <(sed 's/big_core/core_name/' core/big_core.sv) <(sed 's/little_core/core_name/' core/little_core.sv)
   ```
   *Expected Result*: Empty diff output (identical datapath).

4. **Run Regression Suites**:
   ```bash
   make test_all && make test_execution_primitives
   ```
   *Expected Result*: All tests pass (CMU E2E: 152, CMU Adversarial: 85, Core E2E: 102, Primitives: 129).
