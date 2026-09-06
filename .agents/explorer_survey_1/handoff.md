# Handoff Report — Codebase Explorer 1

**Task**: Survey existing S-256 repository structure, packages, core stubs, Makefile, and verification infrastructure for baseline P-core and E-core development.  
**Working Directory**: `/home/tunathefish_b/Code/S-256/.agents/explorer_survey_1`  
**Handoff Type**: Hard (Task complete)  

---

## 1. Observation

1. **`include/soc_pkg.sv`**:
   - 103 lines total. Contains CMU parameters, register offsets (`CMU_REG_CTRL` at line 45 to `CMU_REG_VERSION` at line 66), and structs (`cmu_clk_div_reg_t` line 77, `cmu_status_reg_t` line 89).
   - Zero processor ISA opcodes, instruction bitfield formats, or datapath definitions currently exist in `soc_pkg.sv`.
2. **`core/` and `core/common/`**:
   - `core/big_core.sv` has 9 lines:
     ```systemverilog
     module big_core (
         input logic clk,
         input logic rst_n
     );
         // TODO: Implement big_core
     endmodule
     ```
   - `core/little_core.sv` has 9 lines:
     ```systemverilog
     module little_core (
         input logic clk,
         input logic rst_n
     );
         // TODO: Implement little_core
     endmodule
     ```
   - `core/common/` directory does not exist in the filesystem.
3. **`subsystems/compute_cluster.sv`**:
   - 9 lines stub:
     ```systemverilog
     module compute_cluster (
         input logic clk,
         input logic rst_n
     );
         // TODO: Implement compute_cluster
     endmodule
     ```
   - Instantiated in `topology.sv` (lines 15-18) with ports `.clk(clk), .rst_n(rst_n)`.
4. **`Makefile`**:
   - Line 9: `IVLFLAGS = -g2012 -I include -Wall -Wno-timescale`.
   - Line 17-19: `PKG_SRC = include/soc_pkg.sv`, `INTF_SRC = interconnect/interfaces.sv`, `LIB_SRC = $(wildcard $(LIB_DIR)/*.sv)`.
   - Lines 22-26: `TESTS = test_cmu test_cmu_adversarial`.
   - Command `make test_cmu` runs cleanly and exits with code 0:
     `*** VERIFICATION SUCCESS: All CMU Requirements (R1-R5) Exhaustively Satisfied! ***` (152 passed, 0 failed).
   - Target `test_cores` does not yet exist.
5. **`scripts/generate_stubs.py`**:
   - Warning in `AGENTS.md` (lines 53-56): "Running `generate_stubs.py` unconditionally overwrites `topology.sv`... Only edit or run the generator if the user explicitly requests top-level regeneration."

---

## 2. Logic Chain

1. From Observation 1, `include/soc_pkg.sv` is shared across all SoC modules and compiled first (`$(PKG_SRC)` in `Makefile:43`). Therefore, ISA opcodes (4 groups, 16 instructions), 32-bit packed instruction format (`inst_t`), and architecture parameters (`XLEN=64`, `ILEN=32`, `NUM_GPR=32`) must be appended to `include/soc_pkg.sv` without removing or mutating existing CMU definitions to avoid breaking CMU regression tests.
2. From Observation 2, `core/big_core.sv` and `core/little_core.sv` are empty stubs, and `core/common/` is missing. To fulfill Requirement R2 (`ORIGINAL_REQUEST.md:26-33`), the directory `core/common/` must be created with:
   - `alu.sv`: 64-bit ALU for arithmetic and logical operations.
   - `regfile.sv`: 32-entry × 64-bit GPR file with `r0` hardwired to 0.
   - `decoder.sv`: 32-bit instruction decoder producing control lines and 64-bit sign-extended immediate.
3. From Observation 2 & 4, reset port names in stubs use `rst_n`, but `AGENTS.md:74-75` and `ORIGINAL_REQUEST.md:32` mandate active-low asynchronous assert, synchronous deassert reset named `rst_ni` for module ports. Module definitions for `big_core` and `little_core` must use `rst_ni`.
4. From Observation 4, verification requires a new `test_cores` target in `Makefile`. Following the established pattern for `test_cmu`, `core_tb.vvp` should compile `$(PKG_SRC) $(LIB_SRC) $(CORE_SRC) $(TB_DIR)/core_tb.sv` using `$(IVERILOG) $(IVLFLAGS) -s core_tb` and run via `cd $(BUILD_DIR) && $(VVP) core_tb.vvp`.
5. From Observation 3 & 5, `subsystems/compute_cluster.sv` wraps the cores inside the SoC topology, but standalone core verification in `tb/core_tb.sv` tests `big_core` and `little_core` directly. Modifying `topology.sv` is not required for R1-R3, and `scripts/generate_stubs.py` must remain uninvoked.

---

## 3. Caveats

1. **Top-level Integration**: `subsystems/compute_cluster.sv` and `topology.sv` currently only have `clk` and `rst_n` connections. Connecting memory and ring bus interfaces to the compute cluster will be part of full SoC interconnect integration in subsequent milestones.
2. **Coprocessor / SIMD Extensions**: `ORIGINAL_REQUEST.md:31` specifies that both cores execute the identical 64-bit datapath ISA and pipeline baseline, laying the foundation for future P-core coprocessor/SIMD extensions. For this baseline milestone, `big_core` and `little_core` have architectural parity on the 16-instruction ISA.

---

## 4. Conclusion

The repository is in a clean, fully functional state for CMU logic, with clear extension points for core implementation. The baseline core development can proceed cleanly across 4 discrete milestones:
1. **M1 (ISA Definitions)**: Append 16-instruction opcode constants, struct `inst_t`, and parameters to `include/soc_pkg.sv`.
2. **M2 (Execution Primitives)**: Create `core/common/` with `alu.sv`, `regfile.sv`, and `decoder.sv`.
3. **M3 (Processor Cores)**: Implement `core/big_core.sv` and `core/little_core.sv` with 64-bit datapath and memory interfaces.
4. **M4 (E2E Verification & Build)**: Implement `tb/core_tb.sv` and add `make test_cores` to `Makefile`.

---

## 5. Verification Method

To verify these observations and analysis:
1. Inspect the survey report:
   `view_file /home/tunathefish_b/Code/S-256/.agents/explorer_survey_1/analysis.md`
2. Verify existing CMU test passing baseline:
   `make test_cmu` (all 152 checks pass)
3. Check syntax of existing packages and stubs:
   `iverilog -g2012 -I include -Wall -Wno-timescale include/soc_pkg.sv core/big_core.sv core/little_core.sv -s big_core -o /dev/null`
4. Confirm non-existence of `core/common/`:
   `ls -ld /home/tunathefish_b/Code/S-256/core/common`
