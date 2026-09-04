`timescale 1ns/1ps

package soc_pkg;

    // ========================================================================
    // S-256 Memory Map Allocation
    // ========================================================================
    localparam logic [31:0] CMU_BASE_ADDR           = 32'h1000_0000;
    localparam logic [31:0] CMU_ADDR_MASK           = 32'h0000_0FFF; // 4 KB window
    localparam int          CMU_NUM_DOMAINS         = 5;

    // ========================================================================
    // Clock and Reset Domain Enumeration
    // ========================================================================
    typedef enum logic [2:0] {
        CMU_DOMAIN_SYS  = 3'd0,
        CMU_DOMAIN_MEM  = 3'd1,
        CMU_DOMAIN_RING = 3'd2,
        CMU_DOMAIN_GPU  = 3'd3,
        CMU_DOMAIN_CORE = 3'd4
    } cmu_domain_e;

    // Domain Bitmasks
    localparam logic [4:0] CMU_MASK_SYS             = 5'b00001;
    localparam logic [4:0] CMU_MASK_MEM             = 5'b00010;
    localparam logic [4:0] CMU_MASK_RING            = 5'b00100;
    localparam logic [4:0] CMU_MASK_GPU             = 5'b01000;
    localparam logic [4:0] CMU_MASK_CORE            = 5'b10000;
    localparam logic [4:0] CMU_MASK_ALL             = 5'b11111;

    // ========================================================================
    // Boot Sequencer States
    // ========================================================================
    typedef enum logic [2:0] {
        BOOT_ST_INIT             = 3'b000,
        BOOT_ST_RELEASE_MEM_RING = 3'b001,
        BOOT_ST_RELEASE_GPU      = 3'b010,
        BOOT_ST_RELEASE_CORE     = 3'b011,
        BOOT_ST_RUN              = 3'b100
    } cmu_boot_state_e;

    // ========================================================================
    // CMU CSR Register Offsets (Byte Offsets from CMU_BASE_ADDR)
    // ========================================================================
    localparam logic [11:0] CMU_REG_CTRL            = 12'h000; // Global Control (RW)
    localparam logic [11:0] CMU_REG_STATUS          = 12'h004; // Global Status (RO)
    localparam logic [11:0] CMU_REG_PLL_STATUS      = 12'h008; // Instantaneous PLL Lock Status (RO)
    localparam logic [11:0] CMU_REG_PLL_ERR_STATUS  = 12'h00C; // Sticky Loss-of-Lock Flags (W1C)
    localparam logic [11:0] CMU_REG_PLL_ERR_INT_EN  = 12'h010; // PLL Fault Interrupt Enable (RW)
    localparam logic [11:0] CMU_REG_CLK_GATE_EN     = 12'h014; // Clock Gating Enable (RW)
    localparam logic [11:0] CMU_REG_CLK_BYPASS_SEL  = 12'h018; // Clock Bypass Select (RW)
    localparam logic [11:0] CMU_REG_CLK_BYPASS_STAT = 12'h01C; // Clock Bypass Active Status (RO)
    localparam logic [11:0] CMU_REG_CLK_BYPASS_STATUS = 12'h01C; // Alias for BYPASS_STAT
    localparam logic [11:0] CMU_REG_SYS_CLK_DIV     = 12'h020; // SYS Divider Config (RW)
    localparam logic [11:0] CMU_REG_MEM_CLK_DIV     = 12'h024; // MEM Divider Config (RW)
    localparam logic [11:0] CMU_REG_RING_CLK_DIV    = 12'h028; // RING Divider Config (RW)
    localparam logic [11:0] CMU_REG_GPU_CLK_DIV     = 12'h02C; // GPU Divider Config (RW)
    localparam logic [11:0] CMU_REG_CORE_CLK_DIV    = 12'h030; // CORE Divider Config (RW)
    localparam logic [11:0] CMU_REG_WARM_RST_REQ    = 12'h034; // Warm Reset Trigger (RW)
    localparam logic [11:0] CMU_REG_WARM_RST_BUSY   = 12'h038; // Warm Reset Busy Status (RO)
    localparam logic [11:0] CMU_REG_WARM_RST_LEN    = 12'h03C; // Warm Reset Pulse Length (RW)
    localparam logic [11:0] CMU_REG_BOOT_STATUS     = 12'h040; // Boot FSM Status (RO)
    localparam logic [11:0] CMU_REG_BOOT_STAGE_DLY  = 12'h044; // Boot Stage Delay (RW)
    localparam logic [11:0] CMU_REG_BOOT_STAGE_DELAY = 12'h044; // Alias for BOOT_STAGE_DLY
    localparam logic [11:0] CMU_REG_RESET_STATUS    = 12'h048; // Reset Output Pin Status (RO)
    localparam logic [11:0] CMU_REG_VERSION         = 12'h0FC; // CMU Hardware Version (RO)

    // ========================================================================
    // Bus Response Status Codes
    // ========================================================================
    localparam logic [1:0] COMMS_RESP_OKAY          = 2'b00;
    localparam logic [1:0] COMMS_RESP_SLVERR        = 2'b10;

    // ========================================================================
    // Packed Bitfield Structures
    // ========================================================================
    typedef struct packed {
        logic [22:0] reserved;
        logic        div_update;
        logic [7:0]  div_ratio;
    } cmu_clk_div_reg_t;

    typedef struct packed {
        logic [26:0] reserved;
        logic [4:0]  domain_mask;
    } cmu_domain_mask_reg_t;

    typedef struct packed {
        logic [27:0] reserved;
        logic        warm_rst_active;
        logic        any_pll_err;
        logic        boot_complete;
        logic        all_pll_locked;
    } cmu_status_reg_t;

    typedef struct packed {
        logic [27:0] reserved;
        logic        boot_done;
        logic [2:0]  boot_stage;
    } cmu_boot_status_reg_t;

endpackage
