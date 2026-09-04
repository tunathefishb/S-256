# Makefile for S-256 SoC RTL Testbenches

# Toolchain
IVERILOG = iverilog
VVP = vvp

# Compilation Flags
# -g2012: Enable SystemVerilog 2012 features
# -I include: Add include directory to search path
IVLFLAGS = -g2012 -I include -Wall -Wno-timescale

# Directories
TB_DIR = tb
LIB_DIR = lib
BUILD_DIR = build

# Global Package Sources (included in most compilations)
PKG_SRC = include/soc_pkg.sv

# Interconnect Interface Sources
INTF_SRC = interconnect/interfaces.sv

# Global Library Sources (utility modules used across the SoC)
LIB_SRC = $(wildcard $(LIB_DIR)/*.sv)

# ==============================================================================
# Testbench Definitions
# ==============================================================================

# Default target
.PHONY: all clean
all: test_cmu

# --- CMU Testbench ---
CMU_SRC = $(INTF_SRC) \
          system/cmu_pll_monitor.sv \
          system/cmu_reset_sequencer.sv \
          system/cmu.sv
CMU_TB  = $(TB_DIR)/cmu_tb.sv

.PHONY: test_cmu
test_cmu: $(BUILD_DIR)/cmu_tb.vvp
	cd $(BUILD_DIR) && $(VVP) cmu_tb.vvp

$(BUILD_DIR)/cmu_tb.vvp: $(PKG_SRC) $(LIB_SRC) $(CMU_SRC) $(CMU_TB)
	@mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVLFLAGS) -s cmu_tb -o $@ $^

# Cleanup
clean:
	rm -rf $(BUILD_DIR) *.vvp *.vcd
