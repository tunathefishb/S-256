# S-256 Baseline Core Specification Analysis & Feature Inventory

**Author**: Teamwork Specification Miner (`spec_miner_survey`)  
**Date**: 2026-09-06  
**Working Directory**: `/home/tunathefish_b/Code/S-256/.agents/spec_miner_survey`  
**Authoritative Sources**:
- User Requirements Specification: `/home/tunathefish_b/Code/S-256/.agents/ORIGINAL_REQUEST.md` (and root `ORIGINAL_REQUEST.md`)
- SoC Architectural DIRECTIVE: `/home/tunathefish_b/Code/S-256/AGENTS.md`
- Package & Memory Map Definitions: `/home/tunathefish_b/Code/S-256/include/soc_pkg.sv`
- System Architecture Overview: `/home/tunathefish_b/Code/S-256/README.md`
- Toolchain Standard & Simulation Environment: IEEE 1800-2012 SystemVerilog on Icarus Verilog (`iverilog 12.0 (stable)`)

---

## 1. Executive Summary & Specification Scope

The primary objective of the S-256 Baseline Core project is to develop and formally verify two processor cores:
1. **P-Core (`big_core`)**: High-performance baseline core in `core/big_core.sv`, featuring hooks/parameterization for future coprocessor/SIMD acceleration.
2. **E-Core (`little_core`)**: Energy-efficient baseline core in `core/little_core.sv`, providing strict datapath and ISA parity.

Both cores implement an identical, clean, orthogonal 16-instruction 64-bit RISC architecture with:
- **Datapath**: Strict 64-bit data execution and storage width (`XLEN = 64`).
- **Register File**: 32 general-purpose 64-bit registers (`r0` through `r31`), with `r0` unconditionally hardwired to `64'b0`.
- **Instruction Encoding**: Fixed 32-bit compact word format (`ILEN = 32`) partitioned into four orthogonal $2^2$ groups.
- **Execution Primitives**: Common modular building blocks in `core/common/`:
  - `alu.sv`: 64-bit ALU performing modular addition, subtraction, shift left/right, and bitwise logic with condition flags (`Z`, `N`, `C`, `V`).
  - `regfile.sv`: 32x64-bit dual-read, single-write register file with internal forwarding/bypass and hardwired zero.
  - `decoder.sv`: 32-bit instruction decoder generating execution control signals and sign-extended 64-bit immediates.
- **Verification**: Complete automated test suite in `tb/core_tb.sv` integrated via `make test_cores` in `Makefile`.

---

## 2. Orthogonal 16-Instruction ISA Specification

### 2.1 32-bit Instruction Word Layout

Every instruction in the S-256 ISA is encoded as a fixed-length 32-bit word (`inst[31:0]`). All bitfields occupy fixed, uniform bit slices across the entire instruction set:

```text
 31        28 27       23 22       18 17       13 12                         0
+------------+-----------+-----------+-----------+---------------------------------+
|   opcode   |    rd     |    rs1    |    rs2    |              imm13              |
|   (4 bits) |  (5 bits) |  (5 bits) |  (5 bits) |            (13 bits)            |
+------------+-----------+-----------+-----------+---------------------------------+
 [31:30] Grp
 [29:28] Sub-Op
```

- **`opcode` (`inst[31:28]`)**: 4-bit operation code:
  - `inst[31:30]`: 2-bit Instruction Group (`2'b00` Arithmetic, `2'b01` Logic, `2'b10` Memory/Data, `2'b11` Control Flow).
  - `inst[29:28]`: 2-bit Sub-Operation within the group (`2'b00`, `2'b01`, `2'b10`, `2'b11`).
- **`rd` (`inst[27:23]`)**: 5-bit Destination / Target register address ($0 \le rd \le 31$).
- **`rs1` (`inst[22:18]`)**: 5-bit First Source register address ($0 \le rs1 \le 31$) or Base address register.
- **`rs2` (`inst[17:13]`)**: 5-bit Second Source register address ($0 \le rs2 \le 31$) or Store data register.
- **`imm13` (`inst[12:0]`)**: 13-bit Immediate value or branch/jump signed displacement.

### 2.2 Opcode Matrix & Instruction Inventory

The 16 instructions are mapped across the 4 opcode groups as follows:

| Group (`inst[31:30]`) | Sub-Op (`inst[29:28]`) | Full Opcode | Mnemonic | Format Type | Operation Description | Formula |
|:---|:---:|:---:|:---|:---:|:---|:---|
| **`2'b00` (Arithmetic)** | `2'b00` | `4'b0000` (`4'h0`) | **`ADD`** | R-Type | 64-bit Integer Addition | $R[rd] \leftarrow R[rs1] + R[rs2]$ |
| | `2'b01` | `4'b0001` (`4'h1`) | **`SUB`** | R-Type | 64-bit Integer Subtraction | $R[rd] \leftarrow R[rs1] - R[rs2]$ |
| | `2'b10` | `4'b0010` (`4'h2`) | **`SHL`** | R-Type | 64-bit Logical Shift Left | $R[rd] \leftarrow R[rs1] \ll R[rs2][5:0]$ |
| | `2'b11` | `4'b0011` (`4'h3`) | **`SHR`** | R-Type | 64-bit Logical Shift Right | $R[rd] \leftarrow R[rs1] \gg R[rs2][5:0]$ |
| **`2'b01` (Logic)** | `2'b00` | `4'b0100` (`4'h4`) | **`AND`** | R-Type | 64-bit Bitwise AND | $R[rd] \leftarrow R[rs1] \ \& \ R[rs2]$ |
| | `2'b01` | `4'b0101` (`4'h5`) | **`OR`** | R-Type | 64-bit Bitwise OR | $R[rd] \leftarrow R[rs1] \ \| \ R[rs2]$ |
| | `2'b10` | `4'b0110` (`4'h6`) | **`XOR`** | R-Type | 64-bit Bitwise Exclusive-OR | $R[rd] \leftarrow R[rs1] \oplus R[rs2]$ |
| | `2'b11` | `4'b0111` (`4'h7`) | **`NOT`** | R-Type | 64-bit Bitwise Inversion | $R[rd] \leftarrow \sim R[rs1]$ |
| **`2'b10` (Memory/Data)** | `2'b00` | `4'b1000` (`4'h8`) | **`LOAD`** | I-Type | 64-bit Memory Load | $R[rd] \leftarrow \text{Mem}[R[rs1] + \text{SignExt}(imm13)]$ |
| | `2'b01` | `4'b1001` (`4'h9`) | **`STORE`** | S-Type | 64-bit Memory Store | $\text{Mem}[R[rs1] + \text{SignExt}(imm13)] \leftarrow R[rs2]$ |
| | `2'b10` | `4'b1010` (`4'hA`) | **`MOV`** | R-Type | Register-to-Register Move | $R[rd] \leftarrow R[rs1]$ |
| | `2'b11` | `4'b1011` (`4'hB`) | **`LDI`** | I-Type | Load 13-bit Sign-Ext Immediate | $R[rd] \leftarrow \text{SignExt}(imm13)$ |
| **`2'b11` (Control Flow)** | `2'b00` | `4'b1100` (`4'hC`) | **`BEQ`** | B-Type | Branch if Equal | $\text{if } R[rs1] == R[rs2] \implies PC \leftarrow PC + (\text{SignExt}(imm13) \ll 2)$ |
| | `2'b01` | `4'b1101` (`4'hD`) | **`BNE`** | B-Type | Branch if Not Equal | $\text{if } R[rs1] \neq R[rs2] \implies PC \leftarrow PC + (\text{SignExt}(imm13) \ll 2)$ |
| | `2'b10` | `4'b1110` (`4'hE`) | **`CALL`** | J-Type | Subroutine Call with Link | $R[31] \leftarrow PC + 4; \ PC \leftarrow PC + (\text{SignExt}(imm13) \ll 2)$ |
| | `2'b11` | `4'b1111` (`4'hF`) | **`JMP`** | J-Type | Unconditional Jump / Return | $\text{if } rs1 == 0 \implies PC \leftarrow PC + (\text{SignExt}(imm13) \ll 2); \ \text{else } PC \leftarrow R[rs1] + \text{SignExt}(imm13)$ |

---

## 3. Microarchitectural Primitives Specifications

### 3.1 64-Bit Arithmetic Logic Unit (`core/common/alu.sv`)
- **Port Interface**:
  - Inputs: `op_a` (64 bits), `op_b` (64 bits), `alu_op` (4 bits).
  - Outputs: `alu_out` (64 bits), condition flags: `zero` (1 bit), `negative` (1 bit), `carry` (1 bit), `overflow` (1 bit).
- **Flag Equations**:
  - `zero`: `alu_out == 64'd0`
  - `negative`: `alu_out[63]` (sign bit)
  - `carry`: Extended bit 64 from addition/subtraction (`sum_ext[64]` / `sub_ext[64]`).
  - `overflow`: Two's complement signed overflow:
    - ADD: `(op_a[63] == op_b[63]) && (alu_out[63] != op_a[63])`
    - SUB: `(op_a[63] != op_b[63]) && (alu_out[63] != op_a[63])`
- **Shift Mechanics**:
  - Shifts operate on 64-bit values. The shift count is determined by `op_b[5:0]` ($0 \le \text{count} \le 63$).
  - Logical shift right (`SHR`) zeroes vacated high-order bits (`64'b0` shifted into MSB).
- **Passthrough Modes**:
  - `ALU_PASSA`: `alu_out = op_a` (used for `MOV` and base address computation).
  - `ALU_PASSB`: `alu_out = op_b` (used for `LDI` immediate routing).

### 3.2 32-Entry × 64-Bit Register File (`core/common/regfile.sv`)
- **Capacity**: 32 registers (`r0` to `r31`), each 64 bits wide.
- **Port Structure**:
  - **Read Ports**: 2 combinational asynchronous read ports (`raddr1` $\rightarrow$ `rdata1`, `raddr2` $\rightarrow$ `rdata2`).
  - **Write Port**: 1 synchronous write port (`clk`, `rst_ni`, `wen`, `waddr`, `wdata`).
- **Hardwired `r0` Invariant**:
  - `r0` is strictly read as `64'h0000_0000_0000_0000` regardless of clock cycle or written data.
  - Any write attempting to target `r0` (`waddr == 5'd0`) is silently discarded.
- **Internal Forwarding / Write-Through Bypass**:
  - If a write occurs to register $R_x$ in the current cycle (`wen == 1`, `waddr == Rx`, $Rx \neq 0$) and a read port requests $R_x$ in the exact same cycle (`raddr == Rx`), the register file transparently returns `wdata` rather than the old flop state. This eliminates read-during-write pipeline bubbles.
- **Reset Invariant**:
  - Active-low asynchronous assert, synchronous deassert `rst_ni`. Upon reset, all registers `r0`..`r31` are cleared to `64'h0`.

### 3.3 32-Bit Instruction Decoder (`core/common/decoder.sv`)
- **Instruction Field Slicing**:
  - `opcode = inst[31:28]` (`grp = inst[31:30]`, `sub_op = inst[29:28]`)
  - `rd = inst[27:23]`
  - `rs1 = inst[22:18]`
  - `rs2 = inst[17:13]`
  - `imm13 = inst[12:0]`
- **Immediate Generation**:
  - Sign-extended 64-bit immediate:
    $$\text{imm64} = \{\{51\{\text{inst}[12]\}\}, \text{inst}[12:0]\}$$
  - Range of 13-bit signed immediate: $[-4096, +4095]$ (`13'h1000` to `13'h0FFF`).
- **Control Signal Matrix**:

| Instruction | `reg_write` | `alu_src_a` | `alu_src_b` | `alu_op` | `mem_read` | `mem_write` | `wb_sel` | `branch` | `jump` | `call` |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `ADD` | 1 | RS1 | RS2 | `ALU_ADD` | 0 | 0 | WB_ALU | 0 | 0 | 0 |
| `SUB` | 1 | RS1 | RS2 | `ALU_SUB` | 0 | 0 | WB_ALU | 0 | 0 | 0 |
| `SHL` | 1 | RS1 | RS2 | `ALU_SHL` | 0 | 0 | WB_ALU | 0 | 0 | 0 |
| `SHR` | 1 | RS1 | RS2 | `ALU_SHR` | 0 | 0 | WB_ALU | 0 | 0 | 0 |
| `AND` | 1 | RS1 | RS2 | `ALU_AND` | 0 | 0 | WB_ALU | 0 | 0 | 0 |
| `OR`  | 1 | RS1 | RS2 | `ALU_OR`  | 0 | 0 | WB_ALU | 0 | 0 | 0 |
| `XOR` | 1 | RS1 | RS2 | `ALU_XOR` | 0 | 0 | WB_ALU | 0 | 0 | 0 |
| `NOT` | 1 | RS1 | X   | `ALU_NOT` | 0 | 0 | WB_ALU | 0 | 0 | 0 |
| `LOAD`| 1 | RS1 | IMM | `ALU_ADD` | 1 | 0 | WB_MEM | 0 | 0 | 0 |
| `STORE`| 0 | RS1 | IMM | `ALU_ADD` | 0 | 1 | X      | 0 | 0 | 0 |
| `MOV` | 1 | RS1 | X   | `ALU_PASSA`| 0 | 0 | WB_ALU | 0 | 0 | 0 |
| `LDI` | 1 | X   | IMM | `ALU_PASSB`| 0 | 0 | WB_ALU | 0 | 0 | 0 |
| `BEQ` | 0 | RS1 | RS2 | `ALU_SUB` | 0 | 0 | X      | 1 (EQ)| 0 | 0 |
| `BNE` | 0 | RS1 | RS2 | `ALU_SUB` | 0 | 0 | X      | 1 (NE)| 0 | 0 |
| `CALL`| 1 | PC  | IMM | `ALU_ADD` | 0 | 0 | WB_PC4 | 0 | 1 | 1 |
| `JMP` | 0 | RS1/PC| IMM | `ALU_ADD` | 0 | 0 | X      | 0 | 1 | 0 |

---

## 4. Control Flow, Subroutine Linkage, & Memory Semantics

### 4.1 Branch and Jump Address Calculations
1. **Conditional Branches (`BEQ`, `BNE`)**:
   - PC-relative word displacement: $\text{Target} = PC + (\text{SignExt}(imm13) \ll 2)$.
   - Word offset range: $[-4096, +4095]$ instructions, spanning a byte window of $\pm 16\text{ KB}$ ($[-16384, +16380]$ bytes).
   - Condition evaluation:
     - `BEQ`: Branch taken when $R[rs1] == R[rs2]$.
     - `BNE`: Branch taken when $R[rs1] \neq R[rs2]$.
2. **Subroutine Call (`CALL`)**:
   - Link Register: Return address $PC + 4$ (address of next sequential instruction) is written into link register `r31` (or `rd` if specified non-zero).
   - Target Address: $PC + (\text{SignExt}(imm13) \ll 2)$.
3. **Unconditional Jump (`JMP`)**:
   - Dual-mode operation:
     - **PC-Relative Jump**: When $rs1 == 0$, $\text{Target} = PC + (\text{SignExt}(imm13) \ll 2)$.
     - **Register-Indirect Jump**: When $rs1 \neq 0$, $\text{Target} = R[rs1] + \text{SignExt}(imm13)$.
     - *Function Return Idiom*: Subroutine return is synthesized as `JMP r31, 0` ($rs1 = 31, imm13 = 0$), transferring execution back to the caller seamlessly.

### 4.2 Memory Subsystem Interface
- **Address Generation**: Effective Address (EA) is computed by adding the sign-extended 13-bit offset to the base register: $EA = R[rs1] + \text{SignExt}(imm13)$.
- **Data Width**: 64-bit memory word access.
- **Alignment**: 64-bit accesses require 8-byte aligned addresses ($EA[2:0] == 3'b000$).
- **Bus Handshaking**:
  - Instruction Memory: `imem_addr [63:0]`, `imem_rdata [31:0]`, `imem_ren`.
  - Data Memory: `dmem_addr [63:0]`, `dmem_wdata [63:0]`, `dmem_rdata [63:0]`, `dmem_wen`, `dmem_ren`.

---

## 5. SystemVerilog & Toolchain Rules (`iverilog 12.0`)

During empirical probing with `iverilog 12.0`, specific compiler behavioral traits were verified:
1. **Constant Slices in `always_comb`**:
   - Directly indexing sub-ranges (e.g. `sum_ext[63:0]`) inside `always_comb` triggers compiler notices: `sorry: constant selects in always_* processes are not currently supported`.
   - **Remedy for Zero-Warning Build**: Declare intermediate wire assignments outside procedural blocks (e.g., `assign sum_val = sum_ext[63:0];`) or utilize standard `always @*`.
2. **Signed Bitfield Concatenation**:
   - Sign extension syntax `{{51{inst[12]}}, inst[12:0]}` compiles cleanly and synthesizes bit-exact 64-bit two's complement integers.
3. **Package Compilation Order**:
   - `include/soc_pkg.sv` must always be compiled first before any module files, with `-I include` passed to `iverilog`.

---

## Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| 1 | ISA Encoding | 32-bit Uniform Instruction Format | Fixed-length 32-bit instruction word containing opcode, rd, rs1, rs2, and imm13 at fixed bit positions | `inst[31:0]` | Sliced bitfields | None (uniform across all 16 instructions) | ORIGINAL_REQUEST.md R1 |
| 2 | ISA Encoding | 4-bit Opcode Partitioning | Two-level opcode structure: 2-bit group selector (`[31:30]`) and 2-bit operation selector (`[29:28]`) | `inst[31:28]` | Group & Op signals | None (all 16 codes utilized) | ORIGINAL_REQUEST.md R1 |
| 3 | Instruction (Arith) | `ADD` (Opcode `4'b0000`) | 64-bit integer addition of rs1 and rs2 into rd | `R[rs1]`, `R[rs2]` | `R[rd]`, Flags (Z,N,C,V) | Unsigned carry/overflow latched in flags; modular wrap | ORIGINAL_REQUEST.md R1, R2 |
| 4 | Instruction (Arith) | `SUB` (Opcode `4'b0001`) | 64-bit integer subtraction of rs2 from rs1 into rd | `R[rs1]`, `R[rs2]` | `R[rd]`, Flags (Z,N,C,V) | Underflow/borrow and signed overflow latched in flags | ORIGINAL_REQUEST.md R1, R2 |
| 5 | Instruction (Arith) | `SHL` (Opcode `4'b0010`) | 64-bit logical shift left by `rs2[5:0]` bit positions into rd | `R[rs1]`, `R[rs2][5:0]` | `R[rd]`, Flags (Z,N) | Shift count $\ge 64$ masked by 6-bit slice; bits shifted out discarded | ORIGINAL_REQUEST.md R1, R2 |
| 6 | Instruction (Arith) | `SHR` (Opcode `4'b0011`) | 64-bit logical shift right by `rs2[5:0]` bit positions into rd | `R[rs1]`, `R[rs2][5:0]` | `R[rd]`, Flags (Z,N) | Zeroes shifted into MSB; shift count $\ge 64$ masked | ORIGINAL_REQUEST.md R1, R2 |
| 7 | Instruction (Logic) | `AND` (Opcode `4'b0100`) | 64-bit bitwise AND of rs1 and rs2 into rd | `R[rs1]`, `R[rs2]` | `R[rd]`, Flags (Z,N) | None | ORIGINAL_REQUEST.md R1, R2 |
| 8 | Instruction (Logic) | `OR` (Opcode `4'b0101`) | 64-bit bitwise OR of rs1 and rs2 into rd | `R[rs1]`, `R[rs2]` | `R[rd]`, Flags (Z,N) | None | ORIGINAL_REQUEST.md R1, R2 |
| 9 | Instruction (Logic) | `XOR` (Opcode `4'b0110`) | 64-bit bitwise XOR of rs1 and rs2 into rd | `R[rs1]`, `R[rs2]` | `R[rd]`, Flags (Z,N) | None | ORIGINAL_REQUEST.md R1, R2 |
| 10 | Instruction (Logic) | `NOT` (Opcode `4'b0111`) | 64-bit bitwise NOT (unary one's complement) of rs1 into rd | `R[rs1]` | `R[rd]`, Flags (Z,N) | `rs2` and `imm13` fields ignored | ORIGINAL_REQUEST.md R1, R2 |
| 11 | Instruction (Memory) | `LOAD` (Opcode `4'b1000`) | Loads 64-bit word from memory at `R[rs1] + SignExt(imm13)` into rd | `R[rs1]`, `imm13`, `dmem_rdata` | `R[rd]`, `dmem_addr`, `dmem_ren` | Unaligned memory access ignored or lower 3 bits truncated | ORIGINAL_REQUEST.md R1, R2 |
| 12 | Instruction (Memory) | `STORE` (Opcode `4'b1001`) | Stores 64-bit word from rs2 to memory at `R[rs1] + SignExt(imm13)` | `R[rs1]`, `R[rs2]`, `imm13` | `dmem_wdata`, `dmem_addr`, `dmem_wen` | Unaligned memory access ignored or lower 3 bits truncated | ORIGINAL_REQUEST.md R1, R2 |
| 13 | Instruction (Memory) | `MOV` (Opcode `4'b1010`) | Copies 64-bit value from rs1 into rd | `R[rs1]` | `R[rd]` | `rs2` and `imm13` fields ignored | ORIGINAL_REQUEST.md R1, R2 |
| 14 | Instruction (Memory) | `LDI` (Opcode `4'b1011`) | Loads sign-extended 13-bit immediate into rd | `imm13` | `R[rd]` | `rs1` and `rs2` fields ignored | ORIGINAL_REQUEST.md R1, R2 |
| 15 | Instruction (Control) | `BEQ` (Opcode `4'b1100`) | Branches to `PC + (SignExt(imm13) << 2)` if `R[rs1] == R[rs2]` | `R[rs1]`, `R[rs2]`, `imm13`, `PC` | `next_PC` | Fall-through to `PC + 4` if not equal | ORIGINAL_REQUEST.md R1, R2 |
| 16 | Instruction (Control) | `BNE` (Opcode `4'b1101`) | Branches to `PC + (SignExt(imm13) << 2)` if `R[rs1] != R[rs2]` | `R[rs1]`, `R[rs2]`, `imm13`, `PC` | `next_PC` | Fall-through to `PC + 4` if equal | ORIGINAL_REQUEST.md R1, R2 |
| 17 | Instruction (Control) | `CALL` (Opcode `4'b1110`) | Saves return address `PC + 4` into `r31` (or rd) and branches to target | `imm13`, `PC` | `R[31] <= PC + 4`, `next_PC` | Requires caller to save r31 prior to nested call | ORIGINAL_REQUEST.md R1, R2 |
| 18 | Instruction (Control) | `JMP` (Opcode `4'b1111`) | Unconditional jump: PC-relative if `rs1 == 0`; register-indirect if `rs1 != 0` | `rs1`, `imm13`, `PC` | `next_PC` | Does not modify link register | ORIGINAL_REQUEST.md R1, R2 |
| 19 | Execution Primitives | 64-bit ALU (`alu.sv`) | Modular arithmetic, barrel shift, logic, and condition flag generation | `op_a[63:0]`, `op_b[63:0]`, `alu_op` | `alu_out[63:0]`, `Z`, `N`, `C`, `V` | Default to zero on illegal op | ORIGINAL_REQUEST.md R2 |
| 20 | Execution Primitives | ALU Flags (`Z`, `N`, `C`, `V`) | Real-time status flags: Zero, Negative (MSB), Carry-out, Signed Overflow | `op_a`, `op_b`, `alu_out` | Status flags | Correctly separates signed overflow from unsigned carry | ORIGINAL_REQUEST.md R2, R3 |
| 21 | Execution Primitives | 32x64-bit Regfile (`regfile.sv`) | Dual asynchronous read, single synchronous write 64-bit GPR storage | `clk`, `rst_ni`, `raddr1/2`, `waddr`, `wdata`, `wen` | `rdata1[63:0]`, `rdata2[63:0]` | Discards write if `waddr == 5'd0` | ORIGINAL_REQUEST.md R2 |
| 22 | Execution Primitives | Hardwired `r0 == 0` Invariant | Register `r0` is immutable zero; writes ignored, reads return `64'd0` | `waddr = 0`, `raddr = 0` | `rdata = 64'd0` | Write to r0 produces zero state change | ORIGINAL_REQUEST.md R2, R3 |
| 23 | Execution Primitives | Regfile Forwarding / Bypass | Internal read-during-write forwarding delivering new write data in same cycle | `waddr == raddr && wen && waddr != 0` | `rdata = wdata` | Read-after-write hazard avoided inside regfile | ORIGINAL_REQUEST.md R2, R3 |
| 24 | Execution Primitives | Instruction Decoder (`decoder.sv`) | Combinational decoding of 32-bit inst to datapath and memory control lines | `inst[31:0]` | Control lines, `imm64` | Illegal opcode asserts default safe control signals | ORIGINAL_REQUEST.md R2 |
| 25 | Execution Primitives | 13-bit Immediate Sign Extension | Extends 13-bit two's complement immediate to full 64-bit signed integer | `inst[12:0]` | `imm64[63:0]` | Negative bit 12 replicates across high 51 bits | ORIGINAL_REQUEST.md R1, R2 |
| 26 | Core Datapath | Baseline P-Core (`big_core.sv`) | 64-bit processor core implementing baseline RISC ISA with coprocessor hooks | `clk`, `rst_ni`, `imem_*`, `dmem_*` | Memory buses, PC, state | Stalls or flushes pipeline on control flow transfer | ORIGINAL_REQUEST.md R2 |
| 27 | Core Datapath | Baseline E-Core (`little_core.sv`) | 64-bit processor core implementing identical baseline RISC ISA with core parity | `clk`, `rst_ni`, `imem_*`, `dmem_*` | Memory buses, PC, state | 100% ISA and behavioral parity with big_core | ORIGINAL_REQUEST.md R2 |
| 28 | Reset Management | Active-Low Reset Discipline | Strict asynchronous assertion and synchronous deassertion via `rst_ni` | `rst_ni`, `clk` | Reset state | Flops clear to 0; PC resets to boot vector | AGENTS.md, ORIGINAL_REQUEST.md R2 |
| 29 | Memory Bus | Core Memory Interface | Independent instruction fetch and data read/write interfaces | `dmem_rdata`, `imem_rdata` | `imem_addr`, `dmem_addr`, `dmem_wdata`, `wen`, `ren` | Multi-cycle memory handshakes if wait states introduced | ORIGINAL_REQUEST.md R2 |
| 30 | Package Definitions | SoC Package ISA Extension (`soc_pkg.sv`) | Enums for opcodes, ALU operations, instruction struct, and datapath constants | N/A | Global types | Preserves existing CMU definitions | ORIGINAL_REQUEST.md R1 |
| 31 | Verification Suite | Automated Core TB (`core_tb.sv`) | Multi-tier testbench validating both cores on all 16 instructions and edge cases | Core instances | Assertion results, `TEST PASSED` | Triggers `$fatal` on assertion failure | ORIGINAL_REQUEST.md R3 |
| 32 | Verification Suite | Dual-Core Parity Co-Simulation | Co-verifies `big_core` and `little_core` executing identical test suites | Dual core outputs | Match flag | Mismatch between cores halts simulation | ORIGINAL_REQUEST.md R3 |
| 33 | Build Automation | Makefile Target `test_cores` | Clean compilation with `iverilog -g2012 -I include -Wall` and execution via `vvp` | Source and TB files | Simulation binary `build/core_tb.vvp` | Fails make target if compilation fails | ORIGINAL_REQUEST.md R3, Makefile |

---

## Edge Cases

| # | Feature | Input | Observed Behavior |
|---|---------|-------|-------------------|
| 1 | `ADD` Signed Overflow | `op_a = 64'h7FFF_FFFF_FFFF_FFFF`, `op_b = 64'd1` | `alu_out = 64'h8000_0000_0000_0000`, `zero=0`, `negative=1`, `carry=0`, `overflow=1` |
| 2 | `ADD` Unsigned Carry-Out | `op_a = 64'hFFFF_FFFF_FFFF_FFFF`, `op_b = 64'd1` | `alu_out = 64'h0000_0000_0000_0000`, `zero=1`, `negative=0`, `carry=1`, `overflow=0` |
| 3 | `ADD` Zero Result | `op_a = 64'd0`, `op_b = 64'd0` | `alu_out = 64'd0`, `zero=1`, `negative=0`, `carry=0`, `overflow=0` |
| 4 | `SUB` Negative Signed Overflow | `op_a = 64'h8000_0000_0000_0000`, `op_b = 64'd1` | `alu_out = 64'h7FFF_FFFF_FFFF_FFFF`, `zero=0`, `negative=0`, `carry=0`, `overflow=1` |
| 5 | `SUB` Unsigned Borrow | `op_a = 64'd0`, `op_b = 64'd1` | `alu_out = 64'hFFFF_FFFF_FFFF_FFFF`, `zero=0`, `negative=1`, `carry=1`, `overflow=0` |
| 6 | `SUB` Self-Cancellation | `op_a = 64'hDEAD_BEEF_CAFE_BABE`, `op_b = 64'hDEAD_BEEF_CAFE_BABE` | `alu_out = 64'd0`, `zero=1`, `negative=0`, `carry=0`, `overflow=0` |
| 7 | `SHL` Shift by Zero | `op_a = 64'hA5A5_A5A5_A5A5_A5A5`, `op_b = 64'd0` | `alu_out = 64'hA5A5_A5A5_A5A5_A5A5` (unchanged), `zero=0`, `negative=1` |
| 8 | `SHL` Shift Maximum (63 bits) | `op_a = 64'd1`, `op_b = 64'd63` | `alu_out = 64'h8000_0000_0000_0000`, `zero=0`, `negative=1` |
| 9 | `SHL` Shift Count $\ge 64$ | `op_a = 64'd1`, `op_b = 64'd64` (or `64'd128`) | Shift count masked by `op_b[5:0] == 6'd0` yields `alu_out = 64'd1` |
| 10 | `SHR` Shift Maximum (63 bits) | `op_a = 64'h8000_0000_0000_0000`, `op_b = 64'd63` | `alu_out = 64'h0000_0000_0000_0001`, `zero=0`, `negative=0` (logical zero-fill) |
| 11 | `AND` All-Ones Identity | `op_a = 64'h1234_5678_9ABC_DEF0`, `op_b = 64'hFFFF_FFFF_FFFF_FFFF` | `alu_out = 64'h1234_5678_9ABC_DEF0` (identity preserved) |
| 12 | `AND` Masking to Zero | `op_a = 64'h1234_5678_9ABC_DEF0`, `op_b = 64'd0` | `alu_out = 64'd0`, `zero=1`, `negative=0` |
| 13 | `OR` Self Inverse | `op_a = 64'h0123_4567_89AB_CDEF`, `op_b = ~64'h0123_4567_89AB_CDEF` | `alu_out = 64'hFFFF_FFFF_FFFF_FFFF`, `zero=0`, `negative=1` |
| 14 | `XOR` Self-Annihilation | `op_a = 64'hFEDC_BA98_7654_3210`, `op_b = 64'hFEDC_BA98_7654_3210` | `alu_out = 64'd0`, `zero=1`, `negative=0` |
| 15 | `NOT` of Zero | `op_a = 64'd0` | `alu_out = 64'hFFFF_FFFF_FFFF_FFFF`, `zero=0`, `negative=1` |
| 16 | `NOT` of All-Ones | `op_a = 64'hFFFF_FFFF_FFFF_FFFF` | `alu_out = 64'd0`, `zero=1`, `negative=0` |
| 17 | `r0` Hardwired Zero Persistence | Write `64'hDEAD_BEEF_CAFE_BABE` to `waddr = 5'd0` with `wen = 1` | `regs[0]` remains `64'd0`; subsequent reads return `64'd0` |
| 18 | `r0` Simultaneous Read/Write | `waddr = 5'd0, wdata = 64'hFFFF, wen = 1, raddr1 = 5'd0` | `rdata1` evaluates strictly to `64'd0` via invariant bypass check |
| 19 | Regfile Internal Bypass (RAW) | `waddr = 5'd5, wdata = 64'h1122_3344_5566_7788, wen = 1, raddr1 = 5'd5` | `rdata1` immediately returns `64'h1122_3344_5566_7788` in the same clock cycle |
| 20 | Immediate Sign-Ext Max Positive | `imm13 = 13'h0FFF` (+4095) | Sign-extended to `64'h0000_0000_0000_0FFF` (bit 12 is 0) |
| 21 | Immediate Sign-Ext Zero | `imm13 = 13'h0000` (0) | Sign-extended to `64'h0000_0000_0000_0000` |
| 22 | Immediate Sign-Ext Min Negative | `imm13 = 13'h1000` (-4096) | Sign-extended to `64'hFFFF_FFFF_FFFF_F000` (bit 12 is 1) |
| 23 | Immediate Sign-Ext Minus One | `imm13 = 13'h1FFF` (-1) | Sign-extended to `64'hFFFF_FFFF_FFFF_FFFF` |
| 24 | `LOAD` with Negative Offset | `R[rs1] = 64'h0000_1000`, `imm13 = 13'h1FF8` (-8) | `dmem_addr = 64'h0000_0FF8`, `dmem_ren = 1`, `R[rd]` updated with loaded data |
| 25 | `LOAD` with `r0` Base (Absolute) | `rs1 = 5'd0` (reads `64'd0`), `imm13 = 13'h0100` (+256) | `dmem_addr = 64'h0000_0100`, direct absolute addressing |
| 26 | `STORE` followed by `LOAD` (RAW) | `STORE r2, 0(r1)` followed by `LOAD r3, 0(r1)` | Data written from `r2` into memory address `0(r1)` correctly fetched into `r3` |
| 27 | `BEQ` Taken | `R[rs1] = 64'd42`, `R[rs2] = 64'd42`, `imm13 = 13'd4` | Branch condition satisfied; `PC <= PC + (4 << 2) = PC + 16` |
| 28 | `BEQ` Not Taken (Fall-through) | `R[rs1] = 64'd42`, `R[rs2] = 64'd99`, `imm13 = 13'd4` | Branch condition fails; `PC <= PC + 4` |
| 29 | `BNE` Taken | `R[rs1] = 64'd1`, `R[rs2] = 64'd2`, `imm13 = 13'd8` | Branch condition satisfied; `PC <= PC + 32` |
| 30 | Backward Loop Branch | `imm13 = -13'd3` (`13'h1FFD`) in loop body | `PC <= PC + (-3 << 2) = PC - 12`, jumping back 3 instructions |
| 31 | `CALL` Link Register Update | `PC = 64'h0000_0020`, `imm13 = 13'd10` | `R[31] <= 64'h0000_0024`, `PC <= 64'h0000_0020 + 40 = 64'h0000_0048` |
| 32 | `JMP` Function Return (`ret`) | `rs1 = 5'd31`, `R[31] = 64'h0000_0024`, `imm13 = 13'd0` | `PC <= R[31] + 0 = 64'h0000_0024`, returning execution cleanly to caller |
| 33 | Reset Assertion (`rst_ni = 0`) | Assert `rst_ni = 0` during active core execution | PC resets to reset vector (`64'd0`); all 32 GPRs clear to 0; memory strobes deassert |
| 34 | Icarus Verilog Procedural Selects | Slicing bits inside `always_comb` (e.g. `sum[63:0]`) | Compiler notice generated unless assigned via external continuous net or `always @*` |

---

## 6. Verification & Test Requirements

To satisfy user acceptance criteria R3, the automated testbench (`tb/core_tb.sv`) and build environment must verify:
1. **Instruction Unit Coverage (16/16)**:
   - Every individual instruction (`ADD`, `SUB`, `SHL`, `SHR`, `AND`, `OR`, `XOR`, `NOT`, `LOAD`, `STORE`, `MOV`, `LDI`, `BEQ`, `BNE`, `CALL`, `JMP`) must execute under positive and negative data conditions with bit-exact validation of register writeback.
2. **Microarchitecture Hardening**:
   - Register `r0` write-rejection and constant zero persistence checked under concurrent write cycles.
   - Read-After-Write (RAW) data hazard tests verifying forwarding between back-to-back instructions.
   - 64-bit integer sign, overflow, carry, and modular wrap boundary conditions.
3. **Control Flow & Program Execution**:
   - Backward loops computing iterative calculations (e.g., Fibonacci or factorial accumulation).
   - Forward branches skipping conditional execution blocks.
   - Multi-level subroutine calls (`CALL` and `JMP r31, 0`) demonstrating proper return address preservation.
4. **Dual Core Parity**:
   - Both `big_core` and `little_core` must be co-instantiated in `tb/core_tb.sv` and execute the full testsuite in lockstep or parallel test instances with zero behavioral discrepancies.
5. **Makefile Integration**:
   - Target `test_cores` must compile under `iverilog -g2012 -I include -Wall -Wno-timescale` with 0 warnings and 0 errors, execute with `vvp`, and terminate with string `TEST PASSED`.
