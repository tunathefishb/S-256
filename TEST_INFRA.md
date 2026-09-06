# E2E Test Infrastructure: S-256 Baseline Dual-Core Processors (`big_core` & `little_core`)

## 1. Verification Philosophy & Architectural Directives
- **Verification Goal**: Rigorous, automated end-to-end verification of the S-256 64-bit dual-core architecture (`big_core` and `little_core`), ensuring 100% functional equivalence, full 16-instruction ISA coverage, boundary robustness, hazard resolution, and zero-warning compilation.
- **Architectural Reference**: `ORIGINAL_REQUEST.md`, `AGENTS.md`, and `PROJECT.md`.
- **Toolchain**: Icarus Verilog 12.0 (`iverilog -g2012 -I include -Wall -Wno-timescale`) executed via `vvp`.
- **Zero-Tolerance Invariant**: Simulation halts with non-zero exit status (`$fatal(1)`) or increments a failure tally upon any mismatch. `TEST PASSED` is printed if and only if 100% of checks pass with zero failures.
- **Co-Simulation Parity**: Both `big_core` and `little_core` are instantiated simultaneously in `tb/core_tb.sv` and stimulated identically. Every architectural update (PC, instruction memory access, data memory address/strobe/write data, register writeback) must match identically across both cores in every cycle.

---

## 2. Feature Inventory Matrix

| # | Feature / Instruction | Opcode | Format | Description | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---|-----------------------|:------:|:------:|-------------|:------:|:------:|:------:|:------:|
| 1 | **ADD** | `4'b0000` | R-Type | 64-bit Integer Addition: $R[rd] \leftarrow R[rs1] + R[rs2]$ | 5 | 5 | ✓ | ✓ |
| 2 | **SUB** | `4'b0001` | R-Type | 64-bit Integer Subtraction: $R[rd] \leftarrow R[rs1] - R[rs2]$ | 5 | 5 | ✓ | ✓ |
| 3 | **SHL** | `4'b0010` | R-Type | 64-bit Logical Shift Left: $R[rd] \leftarrow R[rs1] \ll R[rs2][5:0]$ | 5 | 5 | ✓ | ✓ |
| 4 | **SHR** | `4'b0011` | R-Type | 64-bit Logical Shift Right: $R[rd] \leftarrow R[rs1] \gg R[rs2][5:0]$ | 5 | 5 | ✓ | ✓ |
| 5 | **AND** | `4'b0100` | R-Type | 64-bit Bitwise AND: $R[rd] \leftarrow R[rs1] \ \& \ R[rs2]$ | 5 | 5 | ✓ | ✓ |
| 6 | **OR**  | `4'b0101` | R-Type | 64-bit Bitwise OR: $R[rd] \leftarrow R[rs1] \ \| \ R[rs2]$ | 5 | 5 | ✓ | ✓ |
| 7 | **XOR** | `4'b0110` | R-Type | 64-bit Bitwise Exclusive OR: $R[rd] \leftarrow R[rs1] \oplus R[rs2]$ | 5 | 5 | ✓ | ✓ |
| 8 | **NOT** | `4'b0111` | R-Type | 64-bit Bitwise Inversion: $R[rd] \leftarrow \sim R[rs1]$ | 5 | 5 | ✓ | ✓ |
| 9 | **LOAD**| `4'b1000` | I-Type | 64-bit Memory Load: $R[rd] \leftarrow \text{Mem}[R[rs1] + \text{Sext}(imm13)]$ | 5 | 5 | ✓ | ✓ |
| 10| **STORE**|`4'b1001` | S-Type | 64-bit Memory Store: $\text{Mem}[R[rs1] + \text{Sext}(imm13)] \leftarrow R[rs2]$ | 5 | 5 | ✓ | ✓ |
| 11| **MOV**  | `4'b1010` | R-Type | Register Move: $R[rd] \leftarrow R[rs1]$ | 5 | 5 | ✓ | ✓ |
| 12| **LDI**  | `4'b1011` | I-Type | Load 13-bit Sign-Ext Immediate: $R[rd] \leftarrow \text{Sext}(imm13)$ | 5 | 5 | ✓ | ✓ |
| 13| **BEQ**  | `4'b1100` | B-Type | Branch if Equal: if $R[rs1] == R[rs2] \implies PC \leftarrow PC + (\text{Sext}(imm13) \ll 2)$ | 5 | 5 | ✓ | ✓ |
| 14| **BNE**  | `4'b1101` | B-Type | Branch if Not Equal: if $R[rs1] \neq R[rs2] \implies PC \leftarrow PC + (\text{Sext}(imm13) \ll 2)$ | 5 | 5 | ✓ | ✓ |
| 15| **CALL** | `4'b1110` | J-Type | Subroutine Call: $R[31] \leftarrow PC + 4; \ PC \leftarrow PC + (\text{Sext}(imm13) \ll 2)$ | 5 | 5 | ✓ | ✓ |
| 16| **JMP**  | `4'b1111` | J-Type | Unconditional Jump: $(rs1 \neq 0) ? R[rs1] + \text{Sext}(imm13) : PC + (\text{Sext}(imm13) \ll 2)$ | 5 | 5 | ✓ | ✓ |
| 17| **GPR File** | — | Arch | 32 64-bit registers, hardwired $r0 \equiv 0$, write-through bypass | 5 | 5 | ✓ | ✓ |
| 18| **Reset / S-256** | — | Arch | Active-low asynchronous assert, synchronous deassert reset `rst_ni` | 5 | 5 | ✓ | ✓ |
| 19| **Dual-Core Parity** | — | System | Lockstep comparison between `big_core` and `little_core` | 5 | 5 | ✓ | ✓ |

---

## 3. Test Architecture & Verification Harness

### 3.1 Harness Topology (`tb/core_tb.sv`)
The verification environment instantiates:
1. **P-Core DUT (`big_core`)**: Primary high-performance baseline core instance.
2. **E-Core DUT (`little_core`)**: Secondary energy-efficient baseline core instance.
3. **Dual Harvard Memory Subsystems**:
   - `imem` (Instruction Memory): Dual-read port 64 KB RAM/ROM storing 32-bit instructions (`imem_rdata_big`, `imem_rdata_lit`).
   - `dmem` (Data Memory): Dual-port 64 KB 64-bit wide RAM supporting independent read/write requests from both cores.
4. **Clock and Reset Sequencer**:
   - `clk`: 100 MHz simulated clock (10 ns period).
   - `rst_ni`: Active-low reset conforming to S-256 discipline (asynchronous assert, synchronous deassert on clock falling edge).
5. **Self-Checking Assertion Engine**:
   - Compares internal architectural states of both cores against gold-standard mathematical predictions.
   - Cross-checks `big_core` vs `little_core` output buses (`pc`, `imem_addr`, `dmem_addr`, `dmem_wdata`, `dmem_wen`, `dmem_ren`, `dmem_wstrb`).

### 3.2 Instruction Encoding Helper Functions
`tb/core_tb.sv` implements bit-exact instruction synthesis functions:
- `encode_r(opcode, rd, rs1, rs2, imm13)`: Packs fields into 32-bit `inst_t`.
- `encode_i(opcode, rd, rs1, imm13)`: Packs immediate arithmetic, memory loads, and `LDI`.
- `encode_s(opcode, rs1, rs2, imm13)`: Packs `STORE` instructions.
- `encode_b(opcode, rs1, rs2, imm13)`: Packs conditional branches (`BEQ`, `BNE`).
- `encode_j(opcode, rd, rs1, imm13)`: Packs calls and jumps (`CALL`, `JMP`).

---

## 4. Multi-Tier Verification Breakdown

### Tier 1: Feature Coverage (>=5 Tests Per Feature)
Validates the nominal functional path for all 16 ISA instructions and core architectural mechanisms.

#### 1. ADD (Opcode `4'b0000`)
- **T1.1.1**: Small positive addition: $5 + 10 = 15$.
- **T1.1.2**: 32-bit range addition: $0x1234\_5678 + 0x0000\_0001 = 0x1234\_5679$.
- **T1.1.3**: 64-bit high-order addition: $0x1000\_0000\_0000\_0000 + 0x2000\_0000\_0000\_0000 = 0x3000\_0000\_0000\_0000$.
- **T1.1.4**: Positive plus negative canceling to zero: $50 + (-50) = 0$.
- **T1.1.5**: Register self-addition: $r1 + r1 = 2 \times r1$.

#### 2. SUB (Opcode `4'b0001`)
- **T1.2.1**: Small positive subtraction: $20 - 7 = 13$.
- **T1.2.2**: Cancellation to zero: $0xDEAD\_BEEF\_1234\_5678 - 0xDEAD\_BEEF\_1234\_5678 = 0$.
- **T1.2.3**: Subtraction producing negative result: $10 - 25 = -15$ (`0xFFFF_FFFF_FFFF_FFF1`).
- **T1.2.4**: Subtracting negative number: $100 - (-50) = 150$.
- **T1.2.5**: Full 64-bit patterned subtraction: $0x5555\_5555\_5555\_5555 - 0x1111\_1111\_1111\_1111 = 0x4444\_4444\_4444\_4444$.

#### 3. SHL (Opcode `4'b0010`)
- **T1.3.1**: Single-bit shift left: $0x1 \ll 1 = 0x2$.
- **T1.3.2**: Byte shift left: $0xFF \ll 8 = 0xFF00$.
- **T1.3.3**: Word crossing shift left: $0x0000\_0000\_FFFF\_FFFF \ll 32 = 0xFFFF\_FFFF\_0000\_0000$.
- **T1.3.4**: Large shift left: $0x1 \ll 60 = 0x1000\_0000\_0000\_0000$.
- **T1.3.5**: Pattern shift left: $0x5555\_5555\_5555\_5555 \ll 2 = 0x5555\_5555\_5555\_5554$.

#### 4. SHR (Opcode `4'b0011`)
- **T1.4.1**: Single-bit shift right: $0x2 \gg 1 = 0x1$.
- **T1.4.2**: Byte shift right: $0xFF00 \gg 8 = 0x00FF$.
- **T1.4.3**: Word crossing shift right: $0xFFFF\_FFFF\_0000\_0000 \gg 32 = 0x0000\_0000\_FFFF\_FFFF$.
- **T1.4.4**: Large shift right: $0x8000\_0000\_0000\_0000 \gg 60 = 0x0000\_0000\_0000\_0008$.
- **T1.4.5**: Logical zero-fill verification: $0x8000\_0000\_0000\_0000 \gg 1 = 0x4000\_0000\_0000\_0000$.

#### 5. AND (Opcode `4'b0100`)
- **T1.5.1**: Disjoint mask AND: $0xFFFF\_0000\_FFFF\_0000 \ \& \ 0x0000\_FFFF\_0000\_FFFF = 0$.
- **T1.5.2**: Identity with all-ones: $0xDEAD\_BEEF\_CAFE\_BABE \ \& \ \sim 0 = 0xDEAD\_BEEF\_CAFE\_BABE$.
- **T1.5.3**: Zeroing with zero: $0xDEAD\_BEEF\_CAFE\_BABE \ \& \ 0 = 0$.
- **T1.5.4**: Alternating pattern AND: $0xAAAA\_AAAA\_AAAA\_AAAA \ \& \ 0x5555\_5555\_5555\_5555 = 0$.
- **T1.5.5**: Self AND: $r1 \ \& \ r1 = r1$.

#### 6. OR (Opcode `4'b0101`)
- **T1.6.1**: Disjoint field combining: $0xFFFF\_0000\_0000\_0000 \ \| \ 0x0000\_0000\_0000\_FFFF = 0xFFFF\_0000\_0000\_FFFF$.
- **T1.6.2**: Identity with zero: $0x1234\_5678\_9ABC\_DEF0 \ \| \ 0 = 0x1234\_5678\_9ABC\_DEF0$.
- **T1.6.3**: Saturating with all-ones: $0x1234\_5678\_9ABC\_DEF0 \ \| \ \sim 0 = \sim 0$.
- **T1.6.4**: Alternating pattern OR: $0xAAAA\_AAAA\_AAAA\_AAAA \ \| \ 0x5555\_5555\_5555\_5555 = \sim 0$.
- **T1.6.5**: Self OR: $r1 \ \| \ r1 = r1$.

#### 7. XOR (Opcode `4'b0110`)
- **T1.7.1**: Self-annihilation: $r1 \oplus r1 = 0$.
- **T1.7.2**: Inversion with all-ones: $0x0F0F\_0F0F\_0F0F\_0F0F \oplus \sim 0 = 0xF0F0\_F0F0\_F0F0\_F0F0$.
- **T1.7.3**: Identity with zero: $r1 \oplus 0 = r1$.
- **T1.7.4**: Alternating pattern XOR: $0xAAAA\_AAAA\_AAAA\_AAAA \oplus 0x5555\_5555\_5555\_5555 = \sim 0$.
- **T1.7.5**: Reversible property: $(A \oplus B) \oplus B = A$.

#### 8. NOT (Opcode `4'b0111`)
- **T1.8.1**: NOT of zero: $\sim 0 = 0xFFFF\_FFFF\_FFFF\_FFFF$.
- **T1.8.2**: NOT of all-ones: $\sim(\sim 0) = 0$.
- **T1.8.3**: NOT of alternating pattern: $\sim 0xAAAA\_AAAA\_AAAA\_AAAA = 0x5555\_5555\_5555\_5555$.
- **T1.8.4**: Single-bit inversion: $\sim 0x1 = 0xFFFF\_FFFF\_FFFF\_FFFE$.
- **T1.8.5**: Double NOT restoration: $\sim(\sim r1) = r1$.

#### 9. LOAD (Opcode `4'b1000`)
- **T1.9.1**: Load doubleword at base address zero offset ($EA = r1 + 0$).
- **T1.9.2**: Load doubleword at positive offset ($EA = r1 + 8$).
- **T1.9.3**: Load consecutive elements into sequential registers ($r2, r3, r4$).
- **T1.9.4**: Load with base $r0$ (absolute memory addressing).
- **T1.9.5**: Load high-memory address ($EA \ge 0x0000\_1000$).

#### 10. STORE (Opcode `4'b1001`)
- **T1.10.1**: Store doubleword at base address zero offset ($EA = r1 + 0$).
- **T1.10.2**: Store doubleword at positive offset ($EA = r1 + 8$).
- **T1.10.3**: Store distinct values from sequential registers ($r2, r3, r4$).
- **T1.10.4**: Store with base $r0$ (absolute memory addressing).
- **T1.10.5**: Successive store operations to consecutive addresses without interference.

#### 11. MOV (Opcode `4'b1010`)
- **T1.11.1**: Move positive integer between registers: $r2 \leftarrow r1$.
- **T1.11.2**: Move negative integer between registers: $r4 \leftarrow r3$.
- **T1.11.3**: Move full 64-bit bit pattern: $r6 \leftarrow r5$.
- **T1.11.4**: Move zero from $r0$: $r7 \leftarrow r0$.
- **T1.11.5**: Multi-register cascading move: $r1 \rightarrow r2 \rightarrow r3 \rightarrow r4$.

#### 12. LDI (Opcode `4'b1011`)
- **T1.12.1**: Load zero immediate: $r1 \leftarrow 0$.
- **T1.12.2**: Load small positive immediate: $r2 \leftarrow 42$.
- **T1.12.3**: Load positive immediate with bit 11 set: $r3 \leftarrow 0x07FF$ (+2047).
- **T1.12.4**: Load minus one immediate: $r4 \leftarrow -1$ (`0xFFFF_FFFF_FFFF_FFFF`).
- **T1.12.5**: Load negative immediate: $r5 \leftarrow -100$.

#### 13. BEQ (Opcode `4'b1100`)
- **T1.13.1**: Branch taken on register equality ($r1 == r2$).
- **T1.13.2**: Branch not taken on unequal registers ($r1 \neq r2$).
- **T1.13.3**: Unconditional relative branch idiom using $r0 == r0$.
- **T1.13.4**: Forward branch skipping intermediate instructions.
- **T1.13.5**: Backward branch in a loop body.

#### 14. BNE (Opcode `4'b1101`)
- **T1.14.1**: Branch taken on register inequality ($r1 \neq r2$).
- **T1.14.2**: Branch not taken on equal registers ($r1 == r2$).
- **T1.14.3**: Branch taken comparing register against zero ($r1 \neq r0$).
- **T1.14.4**: Forward branch jumping over an error marker.
- **T1.14.5**: Backward branch terminating a loop when counter reaches zero.

#### 15. CALL (Opcode `4'b1110`)
- **T1.15.1**: Call forward subroutine: verifies link register $r31 = PC + 4$.
- **T1.15.2**: Call forward subroutine: verifies target PC is $PC + (imm13 \ll 2)$.
- **T1.15.3**: Call with specified return register $rd \neq 0$ (e.g. $rd = r30$).
- **T1.15.4**: Sequential leaf calls updating $r31$ on each invocation.
- **T1.15.5**: Execution resumption after subroutine completes.

#### 16. JMP (Opcode `4'b1111`)
- **T1.16.1**: PC-relative unconditional jump ($rs1 = 0$).
- **T1.16.2**: Forward PC-relative jump skipping traps.
- **T1.16.3**: Backward PC-relative jump.
- **T1.16.4**: Subroutine return via register-indirect jump: `JMP r31, 0`.
- **T1.16.5**: Computed jump via general register: `JMP rs1, offset`.

---

### Tier 2: Boundary & Corner Cases (>=5 Tests Per Feature)
Stress tests 64-bit boundaries, immediate sign limits, hardwiring, and edge behaviors.

#### 1. 64-bit Arithmetic Overflows & Extrema
- **T2.1.1**: `ADD` Signed Overflow: `0x7FFF_FFFF_FFFF_FFFF + 1` $= 0x8000\_0000\_0000\_0000$ (MSB toggles, signed overflow).
- **T2.1.2**: `ADD` Unsigned Carry-out: `0xFFFF_FFFF_FFFF_FFFF + 1` $= 0x0000\_0000\_0000\_0000$ (modular 64-bit wrap).
- **T2.1.3**: `ADD` Zero Identity: $0 + 0 = 0$.
- **T2.1.4**: `SUB` Negative Signed Overflow: `0x8000_0000_0000_0000 - 1` $= 0x7FFF\_FFFF\_FFFF\_FFFF$.
- **T2.1.5**: `SUB` Unsigned Borrow / Wrap: $0 - 1 = 0xFFFF\_FFFF\_FFFF\_FFFF$.

#### 2. Shift Count Masking & Boundaries
- **T2.2.1**: `SHL` by 0 bits (value unchanged).
- **T2.2.2**: `SHL` by maximum 63 bits ($1 \ll 63 = 0x8000\_0000\_0000\_0000$).
- **T2.2.3**: `SHL` with shift amount $\ge 64$ masked to 6 bits ($rs2 = 64 \implies \text{count}=0$; $rs2 = 65 \implies \text{count}=1$).
- **T2.2.4**: `SHR` by 0 bits (value unchanged).
- **T2.2.5**: `SHR` by maximum 63 bits ($0x8000\_0000\_0000\_0000 \gg 63 = 0x1$).
- **T2.2.6**: `SHR` with shift amount $\ge 64$ masked to 6 bits ($rs2 = 67 \implies \text{count}=3$).

#### 3. Register `r0` Hardwiring Invariant
- **T2.3.1**: Write to `r0` via `LDI r0, 0x123` $\implies r0$ remains $0$.
- **T2.3.2**: Write to `r0` via `ADD r0, r1, r2` $\implies r0$ remains $0$.
- **T2.3.3**: Write to `r0` via `LOAD r0, 0(r1)` $\implies r0$ remains $0$.
- **T2.3.4**: Write to `r0` via `MOV r0, r1` $\implies r0$ remains $0$.
- **T2.3.5**: Concurrent write to `r0` and read of `r0` in same cycle $\implies$ returns $0$.

#### 4. Immediate Sign Extension Boundaries (13-bit: $[-4096, +4095]$)
- **T2.4.1**: Maximum positive immediate: $imm13 = 13'h0FFF$ (+4095) $\implies 64'h0000\_0000\_0000\_0FFF$.
- **T2.4.2**: Minimum negative immediate: $imm13 = 13'h1000$ (-4096) $\implies 64'hFFFF\_FFFF\_FFFF\_F000$.
- **T2.4.3**: Minus one immediate: $imm13 = 13'h1FFF$ (-1) $\implies 64'hFFFF\_FFFF\_FFFF\_FFFF$.
- **T2.4.4**: Zero immediate: $imm13 = 13'h0000$ (0) $\implies 64'h0000\_0000\_0000\_0000$.
- **T2.4.5**: Sign bit boundary transition: $+2048$ ($13'h0800$, bit 12=0) vs $-2048$ ($13'h1800$, bit 12=1).

#### 5. Memory Offset & Hazard Boundaries
- **T2.5.1**: `LOAD` with negative offset: $EA = r1 + (-8)$ ($imm13 = 13'h1FF8$).
- **T2.5.2**: `STORE` with negative offset: $EA = r1 + (-16)$ ($imm13 = 13'h1FF0$).
- **T2.5.3**: Maximum positive memory offset: $+4088$ ($13'h0FF8$, doubleword-aligned).
- **T2.5.4**: Maximum negative memory offset: $-4096$ ($13'h1000$, doubleword-aligned).
- **T2.5.5**: Consecutive writes overwriting the same doubleword address.

#### 6. Control Flow Displacement Boundaries
- **T2.6.1**: Maximum positive branch offset: $+1023$ instructions ($+4092$ bytes).
- **T2.6.2**: Maximum negative branch offset: $-1024$ instructions ($-4096$ bytes).
- **T2.6.3**: Zero offset branch: $imm13 = 0$.
- **T2.6.4**: Branch taken when operands differ by only 1 bit ($r1 = 0x1, r2 = 0x0$).
- **T2.6.5**: Branch not taken when operands share lower 63 bits but differ at MSB.

---

### Tier 3: Cross-Feature Combinations (Pairwise Interactions)
Validates interactions between execution pipeline stages, memory, and control flow.

- **Scenario 3.1: Arithmetic $\rightarrow$ Logic RAW Data Hazard**:
  `ADD r1, r2, r3` followed immediately by `AND r4, r1, r5`. Verifies that the register file or bypass forwarding supplies the newly written `r1` without a bubble.
- **Scenario 3.2: Store $\rightarrow$ Load RAW Memory Coherence**:
  `STORE r2, 0(r1)` followed immediately by `LOAD r3, 0(r1)`. Verifies that data written to memory is instantly readable on the subsequent cycle.
- **Scenario 3.3: Immediate Generation $\rightarrow$ Address Pointer Arithmetic**:
  `LDI r1, 16` $\rightarrow$ `ADD r2, r2, r1` $\rightarrow$ `STORE r3, 0(r2)` $\rightarrow$ `LOAD r4, 0(r2)`.
- **Scenario 3.4: Subroutine Call $\rightarrow$ Execution $\rightarrow$ Return Linkage**:
  Main issues `CALL func_add` $\rightarrow$ Subroutine computes $r1 = r2 + r3$ $\rightarrow$ Returns via `JMP r31, 0` $\rightarrow$ Caller validates result and returns to sequential PC ($PC_{call} + 4$).
- **Scenario 3.5: Conditional Branch Skipping Destructive Store**:
  `BEQ r1, r1, skip_store` jumps over a `STORE` that would corrupt memory. Verifies memory remains unmodified.
- **Scenario 3.6: Multi-Stage Shift and Logic Masking**:
  `SHL r1, r1, 8` $\rightarrow$ `OR r1, r1, r2` $\rightarrow$ `SHR r1, r1, 4` $\rightarrow$ `XOR r1, r1, r3`.
- **Scenario 3.7: Register State Persistence across Iterative Loops**:
  Loop modifies only `r1` and `r2`, asserting that `r10` through `r20` preserve their initial random state across 20 iterations.
- **Scenario 3.8: Asynchronous Reset Assertion During Active Processing**:
  Core is actively executing ALU and memory traffic when `rst_ni` is asynchronously asserted. Verifies instantaneous clear of PC to $0$, suppression of memory writes (`dmem_wen = 0`), and register file clear.

---

### Tier 4: Real-World Application Scenarios
Executes full algorithm benchmarks and stress workloads.

- **Scenario 4.1: Iterative Fibonacci Sequence Generation**:
  - Computes 10 terms of the Fibonacci sequence: $F(0)=0, F(1)=1, F(2)=1, F(3)=2, F(4)=3, F(5)=5, F(6)=8, F(7)=13, F(8)=21, F(9)=34, F(10)=55$.
  - Stores each computed term into data memory array at addresses `0x100, 0x108, 0x110, ...`.
  - Verifies memory array contents after loop termination.
- **Scenario 4.2: Subroutine-Driven Factorial Calculation**:
  - Main initializes argument register $r1 = 6$.
  - Calls `factorial` subroutine via `CALL`.
  - Subroutine executes loop: $6 \times 5 \times 4 \times 3 \times 2 \times 1 = 720$.
  - Returns to caller via `JMP r31, 0`.
  - Main verifies $r1 == 720$ and $PC$ resumed at `CALL + 4`.
- **Scenario 4.3: Memory Block Copy & Checksum Verification**:
  - Populates a 4-element array in data memory.
  - Copies the block to a destination address while computing a running XOR checksum.
  - Verifies destination buffer matches source buffer and computed checksum is correct.
- **Scenario 4.4: Nested Function Calls with Simulated Stack Frame**:
  - `main` calls `func_outer`.
  - `func_outer` saves link register $r31$ to memory (`STORE r31, 0(sp)`).
  - `func_outer` calls `func_inner`.
  - `func_inner` computes result and returns to `func_outer`.
  - `func_outer` restores link register (`LOAD r31, 0(sp)`) and returns to `main`.
  - Verifies flawless return to `main`.
- **Scenario 4.5: Dual-Core Lockstep Parity Verification**:
  - `big_core` and `little_core` execute the complete test suite concurrently.
  - In every single clock cycle, assertions check:
    $$imem\_addr_{big} == imem\_addr_{lit}$$
    $$dmem\_addr_{big} == dmem\_addr_{lit}$$
    $$dmem\_wdata_{big} == dmem\_wdata_{lit}$$
    $$dmem\_wen_{big} == dmem\_wen_{lit}$$
    $$dmem\_ren_{big} == dmem\_ren_{lit}$$
  - Guarantees 100% datapath and architectural parity between P-core and E-core.

---

## 5. Coverage Thresholds & Pass Criteria

- **Tier 1**: $\ge 80$ assertions ($16 \text{ instructions} \times 5 \text{ tests}$) + 15 architectural tests $\ge 95$ checks.
- **Tier 2**: $\ge 30$ boundary / corner case assertions.
- **Tier 3**: $\ge 8$ cross-feature interaction scenarios.
- **Tier 4**: $\ge 5$ end-to-end application workloads.
- **Total Verification Assertions**: $> 140$ checks.
- **Target Pass Rate**: 100% ($0$ failures).
