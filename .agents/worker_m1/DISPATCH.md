## 2026-09-06T11:22:26Z

You are teamwork_preview_worker implementing Milestone 1 (ISA definition in include/soc_pkg.sv).
Your working directory: /home/tunathefish_b/Code/S-256/.agents/worker_m1
Original Request path: /home/tunathefish_b/Code/S-256/.agents/ORIGINAL_REQUEST.md
PROJECT.md path: /home/tunathefish_b/Code/S-256/PROJECT.md
Explorer reports:
- /home/tunathefish_b/Code/S-256/.agents/spec_miner_survey/spec_analysis.md
- /home/tunathefish_b/Code/S-256/.agents/explorer_survey_1/analysis.md
- /home/tunathefish_b/Code/S-256/.agents/explorer_survey_2/analysis.md

Task:
Implement Milestone 1:
- Append the 16-instruction orthogonal RISC ISA definitions to include/soc_pkg.sv:
  - op_group_e: OP_GROUP_ARITH (2'b00), OP_GROUP_LOGIC (2'b01), OP_GROUP_MEM (2'b10), OP_GROUP_CTRL (2'b11)
  - opcode_e: ADD (4'b0000), SUB (4'b0001), SHL (4'b0010), SHR (4'b0011), AND (4'b0100), OR (4'b0101), XOR (4'b0110), NOT (4'b0111), LOAD (4'b1000), STORE (4'b1001), MOV (4'b1010), LDI (4'b1011), BEQ (4'b1100), BNE (4'b1101), CALL (4'b1110), JMP (4'b1111)
  - inst_t packed struct: opcode[3:0] (bits 31:28), rd[4:0] (bits 27:23), rs1[4:0] (bits 22:18), rs2[4:0] (bits 17:13), imm13[12:0] (bits 12:0)
  - alu_flags_t packed struct: zero, negative, carry, overflow
  - Architecture parameters: XLEN = 64, ILEN = 32, NUM_GPR = 32
- PRESERVE all existing CMU parameters, register maps, and structs in include/soc_pkg.sv.
- Verify compilation with iverilog -g2012 -I include -Wall -Wno-timescale include/soc_pkg.sv and run make test_cmu to ensure no regression.
- Exclusive file ownership: include/soc_pkg.sv.
- Write your completion report to /home/tunathefish_b/Code/S-256/.agents/worker_m1/handoff.md. Send a message upon completion.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
