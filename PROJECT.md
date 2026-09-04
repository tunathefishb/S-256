# Project: S-256 CMU Hardening & Upgrade

## Architecture
The S-256 Clock and Reset Management Unit (CMU) is responsible for generating, dividing, multiplexing, and gating clocks across 5 independent SoC domains (`clk_sys`, `clk_mem`, `clk_ring`, `clk_gpu`, `clk_core`), and executing deterministic staged reset release and domain-isolated software warm resets.

```
                                  +---------------------------------------------+
                                  |                   CMU Top                   |
                                  |                                             |
   clk_in (100MHz Ref Osc) ------>+-----> [clk_sys Divider & ICG] -------------> clk_sys
   rst_ni (Async Hard Reset) ---->+                                             rst_sys_ni
                                  |                                             
                                  |   +-------------------------------------+   
   comms_bus_if (via bus ports) ->+-->|               CSR File              |   
                                  |   +--+----------+----------+----------+-+   
                                  |      |          |          |          |     
                                  |      v          v          v          v     
                                  |   [Div Cfg] [Gate En] [Src Sel] [Warm Rst]  
                                  |      |          |          |          |     
                                  |      |  +-------+----------+          |     
                                  |      |  |                             |     
                                  |   +--v--v-----------+                 |     
                                  |   | PLL Monitors    |<-- PLL Lock     |     
                                  |   | Loss-of-Lock    |                 |     
                                  |   +--------+--------+                 |     
                                  |            |                          |     
                                  |            v (Force Bypass)           |     
                                  |   +--------+--------+                 |     
                                  |   | Glitch-Free Mux |                 |     
                                  |   +--------+--------+                 |     
                                  |            |                          |     
                                  |            v                          |     
                                  |   +--------+--------+                 |     
                                  |   | Dynamic Divider |                 |     
                                  |   +--------+--------+                 |     
                                  |            |                          |     
                                  |            v                          |     
                                  |   +--------+--------+                 |     
                                  |   | Flop-Based ICG  +---------------> clk_domain
                                  |   +-----------------+                       
                                  |                                             
                                  |   +-------------------------------------+   
                                  |   | Sequenced Reset Controller          |   
                                  |   | (Hard rst + FSM Release + Warm Rst) |   
                                  |   +------------------+------------------+   
                                  |                      |                      
                                  |                      v                      
                                  |            [Domain reset_sync] -------------> rst_domain_ni
                                  +---------------------------------------------+
```

### Key Architectural Decisions
1. **Glitch-Free Clock Multiplexing (GFMUX)**: Negative-edge dual-flop feedback handshaking with dual-stage interlock (`(~sync1) & (~sync2)`) and dead-clock override counter on `clk0` to prevent deadlocks when a PLL halts high.
2. **Integrated Clock Gating (ICG)**: Negative-edge flop-based clock gating (`always_ff @(negedge clk)`) guaranteeing zero runt pulses, zero inferred latches, and clean linting under `iverilog -g2012 -Wall`.
3. **Dynamic Clock Division**: Terminal-count shadow latching and internal glitch-free bypass mux for seamless frequency scaling ($N=1..64$).
4. **PLL Lock Monitoring**: 2-stage synchronization, debounce filtering, instantaneous loss-of-lock fallback, and W1C sticky error flags.
5. **Deterministic Staged Boot**: Interconnect/Memory $\rightarrow$ GPU $\rightarrow$ CPU Cores with configurable stage transition delays (`CMU_BOOT_STAGE_DELAY`), fixing the observed race where Core exited reset prematurely.
6. **Isolated Warm Reset**: 16-cycle pulse-stretched reset assertion per domain, without interfering with unselected domains.
7. **Toolchain Compatibility**: SystemVerilog 2012 IEEE standard, discrete bus ports on `cmu` matching `comms_bus_if` signals to maintain strict compatibility with `iverilog 12.0`.

---

## Feature Inventory
| # | Feature | Description | Milestone | Source | Status |
|---|---------|-------------|-----------|--------|:------:|
| 1 | Multi-Domain Clock Distribution | Generate 5 domain clocks (`clk_sys`, `clk_mem`, `clk_ring`, `clk_gpu`, `clk_core`) | M_IMPL | R1, survey | **VERIFIED** |
| 2 | Glitch-Free Clock Multiplexing (GFMUX) | Dual-flop handshake + dual-stage interlock + dead-clock override | M_IMPL | R1, R3, survey | **VERIFIED** |
| 3 | Dynamic Clock Dividers | Integer division ($N=1..64$) with terminal-count shadow latching | M_IMPL | R1, survey | **VERIFIED** |
| 4 | Glitch-Free Integrated Clock Gating (ICG) | Flop-based negative-edge ICG cells for clean low-power clock gating | M_IMPL | R2, survey | **VERIFIED** |
| 5 | SoC Package Definitions | Domain enums, bitmasks, FSM states, register offsets, bitfield structs | M_IMPL | R4, survey | **VERIFIED** |
| 6 | Interconnect Interface Extension | `comms_bus_if` read/write memory-mapped signal extensions | M_IMPL | R4, survey | **VERIFIED** |
| 7 | PLL Lock Monitoring & Debounce | 2-stage synchronization and debounce filtering for all domain PLL locks | M_IMPL | R3, survey | **VERIFIED** |
| 8 | Instantaneous Loss-of-Lock Fallback | Auto-switch affected domain GFMUX to `clk_in` on loss of lock | M_IMPL | R3, survey | **VERIFIED** |
| 9 | Sticky Loss-of-Lock Error Flags | W1C latched fault flags in CSR for transient/permanent PLL faults | M_IMPL | R3, survey | **VERIFIED** |
| 10 | Sequenced Domain Boot Controller | Staged reset release (MEM/RING $\rightarrow$ GPU $\rightarrow$ CORE) with configurable delays | M_IMPL | R5, survey | **VERIFIED** |
| 11 | Domain-Isolated Software Warm Reset | Targetable 16-cycle warm reset pulse per domain leaving other domains running | M_IMPL | R5, survey | **VERIFIED** |
| 12 | Memory-Mapped CSR Register File | 20 registers across 4 KB aperture at `0x1000_0000` via bus interface | M_IMPL | R4, survey | **VERIFIED** |
| 13 | Global Gate & Bypass Controls | Software override and manual bypass selection via CSRs | M_IMPL | R2, R4, survey | **VERIFIED** |
| 14 | Top-Level Integration & Wiring | Complete `system/cmu.sv` wiring and Makefile build integration | M_IMPL | R1-R5, survey | **VERIFIED** |
| 15 | E2E Testbench Infrastructure | Self-checking monitors, frequency measurement, runt pulse detection | M_E2E | Criteria, survey | **VERIFIED** |
| 16 | E2E Test Suite (Tiers 1-4) | Comprehensive test coverage across all requirements and corner cases (152 checks) | M_E2E | Criteria, survey | **VERIFIED** |
| 17 | Final Acceptance & Coverage Hardening | 100% E2E test pass + adversarial coverage hardening (Tier 5, 90 checks) | M_FINAL | Criteria, survey | **VERIFIED** |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|:------:|
| M_IMPL | CMU RTL Implementation Track | `include/soc_pkg.sv`, `interconnect/interfaces.sv`, `lib/glitch_free_clock_mux.sv`, `lib/clock_divider.sv`, `lib/clock_gater.sv`, `system/cmu_pll_monitor.sv`, `system/cmu_reset_sequencer.sv`, `system/cmu.sv`, `Makefile` | none | **DONE** |
| M_E2E | E2E Testing Track | `TEST_INFRA.md`, `tb/cmu_tb.sv` (Tiers 1-4), `TEST_READY.md` | none | **DONE** |
| M_FINAL | Dual Track Convergence & Hardening | Verify 100% passing E2E suite, 2 Reviewers, 2 Challengers (Tier 5), 1 Forensic Auditor | M_IMPL, M_E2E | **DONE** |

---

## Interface Contracts

### 1. `include/soc_pkg.sv`
- Base Address: `CMU_BASE_ADDR = 32'h1000_0000`
- Register offsets: `0x000` (`CMU_REG_CTRL`) through `0x048` (`CMU_REG_RESET_STATUS`), `0x0FC` (`CMU_REG_VERSION`)
- Domain mask: Bit 0=SYS, 1=MEM, 2=RING, 3=GPU, 4=CORE
- Enums: `cmu_domain_e`, `cmu_boot_state_e`
- Response codes: `COMMS_RESP_OKAY = 2'b00`, `COMMS_RESP_SLVERR = 2'b10`

### 2. `interconnect/interfaces.sv` (`comms_bus_if`)
```systemverilog
interface comms_bus_if (input logic clk);
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic        wen;
    logic        ren;
    logic        valid;
    logic        ready;
    logic [1:0]  resp;
    logic [31:0] cmd; // Legacy compatibility
    modport master (input clk, ready, rdata, resp, output addr, wdata, wen, ren, valid, cmd);
    modport slave  (input clk, addr, wdata, wen, ren, valid, cmd, output ready, rdata, resp);
endinterface
```

### 3. CMU Top-Level Port Contract (`system/cmu.sv`)
```systemverilog
module cmu (
    input  logic        clk_in,
    input  logic        rst_ni,
    // Discrete bus ports matching comms_bus_if (for iverilog compatibility)
    input  logic [31:0] bus_addr,
    input  logic [31:0] bus_wdata,
    input  logic        bus_wen,
    input  logic        bus_ren,
    input  logic        bus_valid,
    output logic        bus_ready,
    output logic [31:0] bus_rdata,
    output logic [1:0]  bus_resp,
    // Clock & Synchronized Reset Outputs
    output logic        clk_sys,  rst_sys_ni,
    output logic        clk_mem,  rst_mem_ni,
    output logic        clk_ring, rst_ring_ni,
    output logic        clk_gpu,  rst_gpu_ni,
    output logic        clk_core, rst_core_ni
);
```

### 4. Primitives Contracts (`lib/` & `system/`)
- `glitch_free_clock_mux (clk0, rst_clk0_ni, clk1, rst_clk1_ni, sel, force_bypass, clk_out)`
- `clock_divider #(MAX_DIV) (clk_in, rst_ni, div_val[7:0], clk_out)`
- `clock_gater (clk_in, rst_ni, enable, test_en, clk_out)`
- `cmu_pll_monitor #(DEBOUNCE_CYCLES) (clk_sys, rst_sys_ni, pll_locked_raw, clear_sticky_err, pll_locked_sync, loss_of_lock_sticky, force_bypass)`
- `cmu_reset_sequencer (clk_sys, rst_sys_ni, rst_ni, all_plls_locked, cfg_delay_mem_to_gpu, cfg_delay_gpu_to_core, req_warm_rst_*, fsm_release_*, warm_rst_busy_*, boot_state, boot_done)`

---

## Code Layout
- `include/soc_pkg.sv`: Global package definitions (VERIFIED)
- `interconnect/interfaces.sv`: Bus interfaces (VERIFIED)
- `lib/glitch_free_clock_mux.sv`: Glitch-free multiplexer with dead-clock override (VERIFIED)
- `lib/clock_divider.sv`: Dynamic integer clock divider (VERIFIED)
- `lib/clock_gater.sv`: Flop-based Integrated Clock Gating (VERIFIED)
- `system/cmu_pll_monitor.sv`: PLL monitor & loss-of-lock detector (VERIFIED)
- `system/cmu_reset_sequencer.sv`: Staged reset sequencer & warm reset (VERIFIED)
- `system/cmu.sv`: Top-level CMU module (VERIFIED)
- `Makefile`: Build rules and target test_cmu (VERIFIED)
- `tb/cmu_tb.sv`: Comprehensive verification testbench (VERIFIED)
- `TEST_READY.md`: E2E suite readiness signal (VERIFIED)
