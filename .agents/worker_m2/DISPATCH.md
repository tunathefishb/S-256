## 2026-09-06T11:24:48Z

You are teamwork_preview_worker implementing Milestone 2: Execution Primitives in core/common/.
Your working directory: /home/tunathefish_b/Code/S-256/.agents/worker_m2
Original Request path: /home/tunathefish_b/Code/S-256/.agents/ORIGINAL_REQUEST.md
PROJECT.md path: /home/tunathefish_b/Code/S-256/PROJECT.md
Include path: /home/tunathefish_b/Code/S-256/include/soc_pkg.sv

Explorer reports:
- /home/tunathefish_b/Code/S-256/.agents/spec_miner_survey/spec_analysis.md
- /home/tunathefish_b/Code/S-256/.agents/explorer_survey_1/analysis.md
- /home/tunathefish_b/Code/S-256/.agents/explorer_survey_2/analysis.md

Task:
Implement Milestone 2:
Create directory core/common/ and implement the 3 execution primitive modules in SystemVerilog (IEEE 1800-2012):
1. core/common/alu.sv:
   - 64-bit ALU supporting all arithmetic (ADD, SUB, SHL, SHR) and logical (AND, OR, XOR, NOT) operations, plus MOV/LDI pass-through (ALU_PASSA, ALU_PASSB).
   - Slicing shift amount: wire [5:0] shamt = op_b[5:0]; to strictly shift 0..63 bits.
   - Outputs 64-bit alu_res and alu_flags_t (zero, negative, carry, overflow).
   - Calculate overflow for 64-bit signed:
     ADD: (~(op_a[63] ^ op_b[63])) & (op_a[63] ^ alu_res[63])
     SUB: (op_a[63] ^ op_b[63]) & (op_a[63] ^ alu_res[63])
2. core/common/regfile.sv:
   - 32-entry × 64-bit general-purpose register file (r0..r31).
   - r0 MUST be hardwired to 64'd0 at all times (reads of r0 return 0, writes to r0 are ignored).
   - Dual read ports (raddr1/rdata1, raddr2/rdata2) and single write port (wen, waddr, wdata).
   - Clock and reset: clk, active-low reset rst_ni. Synchronous write on posedge clk when wen && waddr != 5'd0.
   - Internal write-through forwarding: if wen && (waddr == raddr) && (waddr != 5'd0) then rdata = wdata, else read from memory array. If raddr == 5'd0, rdata = 64'd0.
3. core/common/decoder.sv:
   - Decodes 32-bit inst[31:0].
   - Outputs: opcode[3:0], op_group[1:0], rd[4:0], rs1[4:0], rs2[4:0], imm13[12:0], imm64_sext[63:0].
   - Control flags: reg_write, mem_read, mem_write, is_branch, is_jump, is_call, alu_src_imm, illegal_inst.
   - Sign extension of 13-bit immediate to 64-bit: {{51{inst[12]}}, inst[12:0]}.
   - CRITICAL Icarus Verilog 12.0 compatibility: Declare subfield extracts as continuous assignment wires outside always_comb (e.g. wire [3:0] op_w = inst[31:28];) to avoid "sorry: constant selects in always_* processes are not currently supported" warnings.

Verify:
- Compile execution units with iverilog -tnull -g2012 -I include -Wall -Wno-timescale include/soc_pkg.sv core/common/alu.sv core/common/regfile.sv core/common/decoder.sv. Must produce zero warnings and zero errors.
- Write a unit testbench for all 3 primitives and verify 100% of checks pass.
- Write your handoff to /home/tunathefish_b/Code/S-256/.agents/worker_m2/handoff.md. Send a message upon completion.

Exclusive file ownership: core/common/alu.sv, core/common/regfile.sv, core/common/decoder.sv.
