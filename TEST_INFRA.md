# E2E Test Infra: S-256 CMU

## Test Philosophy
- Opaque-box, requirement-driven verification derived from `ORIGINAL_REQUEST.md`.
- Methodology: Category-Partition + Boundary Value Analysis + Pairwise Interaction + Real-World Scenario Testing.
- Toolchain: Icarus Verilog 12.0 (`iverilog -g2012 -I include -Wall`) + `vvp`.
- Zero-tolerance error handling: Any assertion failure terminates simulation with non-zero exit code (`$fatal(1, ...)`).

## Feature Inventory
| # | Feature | Source | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---|---------|--------|:------:|:------:|:------:|:------:|
| 1 | Multi-domain clock generation (5 domains) | R1 | 5 | 5 | ✓ | ✓ |
| 2 | Glitch-free clock switching (GFMUX) | R1, R3 | 5 | 5 | ✓ | ✓ |
| 3 | Dynamic clock division ($N=1..64$) | R1 | 5 | 5 | ✓ | ✓ |
| 4 | Dynamic clock gating (ICG) | R2 | 5 | 5 | ✓ | ✓ |
| 5 | PLL lock monitoring & safe bypass fallback | R3 | 5 | 5 | ✓ | ✓ |
| 6 | Software CSR read/write via `comms_bus_if` | R4 | 5 | 5 | ✓ | ✓ |
| 7 | Sequenced cold boot with stage delays | R5 | 5 | 5 | ✓ | ✓ |
| 8 | Subsystem-isolated software warm resets | R5 | 5 | 5 | ✓ | ✓ |

## Test Architecture
- **Location**: `tb/cmu_tb.sv`
- **Invocation**: `make test_cmu` (or `cd build && vvp cmu_tb.vvp`)
- **Key Checker Primitives**:
  - `freq_monitor`: Measures clock frequency, period, and duty cycle (within 50% $\pm 5\%$).
  - `runt_monitor`: Continuously checks that all positive and negative clock pulse widths are $\ge \text{period}/2 - \epsilon$ (minimum 4.9 ns for 100MHz).
  - `boot_seq_monitor`: Asserts strict ordering: $T(\text{rst\_mem}) < T(\text{rst\_gpu}) < T(\text{rst\_core})$.
  - `csr_bfm`: Bus functional tasks `csr_write(addr, data)` and `csr_read(addr, data)` using `comms_bus_if` protocol.
  - `warm_rst_monitor`: Verifies that triggering warm reset on domain $X$ asserts `rst_X_ni` while unselected domains $Y$ experience zero glitches or interruptions.
  - `pll_fault_injector`: Emulates runtime loss of PLL lock via hierarchical force/release on lock signals.

## Test Tiers Breakdown
- **Tier 1: Feature Coverage (>=5 per feature)**:
  - Cold power-on boot sequence
  - CSR read/write operations (walking 1s, register identity)
  - Domain clock generation at default frequencies
  - Dynamic clock gating enable/disable in isolation
  - Dynamic divider configuration in isolation
  - Manual bypass switching
  - PLL loss-of-lock detection in isolation
  - Single-domain warm reset trigger
- **Tier 2: Boundary & Corner Cases (>=5 per feature)**:
  - Divider boundary cases: $N=0$ (clamped to 1), $N=1$ (bypass), $N=2$ (even), $N=3$ (odd), $N=64$ (max)
  - Clock gating while clock is high vs clock is low (ICG latch behavior)
  - Clock source switching while both clocks are high vs low
  - PLL loss-of-lock during cold boot (`ST_INIT`) vs during normal run (`ST_RUN`)
  - Back-to-back warm reset writes while reset is already busy
  - Unmapped CSR address read/write returning `SLVERR`
  - Clearing sticky PLL fault while PLL is still unlocked
- **Tier 3: Cross-Feature Combinations (Pairwise)**:
  - Dynamic frequency scaling while clock gate is disabled
  - Warm reset of GPU domain while CPU core is actively reading CSRs
  - PLL loss-of-lock fallback during active dynamic clock division
  - Dynamic clock gating toggle during PLL fallback mode
  - Modifying boot stage delays before warm reset
- **Tier 4: Real-World Application Scenarios**:
  - Full cold boot sequence with non-zero programmed stage delays
  - Runtime dynamic frequency scaling under continuous clock activity
  - PLL catastrophic failure, automatic safe bypass fallback, fault status inspection, PLL recovery, and sticky flag clear
  - Standby low-power entry (gating all peripheral clocks, preserving SYS) and wake-up
  - Selective CPU cluster warm reset while memory controller and ring bus remain running

## Coverage Thresholds
- Tier 1: $\ge 40$ test assertions (5 per feature across 8 features)
- Tier 2: $\ge 40$ test assertions
- Tier 3: $\ge 8$ pairwise cross-feature scenarios
- Tier 4: $\ge 5$ realistic multi-module application workflows
- **Total Minimum Test Cases/Checks**: $> 90$ checks, 100% pass rate.
