# AGENTS.md — S-256 SoC Design Guide for AI Agents

Welcome to the **S-256 SoC** repository. This document serves as the primary operational and architectural directive for AI coding assistants working in this codebase.

---

## 1. Project Overview & Architecture

S-256 is an exploratory System-on-a-Chip (SoC) RTL architecture implemented in **SystemVerilog (IEEE 1800-2012)**.

- **Compute Cluster**: Heterogeneous core architecture (4 Big Cores, 8 Little Cores) wrapped in `subsystems/compute_cluster.sv`.
- **Memory & Cache Hierarchy**:
  - L1 (per core) $\rightarrow$ Shared L2 (per cluster) $\rightarrow$ 3D-stacked L3 $\rightarrow$ L4 & eDRAM buffers $\rightarrow$ Main Memory Controller (`memory/memory_controller.sv`).
- **Interconnect**:
  - Global bidirectional 256-bit Ring Bus for high-throughput data (`interconnect/interfaces.sv`, `ring_node.sv`, `ring_adapter.sv`).
  - 32-bit Command/Control Bus (`comms_bus_if`).
- **Distributed GPU**: Split physically into 2 slices on opposing die edges (`gpu/gpu_slice.sv`).
- **Clock & Reset Management**: Central Management Unit (`system/cmu.sv`) drives multiple clock domains (`clk_sys`, `clk_mem`, `clk_ring`, `clk_gpu`, `clk_core`) with PLL wrappers and multi-stage reset deassertion synchronizers.

---

## 2. Directory Layout

```text
S-256/
├── AGENTS.md                 # Agent instructions and rules (this file)
├── Makefile                  # Simulation and build targets
├── README.md                 # High-level architecture and floorplan
├── topology.sv               # Top-level SoC interconnect wrapper
├── include/
│   └── soc_pkg.sv            # Global types, parameters, structs, memory map
├── lib/                      # Reusable primitives (generic_pll, reset_sync, CDC, FIFOs)
├── core/                     # Big and Little core RTL
│   └── common/               # Shared execution units (ALU, decoders)
├── subsystems/               # Cluster-level wrappers (e.g. compute_cluster.sv)
├── interconnect/             # Ring bus interfaces, adapters, and routers
├── cache/                    # Parameterized caches and eDRAM buffers
├── memory/                   # DDR / Memory controller RTL
├── system/                   # CMU, Interrupt Controller, Secure Enclave
├── gpu/                      # GPU slices
├── media/                    # ISP, display, and media engines
├── dsp/                      # DSP blocks
├── io/                       # Peripheral and host I/O interfaces
├── scripts/
│   └── generate_stubs.py     # Initial scaffold script (⚠️ READ WARNING BELOW)
└── tb/                       # Directed and random testbenches
```

---

## 3. Critical Warnings & Footguns ⚠️

1. **DO NOT blindly run `python3 scripts/generate_stubs.py`**:
   - Running `generate_stubs.py` **unconditionally overwrites** [topology.sv](file:///home/tunathefish_b/Code/S-256/topology.sv).
   - If manual wiring or custom logic has been added to `topology.sv`, running this script will clobber it.
   - Only edit or run the generator if the user explicitly requests top-level regeneration or scaffolding.
2. **Preserve Implemented Modules**:
   - Not all files are empty stubs! For example, [system/cmu.sv](file:///home/tunathefish_b/Code/S-256/system/cmu.sv) and [lib/reset_sync.sv](file:///home/tunathefish_b/Code/S-256/lib/reset_sync.sv) contain functional RTL with active testbenches. Inspect files before modifying.
3. **Include Paths**:
   - Always compile with `-I include` so that `include/soc_pkg.sv` and header files resolve properly.

---

## 4. Build, Simulation & Verification Workflow

The project uses **Icarus Verilog (`iverilog`)** and **`vvp`** for RTL simulation and verification.

### Running Existing Tests
```bash
# Run CMU reset sequence and clock generation testbench
make test_cmu

# Clean build artifacts (*.vvp, *.vcd)
make clean
```

### Adding New Testbenches
When implementing or verifying a new module:
1. Create the testbench in `tb/<module_name>_tb.sv`.
2. Add a target to [Makefile](file:///home/tunathefish_b/Code/S-256/Makefile):
   ```makefile
   <NAME>_SRC = <path_to_rtl>/<module>.sv
   <NAME>_TB  = $(TB_DIR)/<module>_tb.sv

   .PHONY: test_<name>
   test_<name>: $(BUILD_DIR)/<name>_tb.vvp
   	cd $(BUILD_DIR) && $(VVP) <name>_tb.vvp

   $(BUILD_DIR)/<name>_tb.vvp: $(PKG_SRC) $(LIB_SRC) $(<NAME>_SRC) $(<NAME>_TB)
   	@mkdir -p $(BUILD_DIR)
   	$(IVERILOG) $(IVLFLAGS) -s <name>_tb -o $@ $^
   ```
3. Dump `.vcd` files into the `build/` directory so they are cleaned up by `make clean`.
4. Run your test and verify zero runtime errors and that assertions/checks pass.

---

## 5. RTL & SystemVerilog Coding Standards

- **Standard**: SystemVerilog 2012 (`-g2012`).
- **Clock & Reset Disciplines**:
  - Resets are asynchronous assert, synchronous deassert, active-low.
  - Suffix reset signals with `_ni` or `_n` (e.g. `rst_ni` for module input port, `rst_n` for local/interface nets).
  - Always use [lib/reset_sync.sv](file:///home/tunathefish_b/Code/S-256/lib/reset_sync.sv) when bringing resets into distinct clock domains.
- **Process Blocks**:
  - Sequential registers: `always_ff @(posedge clk or negedge rst_ni)` using non-blocking `<=` assignments exclusively.
  - Combinational logic: `always_comb` using blocking `=` assignments.
  - Never infer latches; ensure all branches in `if`/`case` have complete assignments or explicit default values.
- **Interface Usage**:
  - Use interfaces defined in [interconnect/interfaces.sv](file:///home/tunathefish_b/Code/S-256/interconnect/interfaces.sv) (`ring_bus_if`, `comms_bus_if`) with appropriate modports (`master` vs `slave`) for interconnect ports.
- **Packages & Constants**:
  - Place common enums, structs, address maps, and global constants in [include/soc_pkg.sv](file:///home/tunathefish_b/Code/S-256/include/soc_pkg.sv).
  - Use `import soc_pkg::*;` inside modules rather than hardcoding magic numbers.
