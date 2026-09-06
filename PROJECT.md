# Project: S-256 Baseline P-Core and E-Core Processors

## Architecture
The S-256 processor architecture implements a clean 64-bit datapath with 32 general-purpose registers (64-bit width, r0 hardwired to 0) executing a compact 32-bit fixed-length 16-instruction orthogonal RISC ISA.
Both the P-core (`big_core`) and E-core (`little_core`) execute the identical 64-bit datapath ISA and pipeline baseline, laying the foundation for future P-core coprocessor/SIMD extensions.
Clock and reset disciplines strictly follow S-256 standards: active-low asynchronous assert, synchronous deassert reset `rst_ni`.

### Inter-Module Dataflow
```text
[Instruction Memory] --> [Instruction Decoder] --> Control Signals & 64-bit sign-extended imm
                                  |
                                  v
                      [32x64-bit Register File] (r0=0, internal write-through forwarding)
                                  |
                                  v
                         [64-bit ALU] <--> Memory Address / Data Bus
                                  |
                                  v
                     [PC / Next-PC Control] --> [Data Memory Interface]
```

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | `OP_GROUP_ARITH` (2'b00) | Group opcode definition for arithmetic operations | M1 | ORIGINAL_REQUEST §R1 |
| 2 | `OP_GROUP_LOGIC` (2'b01) | Group opcode definition for logical operations | M1 | ORIGINAL_REQUEST §R1 |
| 3 | `OP_GROUP_MEM` (2'b10) | Group opcode definition for memory/data operations | M1 | ORIGINAL_REQUEST §R1 |
| 4 | `OP_GROUP_CTRL` (2'b11) | Group opcode definition for control flow operations | M1 | ORIGINAL_REQUEST §R1 |
| 5 | `OP_ADD` (4'b0000) | 64-bit addition: rd = rs1 + rs2 | M2 | ORIGINAL_REQUEST §R1 |
| 6 | `OP_SUB` (4'b0001) | 64-bit subtraction: rd = rs1 - rs2 | M2 | ORIGINAL_REQUEST §R1 |
| 7 | `OP_SHL` (4'b0010) | 64-bit logical shift left: rd = rs1 << rs2[5:0] | M2 | ORIGINAL_REQUEST §R1 |
| 8 | `OP_SHR` (4'b0011) | 64-bit logical shift right: rd = rs1 >> rs2[5:0] | M2 | ORIGINAL_REQUEST §R1 |
| 9 | `OP_AND` (4'b0100) | 64-bit bitwise AND: rd = rs1 & rs2 | M2 | ORIGINAL_REQUEST §R1 |
| 10 | `OP_OR` (4'b0101) | 64-bit bitwise OR: rd = rs1 \| rs2 | M2 | ORIGINAL_REQUEST §R1 |
| 11 | `OP_XOR` (4'b0110) | 64-bit bitwise XOR: rd = rs1 ^ rs2 | M2 | ORIGINAL_REQUEST §R1 |
| 12 | `OP_NOT` (4'b0111) | 64-bit bitwise NOT: rd = ~rs1 | M2 | ORIGINAL_REQUEST §R1 |
| 13 | `OP_LOAD` (4'b1000) | 64-bit memory load: rd = Mem[rs1 + sign_ext(imm13)] | M3 | ORIGINAL_REQUEST §R1 |
| 14 | `OP_STORE` (4'b1001) | 64-bit memory store: Mem[rs1 + sign_ext(imm13)] = rs2 | M3 | ORIGINAL_REQUEST §R1 |
| 15 | `OP_MOV` (4'b1010) | Register move: rd = rs1 | M3 | ORIGINAL_REQUEST §R1 |
| 16 | `OP_LDI` (4'b1011) | Load sign-extended 13-bit immediate: rd = sign_ext(imm13) | M3 | ORIGINAL_REQUEST §R1 |
| 17 | `OP_BEQ` (4'b1100) | Branch if rs1 == rs2: PC = PC + (sign_ext(imm13) << 2) | M3 | ORIGINAL_REQUEST §R1 |
| 18 | `OP_BNE` (4'b1101) | Branch if rs1 != rs2: PC = PC + (sign_ext(imm13) << 2) | M3 | ORIGINAL_REQUEST §R1 |
| 19 | `OP_CALL` (4'b1110) | Subroutine call: r31 (or rd) = PC + 4, PC = PC + (sign_ext(imm13) << 2) | M3 | ORIGINAL_REQUEST §R1 |
| 20 | `OP_JMP` (4'b1111) | Unconditional jump: if rs1!=0 target=R[rs1]+sign_ext(imm13) else target=PC+(sign_ext(imm13)<<2) | M3 | ORIGINAL_REQUEST §R1 |
| 21 | Instruction Word Struct `inst_t` | 32-bit packed format: opcode[31:28], rd[27:23], rs1[22:18], rs2[17:13], imm13[12:0] | M1 | ORIGINAL_REQUEST §R1 |
| 22 | Architecture Parameters | XLEN=64, ILEN=32, NUM_GPR=32, ALU opcodes/types | M1 | ORIGINAL_REQUEST §R1 |
| 23 | 64-bit ALU (`core/common/alu.sv`) | 64-bit arithmetic & logical operations + flags (Z, N, C, V) | M2 | ORIGINAL_REQUEST §R2 |
| 24 | 32x64-bit Regfile (`core/common/regfile.sv`) | 32 general-purpose 64-bit registers, r0=0 hardwired, parameterized FORWARDING | M2 | ORIGINAL_REQUEST §R2 |
| 25 | 32-bit Instruction Decoder (`core/common/decoder.sv`) | Decodes 32-bit words, generates control signals and sign-extended 64-bit immediates | M2 | ORIGINAL_REQUEST §R2 |
| 26 | P-Core Implementation (`core/big_core.sv`) | 64-bit single-cycle baseline datapath executing 16-instruction ISA, `rst_ni` active-low reset | M3 | ORIGINAL_REQUEST §R2 |
| 27 | E-Core Implementation (`core/little_core.sv`) | 64-bit single-cycle baseline datapath executing identical 16-instruction ISA, `rst_ni` | M3 | ORIGINAL_REQUEST §R2 |
| 28 | Harvard Memory Interface | Separate 64-bit instruction and data memory buses with byte strobes & reset gating | M3 | ORIGINAL_REQUEST §R2 |
| 29 | Register Bypass / Forwarding | Parameterized bypass in regfile (FORWARDING=1 for unit test, FORWARDING=0 for loop-free single-cycle datapath) | M2 | ORIGINAL_REQUEST §R2 |
| 30 | Control Flow Execution Engine | PC calculation for loops, branch forward/backward, call/return resolution | M3 | ORIGINAL_REQUEST §R3 |
| 31 | Verification Testbench (`tb/core_tb.sv`) | Dual-core testbench verifying all 16 instructions, hazards, memory, and sample program | M4 | ORIGINAL_REQUEST §R3 |
| 32 | Makefile Target (`test_cores`) | Build and execution target via `iverilog -g2012 -I include -Wall` and `vvp` | M4 | ORIGINAL_REQUEST §R3 |
| 33 | Zero Warning Compiler Idioms | Pre-sliced continuous assignment wires outside procedural blocks avoiding iverilog 12.0 warnings | M2 | AGENTS.md & ORIGINAL_REQUEST §R3 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | ISA & Datapath Definitions | Append ISA opcodes, groups, parameters, and `inst_t` to `include/soc_pkg.sv` | none | DONE |
| 2 | Shared Execution Primitives | Implement `core/common/alu.sv`, `core/common/regfile.sv`, `core/common/decoder.sv` | M1 | DONE |
| 3 | Core Datapaths (`big_core` & `little_core`) | Implement `core/big_core.sv` and `core/little_core.sv` with memory interfaces and `rst_ni` | M2 | DONE |
| 4 | Verification Suite & Makefile Target | Implement `tb/core_tb.sv` and add `test_cores` target to `Makefile` | M3 | DONE |
| 5 | E2E Verification & Adversarial Coverage Hardening | Run complete test suite, verify dual-core parity, zero warnings, adversarial stress testing | M4 | DONE |

## Interface Contracts

### 1. `soc_pkg.sv` Datatypes
```systemverilog
typedef enum logic [1:0] {
    OP_GROUP_ARITH = 2'b00,
    OP_GROUP_LOGIC = 2'b01,
    OP_GROUP_MEM   = 2'b10,
    OP_GROUP_CTRL  = 2'b11
} op_group_e;

typedef enum logic [3:0] {
    OP_ADD   = 4'b0000,
    OP_SUB   = 4'b0001,
    OP_SHL   = 4'b0010,
    OP_SHR   = 4'b0011,
    OP_AND   = 4'b0100,
    OP_OR    = 4'b0101,
    OP_XOR   = 4'b0110,
    OP_NOT   = 4'b0111,
    OP_LOAD  = 4'b1000,
    OP_STORE = 4'b1001,
    OP_MOV   = 4'b1010,
    OP_LDI   = 4'b1011,
    OP_BEQ   = 4'b1100,
    OP_BNE   = 4'b1101,
    OP_CALL  = 4'b1110,
    OP_JMP   = 4'b1111
} opcode_e;

typedef struct packed {
    logic [3:0]  opcode; // [31:28]
    logic [4:0]  rd;     // [27:23]
    logic [4:0]  rs1;    // [22:18]
    logic [4:0]  rs2;    // [17:13]
    logic [12:0] imm13;  // [12:0]
} inst_t;

typedef struct packed {
    logic zero;
    logic negative;
    logic carry;
    logic overflow;
} alu_flags_t;
```

### 2. `alu.sv` Module Contract
```systemverilog
module alu (
    input  logic [3:0]        alu_op,
    input  logic [63:0]       op_a,
    input  logic [63:0]       op_b,
    output logic [63:0]       alu_res,
    output alu_flags_t        alu_flags
);
```

### 3. `regfile.sv` Module Contract
```systemverilog
module regfile #(
    parameter bit FORWARDING = 1'b1
) (
    input  logic        clk,
    input  logic        rst_ni,
    input  logic [4:0]  raddr1,
    output logic [63:0] rdata1,
    input  logic [4:0]  raddr2,
    output logic [63:0] rdata2,
    input  logic        wen,
    input  logic [4:0]  waddr,
    input  logic [63:0] wdata
);
```

### 4. `decoder.sv` Module Contract
```systemverilog
module decoder (
    input  logic [31:0] inst,
    output logic [3:0]  opcode,
    output logic [1:0]  op_group,
    output logic [4:0]  rd,
    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [12:0] imm13,
    output logic [63:0] imm64_sext,
    output logic        reg_write,
    output logic        mem_read,
    output logic        mem_write,
    output logic        is_branch,
    output logic        is_jump,
    output logic        is_call,
    output logic        alu_src_imm,
    output logic        illegal_inst
);
```

### 5. `big_core.sv` & `little_core.sv` Core Port Contracts
```systemverilog
module big_core (
    input  logic        clk,
    input  logic        rst_ni,
    // Instruction memory interface
    output logic [63:0] imem_addr,
    input  logic [31:0] imem_rdata,
    // Data memory interface
    output logic [63:0] dmem_addr,
    output logic [63:0] dmem_wdata,
    output logic [7:0]  dmem_wstrb,
    output logic        dmem_wen,
    output logic        dmem_ren,
    input  logic [63:0] dmem_rdata
);
```

## Code Layout
```text
include/
└── soc_pkg.sv              # Appended with ISA opcodes, parameters, inst_t, alu_flags_t
core/
├── common/
│   ├── alu.sv              # 64-bit ALU
│   ├── regfile.sv          # 32x64-bit Register File (r0=0, write-through forwarding)
│   └── decoder.sv          # 32-bit Instruction Decoder & Sign Extension
├── big_core.sv             # Baseline P-Core
└── little_core.sv          # Baseline E-Core
tb/
└── core_tb.sv              # Verification testbench for both cores
Makefile                    # Contains test_cores build and execution target
```
