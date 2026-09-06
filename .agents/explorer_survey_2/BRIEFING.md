# BRIEFING — 2026-09-06T11:21:45Z

## Mission
Investigate S-256 baseline core architecture & microarchitecture details (64-bit ALU, RF, decoder, control flow, memory ops, iverilog compatibility) and produce comprehensive analysis and handoff reports.

## 🔒 My Identity
- Archetype: teamwork_preview_explorer
- Roles: Datapath & Architecture Explorer 2
- Working directory: /home/tunathefish_b/Code/S-256/.agents/explorer_survey_2
- Original parent: 48e3166a-75d8-42d0-ac6b-1648d4434b84
- Milestone: baseline core architecture survey

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Do NOT modify source code files in S-256 repository directly (only write within own .agents directory)
- Do NOT run python3 scripts/generate_stubs.py
- Adhere to SystemVerilog 2012 (iverilog -g2012) compatibility requirements
- Use Files for content delivery, Messages for coordination

## Current Parent
- Conversation ID: 48e3166a-75d8-42d0-ac6b-1648d4434b84
- Updated: 2026-09-06T11:21:45Z

## Investigation State
- **Explored paths**: `include/soc_pkg.sv`, `core/big_core.sv`, `core/little_core.sv`, `subsystems/compute_cluster.sv`, `interconnect/interfaces.sv`, `Makefile`, `lib/`, `tb/`, `explorer_survey_1/analysis.md`
- **Key findings**:
  - Unified 32-bit instruction format: opcode[31:28], rd[27:23], rs1[22:18], rs2[17:13], imm13[12:0].
  - 64-bit ALU operations, flags (Z, N, C, V), and 6-bit shift masking `rs2[5:0]`.
  - Register file 32x64 with hardwired `r0=0` (write suppression + read clamp) and internal write-through forwarding.
  - Decoder control signal table and sign extension `{{51{inst[12]}}, inst[12:0]}`.
  - Subroutine linking to `r31` (or `rd`), and subroutine return (`RET`) executed via `JMP r31, 0`.
  - Memory access 64-bit aligned doublewords with `wstrb[7:0]` byte strobes and Harvard core interface.
  - Critical Icarus Verilog 12.0 footgun resolved: bit-slicing inside `always_comb` sensitivity triggers `sorry: constant selects in always_*`; pre-slicing into `wire` declarations guarantees 0 warnings under `-Wall`.
- **Unexplored areas**: None. Architectural blueprint complete for M1-M4.

## Key Decisions Made
- Selected deterministic single-cycle execution engine as core baseline, eliminating pipeline hazards while designing execution primitives in `core/common/` to be 100% reusable for future pipelined iterations.
- Established `JMP` address formulation: `(rs1 != 0) ? (R[rs1] + sext(imm13)) : (PC + (sext(imm13) << 2))` to natively unify relative jumps and register returns.
- Mandated pre-sliced continuous assignment wires for all bit-slicing before `always_comb` blocks.

## Artifact Index
- .agents/explorer_survey_2/DISPATCH.md — Received task instructions
- .agents/explorer_survey_2/BRIEFING.md — Working memory & identity
- .agents/explorer_survey_2/progress.md — Liveness & heartbeat
- .agents/explorer_survey_2/analysis.md — Comprehensive architectural analysis report
- .agents/explorer_survey_2/handoff.md — 5-component handoff report
