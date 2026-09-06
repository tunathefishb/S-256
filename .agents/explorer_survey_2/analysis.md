# S-256 Baseline Core Microarchitecture & Datapath Architecture Survey

**Author**: Teamwork Explorer (Datapath & Architecture Explorer 2)  
**Date**: 2026-09-06  
**Working Directory**: `/home/tunathefish_b/Code/S-256/.agents/explorer_survey_2`  
**Reference Documents**: `ORIGINAL_REQUEST.md`, `AGENTS.md`, `PROJECT.md`, `include/soc_pkg.sv`, `explorer_survey_1/analysis.md`  

---

## 1. Executive Architectural Blueprint & Mission Overview

The objective of the S-256 baseline core development project is to design and implement the baseline P-core (`big_core`) and E-core (`little_core`) in synthesizable SystemVerilog (IEEE 1800-2012). Both cores share an identical 64-bit execution engine and ISA, providing the foundation for future P-core SIMD/coprocessor extensions.

The architecture comprises:
1. **64-bit Datapath**: Pure 64-bit computational width across registers, ALU, effective memory addresses, and data buses.
2. **32 General-Purpose Registers (GPRs)**: 64-bit wide registers `r0` through `r31`, with `r0` hardwired to `64'd0`.
3. **16-Instruction Orthogonal RISC ISA**: Compact 32-bit fixed-width instruction words partitioned into four $2^2$ groups: Arithmetic (`ADD`, `SUB`, `SHL`, `SHR`), Logic (`AND`, `OR`, `XOR`, `NOT`), Memory/Data (`LOAD`, `STORE`, `MOV`, `LDI`), and Control Flow (`BEQ`, `BNE`, `CALL`, `JMP`).
4. **Reusable Common Primitives** in `core/common/`:
   - `alu.sv`: 64-bit arithmetic, logic, shift, status flags (`Z`, `N`, `C`, `V`).
   - `regfile.sv`: 32x64-bit 2R1W register file with hardwired `r0=0` and internal write-through forwarding.
   - `decoder.sv`: 32-bit single-cycle decoder producing unified control signals and sign/zero-extended 64-bit immediates.
5. **Toolchain & Verification Rigor**: Fully verified under Icarus Verilog (`iverilog 12.0 -g2012`) with active-low reset `rst_ni`, zero compiler warnings, and deterministic E2E self-checking testbench execution.

---

## 2. ISA Encoding, Field Bit Slices & Opcode Matrix

### 2.1 Unified 32-Bit Instruction Word Encoding
Every instruction in the S-256 baseline ISA is encoded in a fixed 32-bit word (`inst[31:0]`). The field partition cleanly allocates all 32 bits without overlapping or ambiguous bit alignments:

```text
 31      30 29      28 27       23 22       18 17       13 12                         0
+----------+----------+-----------+-----------+-----------+-------------------------------+
| group[1] |  op[1:0] |  rd[4:0]  |  rs1[4:0] |  rs2[4:0] |           imm13[12:0]         |
+----------+----------+-----------+-----------+-----------+-------------------------------+
  2 bits     2 bits      5 bits      5 bits      5 bits               13 bits
|<--- opcode[3:0] --->|
```

| Field Name | Bit Slices | Width | Role and Semantics |
|:---|:---:|:---:|:---|
| `group` | `inst[31:30]` | 2 | Primary functional partition (`00`: Arith, `01`: Logic, `10`: Mem/Data, `11`: Ctrl) |
| `op` | `inst[29:28]` | 2 | Sub-operation within group |
| `opcode` | `inst[31:28]` | 4 | Combined 4-bit instruction opcode `{group, op}` |
| `rd` | `inst[27:23]` | 5 | Destination register address (`r0`..`r31`). Unused in `STORE`, `BEQ`, `BNE` |
| `rs1` | `inst[22:18]` | 5 | First source register address (`r0`..`r31`). Base register for `LOAD`/`STORE`, indirect jump register for `JMP`/`RET` |
| `rs2` | `inst[17:13]` | 5 | Second source register address (`r0`..`r31`). Data source for `STORE`, comparison operand for `BEQ`/`BNE` |
| `imm13` | `inst[12:0]` | 13 | 13-bit signed/unsigned immediate or branch/jump offset |

### 2.2 Complete 16-Instruction Architectural Matrix

| Opcode | Mnemonic | Group Name | Semantics / Register Transfer | Condition / Flags | Immediate Usage |
|:---:|:---:|:---:|:---|:---:|:---:|
| `4'b0000` | **ADD** | Arithmetic | `R[rd] <= R[rs1] + R[rs2]` | Updates Z, N, C, V | Unused (`0`) |
| `4'b0001` | **SUB** | Arithmetic | `R[rd] <= R[rs1] - R[rs2]` | Updates Z, N, C, V | Unused (`0`) |
| `4'b0010` | **SHL** | Arithmetic | `R[rd] <= R[rs1] << R[rs2][5:0]` | Updates Z, N | Unused (`0`) |
| `4'b0011` | **SHR** | Arithmetic | `R[rd] <= R[rs1] >> R[rs2][5:0]` | Updates Z, N | Unused (`0`) |
| `4'b0100` | **AND** | Logic | `R[rd] <= R[rs1] & R[rs2]` | Updates Z, N | Unused (`0`) |
| `4'b0101` | **OR**  | Logic | `R[rd] <= R[rs1] \| R[rs2]` | Updates Z, N | Unused (`0`) |
| `4'b0110` | **XOR** | Logic | `R[rd] <= R[rs1] ^ R[rs2]` | Updates Z, N | Unused (`0`) |
| `4'b0111` | **NOT** | Logic | `R[rd] <= ~R[rs1]` | Updates Z, N | Unused (`0`) |
| `4'b1000` | **LOAD**| Memory | `R[rd] <= Mem[R[rs1] + sext(imm13)]` | None | Address Offset (`sext`) |
| `4'b1001` | **STORE**| Memory | `Mem[R[rs1] + sext(imm13)] <= R[rs2]`| None | Address Offset (`sext`) |
| `4'b1010` | **MOV** | Data | `R[rd] <= R[rs1]` | None | Unused (`0`) |
| `4'b1011` | **LDI** | Data | `R[rd] <= sext(imm13)` | Updates Z, N | Loaded Data (`sext`) |
| `4'b1100` | **BEQ** | Control | `if (R[rs1] == R[rs2]) PC <= PC + (sext(imm13) << 2)` | Tests Z | Branch Target Offset |
| `4'b1101` | **BNE** | Control | `if (R[rs1] != R[rs2]) PC <= PC + (sext(imm13) << 2)` | Tests ~Z | Branch Target Offset |
| `4'b1110` | **CALL**| Control | `R[31] <= PC + 4; PC <= PC + (sext(imm13) << 2)` | None | Call Target Offset |
| `4'b1111` | **JMP** | Control | `PC <= (rs1 != 0) ? R[rs1] : (PC + (sext(imm13) << 2))` | None | Jump Target Offset / Register Target |

---

## 3. 64-Bit Datapath Architecture & ALU Design

### 3.1 Arithmetic Operations (ADD, SUB, SHL, SHR)
All datapath arithmetic operates on 64-bit two's-complement values:
1. **ADD (`4'b0000`)**:
   - $Result = A + B$
   - 65-bit full-adder internal equation:
     $$\{cout, result\} = \{1'b0, A\} + \{1'b0, B\}$$
   - Carry flag: $C = cout$
   - Overflow flag: $V = (\sim(A[63] \oplus B[63])) \ \& \ (A[63] \oplus Result[63])$
2. **SUB (`4'b0001`)**:
   - $Result = A - B = A + (\sim B) + 1$
   - 65-bit full-subtractor internal equation:
     $$\{cout, result\} = \{1'b0, A\} - \{1'b0, B\}$$
   - Borrow flag: $C = (A < B)$
   - Overflow flag: $V = (A[63] \oplus B[63]) \ \& \ (A[63] \oplus Result[63])$
3. **SHL (`4'b0010`)**:
   - $Result = A \ll B[5:0]$
   - 64-bit logical left shift.
   - Shift amount is strictly masked to 6 bits ($B[5:0]$, covering $0$ to $63$ bit shifts). Masking prevents out-of-range simulation anomalies and guarantees standard 64-bit RISC hardware behavior.
4. **SHR (`4'b0011`)**:
   - $Result = A \gg B[5:0]$
   - 64-bit logical right shift (zero-filling from MSB).
   - Shift amount is strictly masked to $B[5:0]$.

### 3.2 Logic Operations (AND, OR, XOR, NOT)
1. **AND (`4'b0100`)**: Bitwise AND: $Result = A \ \& \ B$
2. **OR (`4'b0101`)**: Bitwise OR: $Result = A \ | \ B$
3. **XOR (`4'b0110`)**: Bitwise XOR: $Result = A \ \oplus \ B$
4. **NOT (`4'b0111`)**: Bitwise bit inversion: $Result = \sim A$. In accordance with unary semantics, operand $B$ is ignored.

### 3.3 Status Flags & Generation Logic
The ALU outputs a dedicated packed flags struct:
```systemverilog
typedef struct packed {
    logic z; // Zero: asserted when 64-bit result == 64'd0
    logic n; // Negative: asserted when result[63] == 1'b1
    logic c; // Carry / Borrow: unsigned carry out or borrow
    logic v; // Overflow: signed two's complement overflow
} alu_flags_t;
```

Exact combinational equations:
```systemverilog
assign flags.z = (result == 64'd0);
assign flags.n = result[63];

always_comb begin
    flags.c = 1'b0;
    flags.v = 1'b0;
    case (alu_op)
        ALU_ADD: begin
            flags.c = add_sub_cout;
            flags.v = (~(a[63] ^ b[63])) & (a[63] ^ result[63]);
        end
        ALU_SUB: begin
            flags.c = (a < b); // borrow
            flags.v = (a[63] ^ b[63]) & (a[63] ^ result[63]);
        end
        default: begin
            flags.c = 1'b0;
            flags.v = 1'b0;
        end
    endcase
end
```

### 3.4 Zero vs Sign Extension (13-Bit Immediate to 64-Bit)
Because instructions have a 13-bit immediate field `inst[12:0]`, the datapath requires deterministic sign and zero extension:
- **Sign Extension (`imm64_sext`)**:
  ```systemverilog
  assign imm64_sext = {{51{inst[12]}}, inst[12:0]};
  ```
  - Used by: `LOAD`, `STORE`, `LDI`, `BEQ`, `BNE`, `CALL`, `JMP`.
  - Maps `13'h0000` $\rightarrow$ `64'h0000_0000_0000_0000` ($0$).
  - Maps `13'h07FF` $\rightarrow$ `64'h0000_0000_0000_07FF` ($+2047$).
  - Maps `13'h1FFF` $\rightarrow$ `64'hFFFF_FFFF_FFFF_FFFF` ($-1$).
  - Maps `13'h1000` $\rightarrow$ `64'hFFFF_FFFF_FFFF_F000` ($-4096$).
- **Zero Extension (`imm64_zext`)**:
  ```systemverilog
  assign imm64_zext = {51'd0, inst[12:0]};
  ```
  - Used for bitmask generation and unsigned immediate constants.

---

## 4. 32x64-Bit Register File Microarchitecture

### 4.1 Port Specifications & `r0` Hardwiring Invariant
The register file (`core/common/regfile.sv`) consists of 32 64-bit registers (`r0` through `r31`):
- **Ports**:
  - Read Port 1: Input `raddr1[4:0]`, Output `rdata1[63:0]` (combinational read).
  - Read Port 2: Input `raddr2[4:0]`, Output `rdata2[63:0]` (combinational read).
  - Write Port: Input `waddr[4:0]`, Input `wdata[63:0]`, Input `wen` (synchronous write on `posedge clk`).
  - System: Input `clk`, Input `rst_ni` (active-low asynchronous assert reset).

- **The `r0 == 0` Invariant**:
  In RISC architectures, `r0` is a constant source of zero and a discard target for unused outputs. The invariant is enforced at two distinct levels:
  1. **Write Suppression**: When `waddr == 5'd0`, write enable is gated off:
     ```systemverilog
     if (wen && (waddr != 5'd0)) begin
         rf_mem[waddr] <= wdata;
     end
     ```
  2. **Read Clamping**: When reading address 0, the output multiplexer unconditionally forces `64'd0`:
     ```systemverilog
     assign rdata1_raw = (raddr1 == 5'd0) ? 64'd0 : rf_mem[raddr1];
     assign rdata2_raw = (raddr2 == 5'd0) ? 64'd0 : rf_mem[raddr2];
     ```
  This dual-layer clamp ensures `r0` can never contain non-zero data under any sequence of operations.

### 4.2 Internal Write-Through Forwarding (Read-During-Write Bypass)
When an instruction writes to register $R_x$ in cycle $t$, and another instruction reads register $R_x$ in the same cycle:
Without write-through forwarding, standard behavioral memory array reads return the stale (pre-write) value.
By adding internal forwarding directly inside `regfile.sv`:
```systemverilog
assign rdata1 = (raddr1 == 5'd0) ? 64'd0 :
                ((wen && (waddr == raddr1)) ? wdata : rf_mem[raddr1]);

assign rdata2 = (raddr2 == 5'd0) ? 64'd0 :
                ((wen && (waddr == raddr2)) ? wdata : rf_mem[raddr2]);
```
This transparent write-first behavior eliminates structural hazards and resolves RAW dependencies within the register file cell itself.

### 4.3 Pipeline RAW Hazard Handling & Forwarding Considerations
In an implementation utilizing pipelining (e.g. 3-stage or 5-stage):
1. **EX-to-EX Forwarding**: When instruction in EX needs result of previous instruction currently in MEM/WB:
   ```systemverilog
   forward_a = (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == id_ex_rs1));
   forward_b = (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == id_ex_rs2));
   ```
2. **Load-Use Hazard**: When a `LOAD` is immediately followed by an ALU instruction consuming loaded data:
   The loaded data is only available after the MEM stage. A 1-cycle stall bubble must be inserted in IF/ID:
   ```systemverilog
   stall = id_ex_mem_read && ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));
   ```
3. **Single-Cycle / Multi-Cycle Execution**:
   In a single-cycle execution model (detailed in Section 8), every instruction executes to completion in exactly one clock cycle ($CPI = 1.0$). Therefore, RAW pipeline hazards across stages do not exist because writeback completes on the same clock edge that latches the next instruction. Internal RF forwarding guarantees back-to-back register consistency.

---

## 5. 32-Bit Instruction Decoder & Control Signals

### 5.1 Field Extraction & Immediate Decoding
The decoder module (`core/common/decoder.sv`) takes the 32-bit instruction word `inst[31:0]` and combinatorially derives all datapath control signals.

To prevent Icarus Verilog `sorry: constant selects in always_*` warnings (see Section 9), all instruction fields are extracted into dedicated continuous wires:
```systemverilog
wire [1:0]  inst_group = inst[31:30];
wire [1:0]  inst_op    = inst[29:28];
wire [3:0]  opcode     = inst[31:28];
wire [4:0]  rd         = inst[27:23];
wire [4:0]  rs1        = inst[22:18];
wire [4:0]  rs2        = inst[17:13];
wire [12:0] imm13      = inst[12:0];
```

### 5.2 Control Signal Truth Table
The decoder produces the following control signals:

| Opcode | Mnemonic | `reg_write` | `mem_read` | `mem_write` | `alu_src_b` | `alu_op` | `wb_sel` | `is_branch` | `is_call` | `is_jmp` |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `4'b0000` | ADD | 1 | 0 | 0 | `SRC_B_REG` | `ALU_ADD` | `WB_ALU`  | 0 | 0 | 0 |
| `4'b0001` | SUB | 1 | 0 | 0 | `SRC_B_REG` | `ALU_SUB` | `WB_ALU`  | 0 | 0 | 0 |
| `4'b0010` | SHL | 1 | 0 | 0 | `SRC_B_REG` | `ALU_SHL` | `WB_ALU`  | 0 | 0 | 0 |
| `4'b0011` | SHR | 1 | 0 | 0 | `SRC_B_REG` | `ALU_SHR` | `WB_ALU`  | 0 | 0 | 0 |
| `4'b0100` | AND | 1 | 0 | 0 | `SRC_B_REG` | `ALU_AND` | `WB_ALU`  | 0 | 0 | 0 |
| `4'b0101` | OR  | 1 | 0 | 0 | `SRC_B_REG` | `ALU_OR`  | `WB_ALU`  | 0 | 0 | 0 |
| `4'b0110` | XOR | 1 | 0 | 0 | `SRC_B_REG` | `ALU_XOR` | `WB_ALU`  | 0 | 0 | 0 |
| `4'b0111` | NOT | 1 | 0 | 0 | `SRC_B_REG` | `ALU_NOT` | `WB_ALU`  | 0 | 0 | 0 |
| `4'b1000` | LOAD| 1 | 1 | 0 | `SRC_B_IMM` | `ALU_ADD` | `WB_MEM`  | 0 | 0 | 0 |
| `4'b1001` | STORE| 0 | 0 | 1 | `SRC_B_IMM` | `ALU_ADD` | `WB_NONE` | 0 | 0 | 0 |
| `4'b1010` | MOV | 1 | 0 | 0 | `SRC_B_REG` | `ALU_PASS_A`| `WB_ALU`| 0 | 0 | 0 |
| `4'b1011` | LDI | 1 | 0 | 0 | `SRC_B_IMM` | `ALU_PASS_B`| `WB_ALU`| 0 | 0 | 0 |
| `4'b1100` | BEQ | 0 | 0 | 0 | `SRC_B_REG` | `ALU_SUB` | `WB_NONE` | 1 | 0 | 0 |
| `4'b1101` | BNE | 0 | 0 | 0 | `SRC_B_REG` | `ALU_SUB` | `WB_NONE` | 1 | 0 | 0 |
| `4'b1110` | CALL| 1 | 0 | 0 | `SRC_B_REG` | `ALU_ADD` | `WB_LINK` | 0 | 1 | 0 |
| `4'b1111` | JMP | 0 | 0 | 0 | `SRC_B_REG` | `ALU_ADD` | `WB_NONE` | 0 | 0 | 1 |

*Note on `CALL` Writeback: `CALL` asserts `reg_write = 1` and directs the writeback multiplexer `wb_sel = WB_LINK` (`PC + 4`) to destination register `rd` (or architectural link register `r31`).*

---

## 6. Control Flow Architecture (BEQ, BNE, CALL, JMP)

### 6.1 Conditional Branch Resolution (BEQ, BNE)
Conditional branches evaluate register equality:
- **`BEQ` (`4'b1100`)**: Branch condition taken when $R[rs1] == R[rs2]$.
- **`BNE` (`4'b1101`)**: Branch condition taken when $R[rs1] \neq R[rs2]$.
- In terms of ALU status:
  - Performing $R[rs1] - R[rs2]$ yields $Z = 1$ when operands are equal, and $Z = 0$ when not equal.
  - `branch_taken = (is_beq & flags.z) | (is_bne & ~flags.z);`

### 6.2 Branch Target Computation: Instruction Offset vs Byte Offset
In a 32-bit fixed-length instruction architecture, all instructions are 4 bytes wide and naturally aligned to 4-byte boundaries (`PC[1:0] == 2'b00`).

Target computation equation:
$$\text{Target} = \text{PC} + (\text{sign\_ext}(imm13) \ll 2)$$

- **Why Shift by 2?**:
  - Shifting the 13-bit signed immediate by 2 multiplies the offset by 4 bytes.
  - This expands the branch reach by $4\times$: from $\pm 4096$ bytes to $\pm 16,384$ bytes ($\pm 16$ KB, or $\pm 4096$ instructions).
  - It maintains strict 4-byte instruction alignment automatically (`Target[1:0] == 2'b00`).
- If an implementation chooses byte offsets without shift:
  $$\text{Target} = \text{PC} + \text{sign\_ext}(imm13)$$
  Both equations are mathematically consistent; shifting by 2 is the standard RISC recommendation (as established in MIPS and RISC-V). The testbench can support either by standard convention, with `PC + (imm << 2)` strongly recommended.

### 6.3 Subroutine Link Convention (`CALL`) & Link Register
Subroutine execution requires saving the return address and branching to the callee:
1. **Return Address**: The return address is the address of the instruction immediately following the `CALL`, which is $\text{PC} + 4$.
2. **Link Register Destination**:
   - The S-256 ISA convention allocates register `r31` as the designated Link Register (equivalent to `$ra` in MIPS or `lr` in ARM).
   - Furthermore, because the instruction word contains a 5-bit `rd` field (`inst[27:23]`), the core decoder can support:
     ```systemverilog
     assign link_reg_addr = (rd != 5'd0) ? rd : 5'd31;
     ```
     This allows standard calls to link to `r31` by default, while giving compilers the option of specifying an alternate link register in `rd`.
3. **Call Target**:
   $$\text{Call Target} = \text{PC} + (\text{sign\_ext}(imm13) \ll 2)$$

### 6.4 Unconditional Jump (`JMP`) & Unified Subroutine Return (`RET` via `rs1`)
Subroutine return is historically a point of friction if an ISA only provides PC-relative immediate jumps.
In our orthogonal 16-instruction ISA:
- `JMP` has `opcode = 4'b1111`, `rs1 = inst[22:18]`, and `imm13 = inst[12:0]`.
- By defining target address resolution as:
  $$\text{Jump Target} = (rs1 \neq 5'd0) \ ? \ (R[rs1] + \text{sign\_ext}(imm13)) \ : \ (\text{PC} + (\text{sign\_ext}(imm13) \ll 2))$$

**Why This Is a Breakthrough Architectural Decision**:
1. **Relative Jump**: When `rs1 == 5'd0` (`r0`, hardwired to 0), `JMP` performs a PC-relative branch:
   $$\text{Target} = \text{PC} + (\text{sign\_ext}(imm13) \ll 2)$$
2. **Subroutine Return (`RET`)**: When returning from a function, the return address is held in `r31`. By issuing `JMP r31, 0` (`rs1 = 31, imm = 0`), the target evaluates to:
   $$\text{Target} = R[31] + 0 = R[31]$$
   This executes a register-indirect jump back to the caller!
3. **Indirect Computed Jump**: When jumping through function pointers or switch tables, `JMP rs1, offset` evaluates to $R[rs1] + offset$.
This unified formulation provides complete control flow versatility (PC-relative jumps, register returns, and computed jumps) within a single 4-bit opcode `JMP`.

---

## 7. Memory Operations & Subsystem Interfacing

### 7.1 Address Generation & Doubleword Alignment
The S-256 datapath is 64-bit wide. Memory access operations are:
- **`LOAD rd, imm13(rs1)` (`4'b1000`)**:
  $$\text{Effective Address} = R[rs1] + \text{sign\_ext}(imm13)$$
  Loads a 64-bit doubleword from memory into `rd`.
- **`STORE rs2, imm13(rs1)` (`4'b1001`)**:
  $$\text{Effective Address} = R[rs1] + \text{sign\_ext}(imm13)$$
  Stores the 64-bit doubleword from `rs2` into memory.

For 64-bit aligned doublewords:
- Address lower bits must satisfy: `addr[2:0] == 3'b000` (8-byte alignment).

### 7.2 Byte Enables & Data Strobes (`wstrb[7:0]`)
To support byte/word granularities and align with standard memory controllers (e.g. DDR, eDRAM, L1 cache):
- The core outputs an 8-bit write strobe `dmem_wstrb[7:0]`.
- For full 64-bit doubleword stores:
  `assign dmem_wstrb = 8'hFF;`
- For partial stores (if extended in future): `wstrb` specifies active byte lanes.

### 7.3 Memory Bus Interface Contract
To avoid structural hazards between instruction fetching and data load/stores, and to enable single-cycle execution in simulation, both `big_core` and `little_core` use a Harvard bus architecture:

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
    output logic [7:0]  dmem_wstrb,
    output logic        dmem_wen,
    output logic        dmem_ren,
    input  logic [63:0] dmem_rdata,

    // Observability & Debug Outputs
    output logic [63:0] pc,
    output logic        halted
);
```

---

## 8. Microarchitecture & Pipeline Design Strategy

### 8.1 Single-Cycle vs Multi-Cycle vs Pipelined Core Trade-Offs

| Evaluation Metric | Single-Cycle Core | Classic Multi-Cycle (FSM) | 3-Stage / 5-Stage Pipelined Core |
|:---|:---|:---|:---|
| **Cycles Per Instruction (CPI)** | **1.0** (Deterministic) | 3.0 – 5.0 (Variable) | ~1.0 – 1.4 (Stalls & Flushes) |
| **Pipeline Hazards** | **None** | **None** | RAW hazards, load-use stalls, branch flush |
| **Verification Complexity** | Minimal, predictable state | Medium (FSM corner states) | High (hazard & forwarding coverage) |
| **Simulation Speed in `vvp`** | **Fastest** (1 cycle per inst) | Slower ($3\times$ to $5\times$ cycles) | Fast |
| **SystemVerilog Complexity** | Clean, modular, robust | FSM state machine overhead | Forwarding muxes, stall & flush controllers |
| **Future Extensibility** | Direct coprocessor hookup | Multi-cycle stall hookup | Decoupled coprocessor queues |

### 8.2 Recommended Core Baseline Architecture: Single-Cycle Execution Engine
For the S-256 baseline core implementation:
1. **Deterministic Single-Cycle Execution**:
   - PC register updates on every clock edge:
     $$\text{PC}_{next} = \text{branch\_taken} \ ? \ \text{Target}_{branch} \ : \ (\text{jump\_taken} \ ? \ \text{Target}_{jump} \ : \ \text{PC} + 4)$$
   - In the same cycle:
     `inst = imem_rdata` $\rightarrow$ `decoder` $\rightarrow$ `regfile` read $\rightarrow$ `alu` $\rightarrow$ `dmem` access $\rightarrow$ `regfile` write latched on `posedge clk`.
   - Every instruction retires in exactly 1 clock cycle.
   - Zero stalls, zero bubbles, zero branch delay slots.
2. **Forwarding-Ready Primitives**:
   - The execution primitives in `core/common/` (`alu.sv`, `regfile.sv`, `decoder.sv`) are implemented as pure, modular SystemVerilog blocks with internal write-through forwarding in `regfile.sv`.
   - If an advanced pipelined version is built later, these primitives remain 100% reusable without modification.

### 8.3 P-Core (`big_core`) vs E-Core (`little_core`) Parity & Extensibility
- **Architecture Parity**:
  - `big_core` and `little_core` instantiate the exact same `core/common/` primitives.
  - Both pass the identical test suite in `tb/core_tb.sv` with identical register updates and memory state.
- **Future-Proofing**:
  - `big_core.sv` includes parameterization and stubbed extension hooks for coprocessor/SIMD interfaces (e.g. `coproc_req`, `coproc_ready`, `coproc_data`), ready for future P-core accelerator milestones.

---

## 9. SystemVerilog 2012 & Icarus Verilog (`iverilog 12.0`) Compatibility & Footguns

During active testing under `iverilog 12.0 -g2012`, several critical toolchain-specific behaviors and footguns were identified:

### 9.1 Footgun: Constant Bit-Selects in `always_*` Sensitivity Lists
**Observed Behavior**:
When slicing bits of an input or bus directly inside an `always_comb` block or case expression:
```systemverilog
// ❌ TRIGGERS IVERILOG WARNING
always_comb begin
    case (inst[31:28])
        4'b0000: ...
    endcase
    alu_out = rdata1 << rdata2[5:0];
end
```
`iverilog 12.0` prints:
```text
sorry: constant selects in always_* processes are not currently supported (all bits will be included).
```
While `iverilog` successfully falls back to including all bits in sensitivity, the prompt and `AGENTS.md` acceptance criteria mandate:
> `make test_cores builds with zero compiler errors or warnings in iverilog`

**Mandatory Idiom**:
Pre-slice all bit fields into dedicated continuous assignment `wire` declarations outside the `always_*` block:
```systemverilog
// ✅ 100% CLEAN, ZERO WARNINGS IN IVERILOG 12.0
wire [3:0] opcode = inst[31:28];
wire [4:0] rd     = inst[27:23];
wire [4:0] rs1    = inst[22:18];
wire [4:0] rs2    = inst[17:13];
wire [12:0] imm13 = inst[12:0];
wire [5:0] shamt  = b[5:0];

always_comb begin
    case (opcode)
        4'b0000: ...
    endcase
    alu_out = a << shamt;
end
```
Empirically verified in `build/test_constructs_4.sv`: this compiles with **zero warnings, zero errors, and clean simulation**.

### 9.2 Footgun: Interface Modports Across Hierarchical Boundaries
In `PROJECT.md` line 59, it was established that passing `interface.modport` signals across module port boundaries in `iverilog 12.0` can produce elaboration faults.
**Standard**:
All module boundaries for `big_core`, `little_core`, `alu`, `regfile`, and `decoder` must use discrete SystemVerilog ports (`input logic`, `output logic [63:0]`, etc.), exactly matching the convention proven in `system/cmu.sv`.

### 9.3 Safe Reset and Memory Array Initialization
In `regfile.sv`, resetting 32 registers using a loop:
```systemverilog
integer i;
always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
        for (i = 0; i < 32; i = i + 1) begin
            rf_mem[i] <= 64'd0;
        end
    end else if (wen && (waddr != 5'd0)) begin
        rf_mem[waddr] <= wdata;
    end
end
```
Declaring `integer i;` at module level ensures universal compatibility across all Verilog/SystemVerilog tools without loop-variable scoping issues.

### 9.4 Verification Build Flags
The Makefile target `test_cores` must invoke:
```makefile
$(IVERILOG) -g2012 -I include -Wall -Wno-timescale -s core_tb -o build/core_tb.vvp $^
```
Ensuring that `-I include` resolves `soc_pkg.sv` and `-Wall` enforces warning-free compilation.

---

## 10. Synthesis & Multi-Agent Consensus

### 10.1 Consensus with Codebase Explorer 1
1. **Module Hierarchy & Paths**:
   - Both surveys agree on placing shared primitives in `core/common/`:
     - `core/common/alu.sv`
     - `core/common/regfile.sv`
     - `core/common/decoder.sv`
   - Both cores in `core/`:
     - `core/big_core.sv`
     - `core/little_core.sv`
   - Testbench in `tb/core_tb.sv`.
2. **Package Preservation**:
   - `include/soc_pkg.sv` retains all 5-domain CMU definitions, adding ISA opcodes, enums, and parameters without modifying existing symbols.
3. **Reset Standard**:
   - `rst_ni` active-low asynchronous assert, synchronous deassert across all core modules.

### 10.2 Resolved Ambiguities & Technical Clarifications
1. **Shift Masking**:
   - Ambiguity: Does `SHL`/`SHR` shift by full 64-bit value or lower bits?
   - Resolution: Mask to `rs2[5:0]` ($0..63$). Shifting $\ge 64$ bits in hardware is undefined or wraps; masking to 6 bits guarantees standard 64-bit RISC behavior.
2. **Subroutine Return (`RET`) Support**:
   - Ambiguity: Does the ISA need a 17th opcode for `RET`?
   - Resolution: No. `JMP` cleanly unifies PC-relative jumps (`rs1 == 0`) and register-indirect returns (`rs1 != 0`, specifically `JMP r31, 0`). This maintains the strict 16-instruction orthogonal budget.
3. **Call Link Register**:
   - Convention: `r31` is the architectural link register. The decoder directs `PC + 4` writeback to `(rd != 0) ? rd : 5'd31`.
4. **Immediate Bit Width**:
   - The immediate field is confirmed as 13 bits (`inst[12:0]`), sign-extended to 64 bits for arithmetic, memory offsets, and branches.

### 10.3 Direct Action Items for Implementation Workers
1. **Worker M1 (ISA Package)**:
   - Extend `include/soc_pkg.sv` with `opcode_e`, `alu_op_e`, `inst_t`, `alu_flags_t`, and architectural parameters (`XLEN=64`, `ILEN=32`, `NUM_GPR=32`, `IMM_WIDTH=13`, `LINK_REG=5'd31`).
2. **Worker M2 (Execution Primitives)**:
   - Implement `core/common/alu.sv` with pre-sliced shift amount and flags.
   - Implement `core/common/regfile.sv` with hardwired `r0=0` and internal write-through bypass.
   - Implement `core/common/decoder.sv` with pre-sliced field wires to guarantee zero iverilog warnings.
3. **Worker M3 (Core Modules)**:
   - Implement `core/big_core.sv` and `core/little_core.sv` utilizing the Harvard bus architecture and deterministic single-cycle execution engine.
4. **Worker M4 (Testbench & Makefile)**:
   - Implement `tb/core_tb.sv` covering all 16 instructions, 64-bit data paths, RAW forwarding, loop execution, and core parity checks.
   - Add `test_cores` to `Makefile`.
