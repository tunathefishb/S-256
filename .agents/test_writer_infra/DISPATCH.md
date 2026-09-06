## 2026-09-06T11:22:26Z

You are teamwork_preview_test_writer building the E2E verification infrastructure and testsuite.
Your working directory: /home/tunathefish_b/Code/S-256/.agents/test_writer_infra
Original Request path: /home/tunathefish_b/Code/S-256/.agents/ORIGINAL_REQUEST.md
PROJECT.md path: /home/tunathefish_b/Code/S-256/PROJECT.md
Explorer reports:
- /home/tunathefish_b/Code/S-256/.agents/spec_miner_survey/spec_analysis.md
- /home/tunathefish_b/Code/S-256/.agents/explorer_survey_1/analysis.md
- /home/tunathefish_b/Code/S-256/.agents/explorer_survey_2/analysis.md

Task:
1. Create TEST_INFRA.md at project root (/home/tunathefish_b/Code/S-256/TEST_INFRA.md) following the 4-tier methodology:
   - Tier 1: Feature Coverage (>=5 tests per feature across all 16 instructions)
   - Tier 2: Boundary & Corner Cases (>=5 tests per feature, e.g. 64-bit max/min/overflow/underflow, r0 hardwiring, sign extension boundary)
   - Tier 3: Cross-Feature Combinations (pairwise interactions: arithmetic->logic, store->load RAW hazard, call->ret)
   - Tier 4: Real-World Application Scenarios (loop iterations, factorial/fibonacci, function call nesting)
2. Implement tb/core_tb.sv:
   - Instantiates BOTH big_core and little_core (dual-core verification).
   - Simulates Harvard memory (imem with instructions, dmem with read/write RAM).
   - Drives active-low reset rst_ni according to S-256 reset discipline.
   - Tests all 16 instructions individually on 64-bit operands.
   - Verifies register persistence, r0 hardwiring to 0, data hazard forwarding.
   - Verifies branch/call/jump targets, call link register r31 (or rd), return via JMP r31, 0.
   - Executes end-to-end sample program with loop and subroutine call.
   - Reports pass/fail count; displays TEST PASSED only when 100% of checks pass with 0 failures.
3. Update Makefile:
   - Add test_cores target using iverilog -g2012 -I include -Wall -Wno-timescale and vvp.
4. When finished, create TEST_READY.md at project root (/home/tunathefish_b/Code/S-256/TEST_READY.md) summarizing test runner, tier counts, and checklist.
5. Write your handoff to /home/tunathefish_b/Code/S-256/.agents/test_writer_infra/handoff.md. Send a message upon completion.

Exclusive file ownership: TEST_INFRA.md, TEST_READY.md, tb/core_tb.sv, Makefile.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All test implementations must be genuine. Do not hardcode trivial passes or bypass checks.
