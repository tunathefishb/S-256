## 2026-09-06T11:29:09Z

You are teamwork_preview_worker implementing Milestone 3: Core Datapaths (core/big_core.sv and core/little_core.sv).
Your working directory: /home/tunathefish_b/Code/S-256/.agents/worker_m3
Original Request path: /home/tunathefish_b/Code/S-256/.agents/ORIGINAL_REQUEST.md
PROJECT.md path: /home/tunathefish_b/Code/S-256/PROJECT.md
TEST_INFRA.md path: /home/tunathefish_b/Code/S-256/TEST_INFRA.md
Include path: /home/tunathefish_b/Code/S-256/include/soc_pkg.sv
Primitives:
- /home/tunathefish_b/Code/S-256/core/common/alu.sv
- /home/tunathefish_b/Code/S-256/core/common/regfile.sv
- /home/tunathefish_b/Code/S-256/core/common/decoder.sv
Testbench:
- /home/tunathefish_b/Code/S-256/tb/core_tb.sv

Task:
Implement Milestone 3:
Create core/big_core.sv and core/little_core.sv in SystemVerilog (IEEE 1800-2012):
1. Both cores must instantiate the shared execution units: decoder, regfile, and alu.
2. Port signature for both cores must match PROJECT.md and tb/core_tb.sv:
   - input logic clk
   - input logic rst_ni (active-low asynchronous assert, synchronous deassert)
   - output logic [63:0] imem_addr
   - input logic [31:0] imem_rdata
   - output logic [63:0] dmem_addr
   - output logic [63:0] dmem_wdata
   - output logic [7:0]  dmem_wstrb
   - output logic        dmem_wen
   - output logic        dmem_ren
   - input logic [63:0]  dmem_rdata
3. Single-cycle datapath executing the full 16-instruction orthogonal RISC ISA:
   - PC update logic on posedge clk with async active-low reset !rst_ni -> pc <= 64'd0.
   - Next PC calculation:
     - If is_branch: BEQ taken when rdata1 == rdata2, BNE taken when rdata1 != rdata2. Target = pc + (imm64_sext << 2).
     - If is_call: target = pc + (imm64_sext << 2). Save return address pc + 4 into register rd != 0 ? rd : LINK_REG (r31).
     - If is_jump: if rs1 != 0 target = rdata1 + imm64_sext (indirect jump / subroutine return via JMP r31, 0); if rs1 == 0 target = pc + (imm64_sext << 2).
     - Else sequential: target = pc + 4.
   - Register writeback selection:
     - CALL: pc + 4
     - LOAD: dmem_rdata
     - LDI: imm64_sext
     - MOV: rdata1
     - ALU instructions: alu_res
   - Memory interface:
     - imem_addr = pc
     - dmem_addr = rdata1 + imm64_sext
     - dmem_wdata = rdata2
     - dmem_wstrb = mem_write ? 8'hFF : 8'h00
     - dmem_wen = mem_write
     - dmem_ren = mem_read
4. Both big_core.sv and little_core.sv have full functional parity.
5. Critical: Avoid Icarus Verilog 12.0 constant-select warnings by declaring intermediate wires outside always_comb if any bit-slicing is needed.
6. Verify by running make test_cores and confirm:
   - Zero compiler warnings, zero errors.
   - All 94 checks across Tiers 1-4 pass.
   - Dual-core cycle-by-cycle parity check passes with 0 errors.
   - Test concludes with TEST PASSED.
7. Write your handoff to /home/tunathefish_b/Code/S-256/.agents/worker_m3/handoff.md. Send a message upon completion.

Exclusive file ownership: core/big_core.sv, core/little_core.sv.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
