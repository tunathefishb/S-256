# S-256 Baseline Core Development — Codebase & Structural Survey

**Author**: Teamwork Explorer (Codebase Explorer 1)  
**Date**: 2026-09-06  
**Working Directory**: `/home/tunathefish_b/Code/S-256/.agents/explorer_survey_1`  
**Reference Documents**: `ORIGINAL_REQUEST.md`, `AGENTS.md`, `PROJECT.md`, `README.md`, `Makefile`  

---

## 1. Executive Summary

This survey analyzes the current state of the S-256 SoC repository in preparation for implementing the baseline P-core (`big_core`) and E-core (`little_core`) processors. The target design requires a 64-bit datapath, 32 64-bit general-purpose registers (GPRs with `r0` hardwired to 0), a compact 32-bit instruction format encoding a clean 16-instruction orthogonal RISC ISA, reusable execution primitives in `core/common/`, automated E2E verification in `tb/core_tb.sv`, and seamless build integration via `make test_cores` in `Makefile`.

The survey confirms:
1. **`include/soc_pkg.sv`** currently contains CMU definitions (5 domains, CSR addresses, FSM states, structs) and must be extended with the 16-instruction ISA opcodes, instruction bitfield struct, and architectural constants while preserving existing CMU logic.
2. **`core/`** currently contains only minimal 9-line stubs (`big_core.sv` and `little_core.sv`). The directory **`core/common/`** does not yet exist and must be created to hold `alu.sv`, `regfile.sv`, and `decoder.sv`.
3. **`subsystems/compute_cluster.sv`** is currently a stub taking `clk` and `rst_n`, instantiated in `topology.sv`.
4. **`Makefile`** compiles with `iverilog -g2012 -I include -Wall -Wno-timescale` and runs via `vvp`. CMU verification targets pass cleanly with 152 checks. A new `test_cores` target must be added alongside `test_cmu`.
5. **Critical footguns**: `scripts/generate_stubs.py` must NEVER be run (it clobbers `topology.sv`), reset naming must follow `rst_ni` active-low conventions, and package inclusion order must strictly position `include/soc_pkg.sv` first during compilation.

---

## 2. Codebase Survey & Existing File Inventory

### 2.1 Package Definitions (`include/soc_pkg.sv`)
- **Current File Size**: 103 lines (5,151 bytes).
- **Existing Content**:
  - Base address and aperture for CMU: `CMU_BASE_ADDR = 32'h1000_0000`, `CMU_ADDR_MASK = 32'h0000_0FFF`, `CMU_NUM_DOMAINS = 5`.
  - Domain enumerations and bitmasks: `cmu_domain_e` (`CMU_DOMAIN_SYS` through `CMU_DOMAIN_CORE`), bitmasks `CMU_MASK_SYS` through `CMU_MASK_ALL`.
  - Boot state enumeration: `cmu_boot_state_e` (`BOOT_ST_INIT` through `BOOT_ST_RUN`).
  - CMU CSR register offset constants (`CMU_REG_CTRL` through `CMU_REG_VERSION`).
  - Bus response status codes: `COMMS_RESP_OKAY = 2'b00`, `COMMS_RESP_SLVERR = 2'b10`.
  - Packed structs: `cmu_clk_div_reg_t`, `cmu_domain_mask_reg_t`, `cmu_status_reg_t`, `cmu_boot_status_reg_t`.
- **Modifications Required for ISA (R1)**:
  - Add opcode group enumerations / constants (`2'b00`: Arithmetic, `2'b01`: Logic, `2'b10`: Memory/Data, `2'b11`: Control Flow).
  - Add 4-bit opcode constants:
    - Arithmetic: `OP_ADD = 4'b00_00`, `OP_SUB = 4'b00_01`, `OP_SHL = 4'b00_10`, `OP_SHR = 4'b00_11`
    - Logic: `OP_AND = 4'b01_00`, `OP_OR = 4'b01_01`, `OP_XOR = 4'b01_10`, `OP_NOT = 4'b01_11`
    - Memory/Data: `OP_LOAD = 4'b10_00`, `OP_STORE = 4'b10_01`, `OP_MOV = 4'b10_10`, `OP_LDI = 4'b10_11`
    - Control Flow: `OP_BEQ = 4'b11_00`, `OP_BNE = 4'b11_01`, `OP_CALL = 4'b11_10`, `OP_JMP = 4'b11_11`
  - Add architectural parameters:
    - `XLEN = 64` (64-bit datapath width)
    - `ILEN = 32` (32-bit instruction word width)
    - `NUM_GPR = 32` (32 general-purpose registers)
    - `REG_ADDR_WIDTH = 5` (5-bit register indexing)
    - `IMM_WIDTH = 13` (13-bit immediate field width)
    - `LINK_REG = 5'd31` (convention for subroutine call link register)
  - Add packed 32-bit instruction struct `inst_t`:
    ```systemverilog
    typedef struct packed {
        logic [3:0]  opcode; // [31:28]: [3:2] group, [1:0] sub-op
        logic [4:0]  rd;     // [27:23]: Destination register
        logic [4:0]  rs1;    // [22:18]: Source register 1
        logic [4:0]  rs2;    // [17:13]: Source register 2
        logic [12:0] imm13;  // [12:0] : 13-bit immediate / branch offset
    } inst_t;
    ```
  - Add ALU operation enumeration `alu_op_e` matching the ALU control demands.
- **Critical Preservation Rule**: Do NOT alter or delete existing CMU definitions in `soc_pkg.sv` as active CMU testbenches (`tb/cmu_tb.sv`, `tb/cmu_adversarial_tb.sv`) rely on them.

---

### 2.2 Core Modules & Execution Primitives (`core/` & `core/common/`)
- **Current File State**:
  - `core/big_core.sv`: 9-line stub (`module big_core (input logic clk, input logic rst_n); ... endmodule`).
  - `core/little_core.sv`: 9-line stub (`module little_core (input logic clk, input logic rst_n); ... endmodule`).
  - `core/common/`: Directory does not exist yet.
- **Required New Modules in `core/common/`**:
  1. **`core/common/alu.sv`**:
     - 64-bit ALU performing:
       - Arithmetic: `ADD`, `SUB`, `SHL`, `SHR` (using `rs2[5:0]` for 64-bit shift width).
       - Logic: `AND`, `OR`, `XOR`, `NOT` (`~rs1`).
     - Zero flag (`zero = (result == 64'd0)`) and sign/carry status if applicable.
     - Pure combinational logic using `always_comb`.
  2. **`core/common/regfile.sv`**:
     - 32 general-purpose 64-bit registers (`logic [63:0] registers [0:31]`).
     - Two asynchronous / combinational read ports (`rdata1`, `rdata2` addressed by `raddr1`, `raddr2`).
     - One synchronous write port (`waddr`, `wdata`, `wen`, `clk`, `rst_ni`).
     - **Hardwired `r0` Invariant**: `r0` is unconditionally 0 (`assign rdata1 = (raddr1 == 5'd0) ? 64'd0 : registers[raddr1]`). Writes to `r0` (`waddr == 5'd0`) are strictly ignored.
     - Synchronous reset clears all registers to `64'h0` upon `rst_ni == 1'b0`.
     - Internal write-forwarding (bypass) when `wen && (waddr != 0) && (waddr == raddr)`.
  3. **`core/common/decoder.sv`**:
     - Decodes 32-bit instruction word into control signals.
     - Extracts `opcode`, `rd`, `rs1`, `rs2`, `imm13`.
     - Produces 64-bit sign-extended immediate: `imm64 = {{51{inst[12]}}, inst[12:0]}`.
     - Controls ALU source selection (immediate vs register), register write enable, memory read/write enable, branch condition type, and jump/call directives.
- **Core Implementations (`core/big_core.sv` & `core/little_core.sv`)**:
  - Both cores implement the exact 64-bit datapath, 32 registers, and 16-instruction ISA.
  - Reset port must be updated from `rst_n` to `rst_ni` per S-256 standard.
  - Core interfaces must provide instruction memory (`imem_addr`, `imem_rdata`) and data memory (`dmem_addr`, `dmem_wdata`, `dmem_wen`, `dmem_ren`, `dmem_rdata`) buses.
  - Observability signals: `pc` output and register inspection interface or debug signals to facilitate non-invasive verification in testbenches.
  - `big_core.sv` includes architecture hooks / parameterization for future coprocessor/SIMD extensions while remaining 100% ISA-compliant with `little_core.sv`.

---

### 2.3 Subsystem Wrapper & Top-Level (`subsystems/compute_cluster.sv` & `topology.sv`)
- **`subsystems/compute_cluster.sv`**:
  - Current state: 9-line stub taking `input logic clk, input logic rst_n`.
  - Future role: Hierarchical container wrapping 4 Big Cores and 8 Little Cores, shared L2 caches, and CMU clock/reset drops.
  - For baseline core milestone: Maintain port signature compatibility with `topology.sv`.
- **`topology.sv`**:
  - Current state: Instantiates `compute_cluster u_compute_cluster (.clk(clk), .rst_n(rst_n));`, `memory_controller`, `generic_cache`, `gpu_slice`, `ring_bus_if`, `comms_bus_if`.
  - **CRITICAL**: `scripts/generate_stubs.py` will unconditionally overwrite `topology.sv` if run. Never execute this script.

---

### 2.4 Makefile & Verification Infrastructure
- **Existing Build Setup**:
  - Toolchain variables:
    ```makefile
    IVERILOG ?= iverilog
    VVP      ?= vvp
    GTKWAVE  ?= gtkwave
    IVLFLAGS  = -g2012 -I include -Wall -Wno-timescale
    ```
  - Verification targets currently defined: `test_cmu`, `test_cmu_adversarial`.
  - Existing execution pattern:
    ```makefile
    $(BUILD_DIR)/<target>.vvp: $(PKG_SRC) $(LIB_SRC) <RTL_SRCS> $(TB_DIR)/<tb>.sv
        @mkdir -p $(BUILD_DIR)
        $(IVERILOG) $(IVLFLAGS) -s <tb> -o $@ $^

    test_<target>: $(BUILD_DIR)/<target>.vvp
        cd $(BUILD_DIR) && $(VVP) <target>.vvp
    ```
- **New Target Needed for R3**:
  - Add `test_cores`:
    ```makefile
    CORE_COMMON_SRC = core/common/alu.sv \
                      core/common/regfile.sv \
                      core/common/decoder.sv

    CORE_SRC        = core/big_core.sv \
                      core/little_core.sv \
                      $(CORE_COMMON_SRC)

    $(BUILD_DIR)/core_tb.vvp: $(PKG_SRC) $(LIB_SRC) $(CORE_SRC) $(TB_DIR)/core_tb.sv
        @mkdir -p $(BUILD_DIR)
        $(IVERILOG) $(IVLFLAGS) -s core_tb -o $@ $^

    .PHONY: test_cores
    test_cores: $(BUILD_DIR)/core_tb.vvp
        cd $(BUILD_DIR) && $(VVP) core_tb.vvp
    ```
  - Include `test_cores` in `TESTS = test_cmu test_cmu_adversarial test_cores`.
  - Update `make help` and `make all`.

---

### 2.5 Verification Testbench Survey (`tb/` & `tb/core_tb.sv`)
- **Existing Patterns in `tb/cmu_tb.sv` & `tb/cmu_adversarial_tb.sv`**:
  - `timescale 1ns/1ps`.
  - Color/banner reporting:
    - Individual assertions: `[time] [PASS] <description>` or `[FAIL] <description>`.
    - Total tally: `TOTAL CHECKS PASSED`, `TOTAL CHECKS FAILED`.
    - Final completion string: `TEST PASSED` or `*** VERIFICATION SUCCESS ***`.
  - Error assertion: `$fatal(1, ...)` or error increment on unexpected behavior.
  - VCD generation: `$dumpfile("core_tb.vcd"); $dumpvars(0, core_tb);`.
- **Required Verification Coverage in `tb/core_tb.sv`**:
  1. **Arithmetic Instruction Suite**:
     - `ADD`: 64-bit addition, positive + positive, positive + negative, carry-out, zero result.
     - `SUB`: 64-bit subtraction, borrow, subtraction resulting in 0, negative results (2's complement).
     - `SHL`: Logical shift left by 0, 1, 32, 63 bits (verifying shift amount mask `rs2[5:0]`).
     - `SHR`: Logical shift right by 0, 1, 32, 63 bits.
  2. **Logic Instruction Suite**:
     - `AND`: Bitwise AND with masks, walking 1s, zeroing.
     - `OR`: Bitwise OR combining bits.
     - `XOR`: Bitwise XOR toggling, identical operand identity (`x ^ x == 0`).
     - `NOT`: Bitwise NOT bit inversion (`~0 == -1`).
  3. **Memory & Data Movement Suite**:
     - `LDI`: Loading 13-bit sign-extended immediate into 64-bit destination register. Verify positive immediates (`0x0000_0000_0000_07FF`) and negative immediates (`0xFFFF_FFFF_FFFF_F800`).
     - `MOV`: Register-to-register data movement (`rd = rs1`).
     - `STORE`: Writing 64-bit value from `rs2` to memory address `rs1 + offset`.
     - `LOAD`: Reading 64-bit value from memory address `rs1 + offset` into `rd`.
  4. **Control Flow Suite**:
     - `BEQ`: Branch if equal (`rs1 == rs2`) taken vs not taken.
     - `BNE`: Branch if not equal (`rs1 != rs2`) taken vs not taken.
     - `CALL`: Saves return address (`PC + 4`) to link register `r31`, jumps to target (`PC + offset` or absolute).
     - `JMP`: Unconditional jump to target address.
  5. **Register File Integrity**:
     - `r0` Hardwired Zero: Attempts to write non-zero values to `r0` via `LDI`, `ADD`, `LOAD`, etc., verifying `r0` reads back `64'h0` at all times.
     - 32-register isolation: Write distinct 64-bit values to `r1` through `r31` and read back without cross-talk.
  6. **Hazard Handling & Forwarding**:
     - Read-After-Write (RAW) back-to-back dependency chains (e.g. `ADD r1, r2, r3` followed immediately by `SUB r4, r1, r5`).
  7. **Realistic Test Program**:
     - Fibonacci series calculation or recursive/looping factorial utilizing memory buffers, loop counters (`BNE`), function calls (`CALL`), and returns (`JMP r31`).
  8. **Core Parity**:
     - Both `big_core` and `little_core` instantiated side-by-side in `core_tb.sv`, fed identical stimulus, and compared for cycle-by-cycle or retirement parity.

---

## 3. Interface Contracts & SystemVerilog Architecture

### 3.1 32-Bit Instruction Bitfield Specification

```text
 31        28 27       23 22       18 17       13 12                         0
+------------+-----------+-----------+-----------+-------------------------------+
|   opcode   |    rd     |    rs1    |    rs2    |             imm13             |
|   (4-bit)  |  (5-bit)  |  (5-bit)  |  (5-bit)  |            (13-bit)           |
+------------+-----------+-----------+-----------+-------------------------------+
```

| Field | Bit Range | Description |
|-------|-----------|-------------|
| `opcode` | `[31:28]` | `opcode[3:2]` = Group (`00`: Arith, `01`: Logic, `10`: Mem, `11`: Ctrl)<br>`opcode[1:0]` = Operation code within group |
| `rd` | `[27:23]` | Destination register (`r0`..`r31`). For store/branches, repurposed as secondary operand or ignored. |
| `rs1` | `[22:18]` | First source operand register (`r0`..`r31`). |
| `rs2` | `[17:13]` | Second source operand register (`r0`..`r31`). Used as store source data in `STORE`. |
| `imm13` | `[12:0]` | 13-bit immediate / branch offset. Sign-extended to 64 bits for datapath operations. |

### 3.2 16-Instruction Orthogonal Opcode Encoding Matrix

| Group (`[3:2]`) | Sub-op (`[1:0]`) | Opcode (`[3:0]`) | Mnemonic | Operation Description |
|:---:|:---:|:---:|:---:|:---|
| `2'b00` (Arith) | `2'b00` | `4'b0000` (`0x0`) | **ADD** | `rd = rs1 + rs2` (or `rs1 + imm` if immediate mode) |
| `2'b00` (Arith) | `2'b01` | `4'b0001` (`0x1`) | **SUB** | `rd = rs1 - rs2` |
| `2'b00` (Arith) | `2'b10` | `4'b0010` (`0x2`) | **SHL** | `rd = rs1 << rs2[5:0]` |
| `2'b00` (Arith) | `2'b11` | `4'b0011` (`0x3`) | **SHR** | `rd = rs1 >> rs2[5:0]` (logical shift) |
| `2'b01` (Logic) | `2'b00` | `4'b0100` (`0x4`) | **AND** | `rd = rs1 & rs2` |
| `2'b01` (Logic) | `2'b01` | `4'b0101` (`0x5`) | **OR**  | `rd = rs1 \| rs2` |
| `2'b01` (Logic) | `2'b10` | `4'b0110` (`0x6`) | **XOR** | `rd = rs1 ^ rs2` |
| `2'b01` (Logic) | `2'b11` | `4'b0111` (`0x7`) | **NOT** | `rd = ~rs1` |
| `2'b10` (Mem)   | `2'b00` | `4'b1000` (`0x8`) | **LOAD**| `rd = mem[rs1 + imm64]` |
| `2'b10` (Mem)   | `2'b01` | `4'b1001` (`0x9`) | **STORE**| `mem[rs1 + imm64] = rs2` |
| `2'b10` (Mem)   | `2'b10` | `4'b1010` (`0xA`) | **MOV** | `rd = rs1` |
| `2'b10` (Mem)   | `2'b11` | `4'b1011` (`0xB`) | **LDI** | `rd = imm64` (sign-extended 13-bit immediate) |
| `2'b11` (Ctrl)  | `2'b00` | `4'b1100` (`0xC`) | **BEQ** | `if (rs1 == rs2) PC = PC + (imm64 << 2)` |
| `2'b11` (Ctrl)  | `2'b01` | `4'b1101` (`0xD`) | **BNE** | `if (rs1 != rs2) PC = PC + (imm64 << 2)` |
| `2'b11` (Ctrl)  | `2'b10` | `4'b1110` (`0xE`) | **CALL**| `r31 = PC + 4; PC = PC + (imm64 << 2)` (or register indirect) |
| `2'b11` (Ctrl)  | `2'b11` | `4'b1111` (`0xF`) | **JMP** | `PC = PC + (imm64 << 2)` (or `rs1 + imm64`) |

---

### 3.3 Core External Port Interface Specification

```systemverilog
module big_core (
    input  logic        clk,
    input  logic        rst_ni,

    // Instruction Memory Interface
    output logic [63:0] imem_addr,
    input  logic [31:0] imem_rdata,

    // Data Memory Interface
    output logic [63:0] dmem_addr,
    output logic [63:0] dmem_wdata,
    output logic        dmem_wen,
    output logic        dmem_ren,
    input  logic [63:0] dmem_rdata,

    // Status / Observability (for TB & Verification)
    output logic [63:0] pc,
    output logic        halted
);
```

*(Note: `little_core` exposes the identical port contract).*

---

## 4. Constraints, Warnings & Footguns

1. **`generate_stubs.py` Overwrite Hazard**:
   - Running `python3 scripts/generate_stubs.py` clobbers `topology.sv`. Never invoke this script.
2. **Clock and Reset Disciplines**:
   - Active-low asynchronous assert, synchronous deassert reset: port name must be `rst_ni` (not active-high `rst`).
   - Internal registers reset asynchronously: `always_ff @(posedge clk or negedge rst_ni)`.
3. **Register `r0` Hardwired Zero**:
   - Must be hardwired to `64'd0`. Any instruction writing to `r0` must produce no state change in `r0`.
4. **Shift Width Truncation**:
   - For 64-bit data, shifts `SHL` and `SHR` must evaluate the lowest 6 bits of the shift amount (`rs2[5:0]`), since shifting a 64-bit integer by $\ge 64$ bits is either 0 or undefined in standard architectures.
5. **Compilation Order in Makefile**:
   - `include/soc_pkg.sv` must always be listed before any file importing `soc_pkg::*`.
   - Compiler invocation must include `-I include` and `-g2012`.

---

## 5. Implementation Roadmap & File Layout

| Step | Milestone | Files to Modify / Create | Description |
|:---:|:---|:---|:---|
| 1 | M1: ISA Package | `include/soc_pkg.sv` | Append opcode enums, instruction struct, register parameters |
| 2 | M2: Primitives | `core/common/alu.sv`<br>`core/common/regfile.sv`<br>`core/common/decoder.sv` | Implement 64-bit ALU, 32x64 RF (r0=0), and 32-bit instruction decoder |
| 3 | M3: Cores | `core/big_core.sv`<br>`core/little_core.sv` | Implement 64-bit datapath, fetch/execute pipeline, memory bus wiring |
| 4 | M4: Verification | `tb/core_tb.sv`<br>`Makefile` | Implement multi-tier verification suite and `make test_cores` target |
| 5 | M5: Cluster Wrap | `subsystems/compute_cluster.sv` | Optional cluster integration wrapper preserving top-level interfaces |

