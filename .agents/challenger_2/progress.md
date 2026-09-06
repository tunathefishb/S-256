# Progress: Challenger 2

Last visited: 2026-09-06T11:34:30Z
Status: Investigating codebase, architecture, core RTL, and test infrastructure.

## Plan
1. [x] Initialize BRIEFING.md, DISPATCH.md, progress.md.
2. [ ] Read PROJECT.md, TEST_INFRA.md, ORIGINAL_REQUEST.md, Makefile, and RTL files in `core/` and `tb/`.
3. [ ] Run existing tests (`make test_cores`, etc.) to establish baseline.
4. [ ] Design and implement adversarial stress testbench (`tb/core_stress_tb.sv`):
   - Control flow stress (multi-iteration loops, alternating BEQ/BNE, forward jumps, backward branches).
   - Deep subroutine call/return nesting (r29 as SP, depth >= 8, verifying return addresses).
   - RAW Memory hazards (immediate STORE -> LOAD on same address, adjacent addresses, 64-bit boundaries).
   - Dual-core lockstep stress (big_core vs little_core parity under branch/call/memory workloads).
5. [ ] Execute tests with iverilog and vvp; collect empirical findings.
6. [ ] Formulate verdict (APPROVE or REQUEST_CHANGES).
7. [ ] Generate adversarial_report.md and handoff.md.
8. [ ] Send message to parent.
