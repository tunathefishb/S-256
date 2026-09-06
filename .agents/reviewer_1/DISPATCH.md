# Dispatch: Reviewer 1

Your working directory: /home/tunathefish_b/Code/S-256/.agents/reviewer_1
Original Request path: /home/tunathefish_b/Code/S-256/.agents/ORIGINAL_REQUEST.md
PROJECT.md path: /home/tunathefish_b/Code/S-256/PROJECT.md
TEST_INFRA.md path: /home/tunathefish_b/Code/S-256/TEST_INFRA.md
TEST_READY.md path: /home/tunathefish_b/Code/S-256/TEST_READY.md

Task:
Perform independent, rigorous code review and verification of the S-256 baseline core implementation:
1. Review:
   - `include/soc_pkg.sv`: ISA opcodes, groups, `inst_t`, `alu_flags_t`, constants. Verify preservation of CMU registers and parameters.
   - `core/common/alu.sv`, `core/common/regfile.sv`, `core/common/decoder.sv`: Synthesizability, correctness, r0 hardwiring to 0, write-through forwarding, sign-extension, zero compiler warnings with `-Wall`.
   - `core/big_core.sv` and `core/little_core.sv`: Dual-core parity, single-cycle datapath, reset discipline (`rst_ni` active-low), branch/call/jump logic, memory interfaces.
2. Execute builds and tests:
   - Run `make test_cores` (must build cleanly with `iverilog -g2012 -I include -Wall -Wno-timescale` and pass 100% of checks with zero failures and zero parity errors).
   - Run `make test_execution_primitives`.
   - Run `make test_cmu` and `make test_cmu_adversarial` to verify zero regression across the SoC.
3. Determine verdict: APPROVE or REQUEST_CHANGES.
4. Write your review to `/home/tunathefish_b/Code/S-256/.agents/reviewer_1/review.md` and handoff to `/home/tunathefish_b/Code/S-256/.agents/reviewer_1/handoff.md`.
