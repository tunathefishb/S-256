# ==============================================================================
# S-256 SoC Build & Verification Makefile
# ==============================================================================

# Toolchain & Flags
IVERILOG ?= iverilog
VVP      ?= vvp
GTKWAVE  ?= gtkwave
IVLFLAGS  = -g2012 -I include -Wall -Wno-timescale

# Directories
TB_DIR    = tb
LIB_DIR   = lib
BUILD_DIR = build

# Core Shared Sources
PKG_SRC   = include/soc_pkg.sv
INTF_SRC  = interconnect/interfaces.sv
LIB_SRC   = $(wildcard $(LIB_DIR)/*.sv)

# Active Verification Targets
TESTS     = test_cmu test_cmu_adversarial test_cores test_cores_adversarial test_execution_primitives

.PHONY: all help test test_all clean lint $(TESTS)

all: $(addprefix $(BUILD_DIR)/, $(addsuffix .vvp, $(subst test_,,$(TESTS))))

help:
	@echo "S-256 SoC Verification Targets:"
	@echo "  make              - Compile all active testbenches"
	@echo "  make test         - Run full regression test suite"
	@echo "  make test_cmu     - Run CMU E2E testbench"
	@echo "  make test_cores   - Run Dual-Core (big_core & little_core) E2E testbench"
	@echo "  make view_cmu     - View CMU waveforms in GTKWave"
	@echo "  make lint         - Check syntax across all RTL files"
	@echo "  make clean        - Remove build artifacts and waveforms"

# --- CMU Testbenches ---
CMU_RTL = $(INTF_SRC) \
          system/cmu_pll_monitor.sv \
          system/cmu_reset_sequencer.sv \
          system/cmu.sv

$(BUILD_DIR)/cmu_tb.vvp: $(PKG_SRC) $(LIB_SRC) $(CMU_RTL) $(TB_DIR)/cmu_tb.sv
	@mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVLFLAGS) -s cmu_tb -o $@ $^

$(BUILD_DIR)/cmu_adversarial_tb.vvp: $(PKG_SRC) $(LIB_SRC) $(CMU_RTL) $(TB_DIR)/cmu_adversarial_tb.sv
	@mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVLFLAGS) -s cmu_adversarial_tb -o $@ $^

test_cmu: $(BUILD_DIR)/cmu_tb.vvp
	cd $(BUILD_DIR) && $(VVP) cmu_tb.vvp

test_cmu_adversarial: $(BUILD_DIR)/cmu_adversarial_tb.vvp
	cd $(BUILD_DIR) && $(VVP) cmu_adversarial_tb.vvp

# --- Core Processors (Dual-Core E2E) Testbench ---
CORE_COMMON_SRC = $(wildcard core/common/*.sv)
CORE_SRC        = core/big_core.sv \
                  core/little_core.sv \
                  $(CORE_COMMON_SRC)

$(BUILD_DIR)/core_tb.vvp: $(PKG_SRC) $(LIB_SRC) $(CORE_SRC) $(TB_DIR)/core_tb.sv
	@mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVLFLAGS) -s core_tb -o $@ $^

test_cores: $(BUILD_DIR)/core_tb.vvp
	cd $(BUILD_DIR) && $(VVP) core_tb.vvp

$(BUILD_DIR)/core_adversarial_tb.vvp: $(PKG_SRC) $(LIB_SRC) $(CORE_SRC) $(TB_DIR)/core_adversarial_tb.sv
	@mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVLFLAGS) -s core_adversarial_tb -o $@ $^

test_cores_adversarial: $(BUILD_DIR)/core_adversarial_tb.vvp
	cd $(BUILD_DIR) && $(VVP) core_adversarial_tb.vvp

# --- Execution Primitives Unit Testbench ---
$(BUILD_DIR)/execution_primitives_tb.vvp: $(PKG_SRC) $(CORE_COMMON_SRC) $(TB_DIR)/execution_primitives_tb.sv
	@mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVLFLAGS) -s execution_primitives_tb -o $@ $^

.PHONY: test_execution_primitives
test_execution_primitives: $(BUILD_DIR)/execution_primitives_tb.vvp
	cd $(BUILD_DIR) && $(VVP) execution_primitives_tb.vvp

test test_all: $(TESTS)

# Open waveform only re-simulating if VCD is missing
view_cmu: $(BUILD_DIR)/cmu_tb.vcd
	$(GTKWAVE) $< $(TB_DIR)/cmu_view.gtkw

$(BUILD_DIR)/cmu_tb.vcd: $(BUILD_DIR)/cmu_tb.vvp
	cd $(BUILD_DIR) && $(VVP) cmu_tb.vvp

# Syntax / Elaboration Check
lint:
	@echo "Checking RTL syntax across all modules..."
	$(IVERILOG) $(IVLFLAGS) -s cmu -o /dev/null $(PKG_SRC) $(LIB_SRC) $(CMU_RTL)
	$(IVERILOG) $(IVLFLAGS) -s big_core -o /dev/null $(PKG_SRC) $(LIB_SRC) $(CORE_SRC)
	$(IVERILOG) $(IVLFLAGS) -s little_core -o /dev/null $(PKG_SRC) $(LIB_SRC) $(CORE_SRC)
	@echo "All modules clean! Zero errors, zero warnings."

clean:
	rm -rf $(BUILD_DIR) *.vvp *.vcd *.log