`timescale 1ns/1ps

module cmu (
    input  logic        clk_in,
    input  logic        rst_ni,

    // Discrete bus ports matching comms_bus_if (for iverilog compatibility)
    input  logic [31:0] bus_addr  = 32'h0,
    input  logic [31:0] bus_wdata = 32'h0,
    input  logic        bus_wen   = 1'b0,
    input  logic        bus_ren   = 1'b0,
    input  logic        bus_valid = 1'b0,
    output logic        bus_ready,
    output logic [31:0] bus_rdata,
    output logic [1:0]  bus_resp,

    // Clock and Synchronized Reset Outputs
    output logic        clk_sys,  rst_sys_ni,
    output logic        clk_mem,  rst_mem_ni,
    output logic        clk_ring, rst_ring_ni,
    output logic        clk_gpu,  rst_gpu_ni,
    output logic        clk_core, rst_core_ni
);

    import soc_pkg::*;

    // =========================================================================
    // 1. PLL Subsystem
    // =========================================================================
    logic pll_clk_mem,  pll_mem_locked_raw;
    wire  pll_mem_locked = pll_mem_locked_raw;

    logic pll_clk_ring, pll_ring_locked_raw;
    wire  pll_ring_locked = pll_ring_locked_raw;

    logic pll_clk_gpu,  pll_gpu_locked_raw;
    wire  pll_gpu_locked = pll_gpu_locked_raw;

    logic pll_clk_core, pll_core_locked_raw;
    wire  pll_core_locked = pll_core_locked_raw;

    generic_pll #(.DIVIDER(1)) u_pll_mem (
        .clk_in  (clk_in),
        .rst_ni  (rst_ni),
        .clk_out (pll_clk_mem),
        .locked  (pll_mem_locked_raw)
    );

    generic_pll #(.DIVIDER(1)) u_pll_ring (
        .clk_in  (clk_in),
        .rst_ni  (rst_ni),
        .clk_out (pll_clk_ring),
        .locked  (pll_ring_locked_raw)
    );

    generic_pll #(.DIVIDER(1)) u_pll_gpu (
        .clk_in  (clk_in),
        .rst_ni  (rst_ni),
        .clk_out (pll_clk_gpu),
        .locked  (pll_gpu_locked_raw)
    );

    generic_pll #(.DIVIDER(1)) u_pll_core (
        .clk_in  (clk_in),
        .rst_ni  (rst_ni),
        .clk_out (pll_clk_core),
        .locked  (pll_core_locked_raw)
    );

    // =========================================================================
    // 2. Base System Reset Synchronizer for Internal Operations
    // =========================================================================
    logic rst_sys_async_n;
    logic rst_sys_internal_n;

    reset_sync #(.STAGES(2)) u_sys_rst_sync (
        .clk        (clk_in),
        .rst_ni     (rst_sys_async_n),
        .rst_sync_no(rst_sys_internal_n)
    );

    assign rst_sys_ni = rst_sys_internal_n;

    // =========================================================================
    // 3. PLL Lock Monitors & Loss-of-Lock Fallback
    // =========================================================================
    logic [4:0] pll_locked_sync;
    logic [4:0] loss_of_lock_sticky;
    logic [4:0] pll_force_bypass;
    logic [4:0] clear_sticky_err_pulse;

    // Domain 0 (SYS) is always driven by safe reference oscillator
    assign pll_locked_sync[0]     = 1'b1;
    assign loss_of_lock_sticky[0] = 1'b0;
    assign pll_force_bypass[0]    = 1'b0;

    cmu_pll_monitor #(.DEBOUNCE_CYCLES(8)) u_mon_mem (
        .clk_sys            (clk_in),
        .rst_sys_ni         (rst_sys_internal_n),
        .pll_locked_raw     (pll_mem_locked),
        .clear_sticky_err   (clear_sticky_err_pulse[1]),
        .pll_locked_sync    (pll_locked_sync[1]),
        .loss_of_lock_sticky(loss_of_lock_sticky[1]),
        .force_bypass       (pll_force_bypass[1])
    );

    cmu_pll_monitor #(.DEBOUNCE_CYCLES(8)) u_mon_ring (
        .clk_sys            (clk_in),
        .rst_sys_ni         (rst_sys_internal_n),
        .pll_locked_raw     (pll_ring_locked),
        .clear_sticky_err   (clear_sticky_err_pulse[2]),
        .pll_locked_sync    (pll_locked_sync[2]),
        .loss_of_lock_sticky(loss_of_lock_sticky[2]),
        .force_bypass       (pll_force_bypass[2])
    );

    cmu_pll_monitor #(.DEBOUNCE_CYCLES(8)) u_mon_gpu (
        .clk_sys            (clk_in),
        .rst_sys_ni         (rst_sys_internal_n),
        .pll_locked_raw     (pll_gpu_locked),
        .clear_sticky_err   (clear_sticky_err_pulse[3]),
        .pll_locked_sync    (pll_locked_sync[3]),
        .loss_of_lock_sticky(loss_of_lock_sticky[3]),
        .force_bypass       (pll_force_bypass[3])
    );

    cmu_pll_monitor #(.DEBOUNCE_CYCLES(8)) u_mon_core (
        .clk_sys            (clk_in),
        .rst_sys_ni         (rst_sys_internal_n),
        .pll_locked_raw     (pll_core_locked),
        .clear_sticky_err   (clear_sticky_err_pulse[4]),
        .pll_locked_sync    (pll_locked_sync[4]),
        .loss_of_lock_sticky(loss_of_lock_sticky[4]),
        .force_bypass       (pll_force_bypass[4])
    );

    wire all_plls_locked = pll_locked_sync[1] & pll_locked_sync[2] &
                           pll_locked_sync[3] & pll_locked_sync[4];

    // =========================================================================
    // 4. CSR Register Storage & Bus Interface
    // =========================================================================
    logic        reg_ctrl_auto_fallback_en;
    logic        reg_ctrl_global_gate_override;
    logic [4:0]  reg_pll_err_int_en;
    logic [4:0]  reg_clk_gate_en;
    logic [4:0]  reg_clk_bypass_sel;
    logic [7:0]  reg_sys_clk_div;
    logic [7:0]  reg_mem_clk_div;
    logic [7:0]  reg_ring_clk_div;
    logic [7:0]  reg_gpu_clk_div;
    logic [7:0]  reg_core_clk_div;
    logic [15:0] reg_warm_rst_len;
    logic [15:0] reg_boot_stage_delay;
    logic [4:0]  pulse_warm_rst;

    logic [4:0]  warm_rst_busy;
    logic [2:0]  boot_state;
    logic        boot_done;
    logic [4:0]  active_bypass_status;

    wire addr_match = (bus_addr[31:12] == CMU_BASE_ADDR[31:12]);
    wire [11:0] reg_offset = bus_addr[11:0];

    logic [31:0] rdata_comb;
    logic        offset_valid;

    always_comb begin
        offset_valid = 1'b1;
        rdata_comb   = 32'h0;

        case (reg_offset)
            CMU_REG_CTRL: begin
                rdata_comb = {30'd0, reg_ctrl_global_gate_override, reg_ctrl_auto_fallback_en};
            end
            CMU_REG_STATUS: begin
                rdata_comb = {28'd0, (|warm_rst_busy), (|loss_of_lock_sticky), boot_done, all_plls_locked};
            end
            CMU_REG_PLL_STATUS: begin
                rdata_comb = {27'd0, pll_locked_sync};
            end
            CMU_REG_PLL_ERR_STATUS: begin
                rdata_comb = {27'd0, loss_of_lock_sticky};
            end
            CMU_REG_PLL_ERR_INT_EN: begin
                rdata_comb = {27'd0, reg_pll_err_int_en};
            end
            CMU_REG_CLK_GATE_EN: begin
                rdata_comb = {27'd0, reg_clk_gate_en};
            end
            CMU_REG_CLK_BYPASS_SEL: begin
                rdata_comb = {27'd0, reg_clk_bypass_sel};
            end
            CMU_REG_CLK_BYPASS_STAT: begin
                rdata_comb = {27'd0, active_bypass_status};
            end
            CMU_REG_SYS_CLK_DIV: begin
                rdata_comb = {24'd0, reg_sys_clk_div};
            end
            CMU_REG_MEM_CLK_DIV: begin
                rdata_comb = {24'd0, reg_mem_clk_div};
            end
            CMU_REG_RING_CLK_DIV: begin
                rdata_comb = {24'd0, reg_ring_clk_div};
            end
            CMU_REG_GPU_CLK_DIV: begin
                rdata_comb = {24'd0, reg_gpu_clk_div};
            end
            CMU_REG_CORE_CLK_DIV: begin
                rdata_comb = {24'd0, reg_core_clk_div};
            end
            CMU_REG_WARM_RST_REQ: begin
                rdata_comb = {27'd0, warm_rst_busy};
            end
            CMU_REG_WARM_RST_BUSY: begin
                rdata_comb = {27'd0, warm_rst_busy};
            end
            CMU_REG_WARM_RST_LEN: begin
                rdata_comb = {16'd0, reg_warm_rst_len};
            end
            CMU_REG_BOOT_STATUS: begin
                rdata_comb = {28'd0, boot_done, boot_state};
            end
            CMU_REG_BOOT_STAGE_DLY: begin
                rdata_comb = {16'd0, reg_boot_stage_delay};
            end
            CMU_REG_RESET_STATUS: begin
                rdata_comb = {27'd0, rst_core_ni, rst_gpu_ni, rst_ring_ni, rst_mem_ni, rst_sys_ni};
            end
            CMU_REG_VERSION: begin
                rdata_comb = 32'h2026_0904;
            end
            default: begin
                offset_valid = 1'b0;
                rdata_comb   = 32'h0;
            end
        endcase
    end

    assign bus_ready = bus_valid;
    assign bus_resp  = (addr_match && offset_valid) ? COMMS_RESP_OKAY : COMMS_RESP_SLVERR;
    assign bus_rdata = (bus_ren && addr_match && offset_valid) ? rdata_comb : 32'h0;

    wire reg_write_en = bus_valid && bus_wen && addr_match && offset_valid;

    always_ff @(posedge clk_in or negedge rst_ni) begin
        if (!rst_ni) begin
            reg_ctrl_auto_fallback_en     <= 1'b1;
            reg_ctrl_global_gate_override <= 1'b0;
            reg_pll_err_int_en            <= 5'd0;
            reg_clk_gate_en               <= 5'b11111;
            reg_clk_bypass_sel            <= 5'b00001;
            reg_sys_clk_div               <= 8'd1;
            reg_mem_clk_div               <= 8'd2;
            reg_ring_clk_div              <= 8'd1;
            reg_gpu_clk_div               <= 8'd4;
            reg_core_clk_div              <= 8'd1;
            reg_warm_rst_len              <= 16'd16;
            reg_boot_stage_delay          <= 16'd32;
            pulse_warm_rst                <= 5'd0;
            clear_sticky_err_pulse        <= 5'd0;
        end else begin
            pulse_warm_rst         <= 5'd0;
            clear_sticky_err_pulse <= 5'd0;

            if (reg_write_en) begin
                case (reg_offset)
                    CMU_REG_CTRL: begin
                        reg_ctrl_auto_fallback_en     <= bus_wdata[0];
                        reg_ctrl_global_gate_override <= bus_wdata[1];
                    end
                    CMU_REG_PLL_ERR_STATUS: begin
                        clear_sticky_err_pulse <= bus_wdata[4:0];
                    end
                    CMU_REG_PLL_ERR_INT_EN: begin
                        reg_pll_err_int_en <= bus_wdata[4:0];
                    end
                    CMU_REG_CLK_GATE_EN: begin
                        reg_clk_gate_en <= bus_wdata[4:0];
                    end
                    CMU_REG_CLK_BYPASS_SEL: begin
                        reg_clk_bypass_sel <= bus_wdata[4:0];
                    end
                    CMU_REG_SYS_CLK_DIV: begin
                        reg_sys_clk_div <= (bus_wdata[7:0] == 8'd0) ? 8'd1 : bus_wdata[7:0];
                    end
                    CMU_REG_MEM_CLK_DIV: begin
                        reg_mem_clk_div <= (bus_wdata[7:0] == 8'd0) ? 8'd1 : bus_wdata[7:0];
                    end
                    CMU_REG_RING_CLK_DIV: begin
                        reg_ring_clk_div <= (bus_wdata[7:0] == 8'd0) ? 8'd1 : bus_wdata[7:0];
                    end
                    CMU_REG_GPU_CLK_DIV: begin
                        reg_gpu_clk_div <= (bus_wdata[7:0] == 8'd0) ? 8'd1 : bus_wdata[7:0];
                    end
                    CMU_REG_CORE_CLK_DIV: begin
                        reg_core_clk_div <= (bus_wdata[7:0] == 8'd0) ? 8'd1 : bus_wdata[7:0];
                    end
                    CMU_REG_WARM_RST_REQ: begin
                        pulse_warm_rst <= bus_wdata[4:0];
                    end
                    CMU_REG_WARM_RST_LEN: begin
                        reg_warm_rst_len <= bus_wdata[15:0];
                    end
                    CMU_REG_BOOT_STAGE_DLY: begin
                        reg_boot_stage_delay <= bus_wdata[15:0];
                    end
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // 5. Glitch-Free Clock Multiplexing
    // =========================================================================
    logic [4:0] mux_sel;
    logic [4:0] mux_force_bypass;

    // Normal operation: reg_clk_bypass_sel = 0 -> mux_sel = 1 (PLL), sel = 0 selects bypass clk_in
    assign mux_sel[0] = 1'b0; // SYS domain always uses bypass clk_in
    assign mux_sel[1] = ~reg_clk_bypass_sel[1];
    assign mux_sel[2] = ~reg_clk_bypass_sel[2];
    assign mux_sel[3] = ~reg_clk_bypass_sel[3];
    assign mux_sel[4] = ~reg_clk_bypass_sel[4];

    assign mux_force_bypass[0] = 1'b0;
    assign mux_force_bypass[1] = reg_ctrl_auto_fallback_en & pll_force_bypass[1];
    assign mux_force_bypass[2] = reg_ctrl_auto_fallback_en & pll_force_bypass[2];
    assign mux_force_bypass[3] = reg_ctrl_auto_fallback_en & pll_force_bypass[3];
    assign mux_force_bypass[4] = reg_ctrl_auto_fallback_en & pll_force_bypass[4];

    assign active_bypass_status[0] = 1'b1;
    assign active_bypass_status[1] = reg_clk_bypass_sel[1] | mux_force_bypass[1];
    assign active_bypass_status[2] = reg_clk_bypass_sel[2] | mux_force_bypass[2];
    assign active_bypass_status[3] = reg_clk_bypass_sel[3] | mux_force_bypass[3];
    assign active_bypass_status[4] = reg_clk_bypass_sel[4] | mux_force_bypass[4];

    logic clk_sys_muxed;
    logic clk_mem_muxed;
    logic clk_ring_muxed;
    logic clk_gpu_muxed;
    logic clk_core_muxed;

    assign clk_sys_muxed = clk_in;

    glitch_free_clock_mux u_mux_mem (
        .clk0         (clk_in),
        .rst_clk0_ni  (rst_ni),
        .clk1         (pll_clk_mem),
        .rst_clk1_ni  (rst_ni),
        .sel          (mux_sel[1]),
        .force_bypass (mux_force_bypass[1]),
        .clk_out      (clk_mem_muxed)
    );

    glitch_free_clock_mux u_mux_ring (
        .clk0         (clk_in),
        .rst_clk0_ni  (rst_ni),
        .clk1         (pll_clk_ring),
        .rst_clk1_ni  (rst_ni),
        .sel          (mux_sel[2]),
        .force_bypass (mux_force_bypass[2]),
        .clk_out      (clk_ring_muxed)
    );

    glitch_free_clock_mux u_mux_gpu (
        .clk0         (clk_in),
        .rst_clk0_ni  (rst_ni),
        .clk1         (pll_clk_gpu),
        .rst_clk1_ni  (rst_ni),
        .sel          (mux_sel[3]),
        .force_bypass (mux_force_bypass[3]),
        .clk_out      (clk_gpu_muxed)
    );

    glitch_free_clock_mux u_mux_core (
        .clk0         (clk_in),
        .rst_clk0_ni  (rst_ni),
        .clk1         (pll_clk_core),
        .rst_clk1_ni  (rst_ni),
        .sel          (mux_sel[4]),
        .force_bypass (mux_force_bypass[4]),
        .clk_out      (clk_core_muxed)
    );

    // =========================================================================
    // 6. Dynamic Clock Dividers
    // =========================================================================
    logic clk_sys_divided;
    logic clk_mem_divided;
    logic clk_ring_divided;
    logic clk_gpu_divided;
    logic clk_core_divided;

    clock_divider #(.MAX_DIV(64)) u_div_sys (
        .clk_in  (clk_sys_muxed),
        .rst_ni  (rst_ni),
        .div_val (reg_sys_clk_div),
        .clk_out (clk_sys_divided)
    );

    clock_divider #(.MAX_DIV(64)) u_div_mem (
        .clk_in  (clk_mem_muxed),
        .rst_ni  (rst_ni),
        .div_val (reg_mem_clk_div),
        .clk_out (clk_mem_divided)
    );

    clock_divider #(.MAX_DIV(64)) u_div_ring (
        .clk_in  (clk_ring_muxed),
        .rst_ni  (rst_ni),
        .div_val (reg_ring_clk_div),
        .clk_out (clk_ring_divided)
    );

    clock_divider #(.MAX_DIV(64)) u_div_gpu (
        .clk_in  (clk_gpu_muxed),
        .rst_ni  (rst_ni),
        .div_val (reg_gpu_clk_div),
        .clk_out (clk_gpu_divided)
    );

    clock_divider #(.MAX_DIV(64)) u_div_core (
        .clk_in  (clk_core_muxed),
        .rst_ni  (rst_ni),
        .div_val (reg_core_clk_div),
        .clk_out (clk_core_divided)
    );

    // =========================================================================
    // 7. Flop-Based Integrated Clock Gating (ICG)
    // =========================================================================
    wire gate_en_sys  = reg_clk_gate_en[0] | reg_ctrl_global_gate_override;
    wire gate_en_mem  = reg_clk_gate_en[1] | reg_ctrl_global_gate_override;
    wire gate_en_ring = reg_clk_gate_en[2] | reg_ctrl_global_gate_override;
    wire gate_en_gpu  = reg_clk_gate_en[3] | reg_ctrl_global_gate_override;
    wire gate_en_core = reg_clk_gate_en[4] | reg_ctrl_global_gate_override;

    clock_gater u_gate_sys (
        .clk_in  (clk_sys_divided),
        .rst_ni  (rst_ni),
        .enable  (gate_en_sys),
        .test_en (1'b0),
        .clk_out (clk_sys)
    );

    clock_gater u_gate_mem (
        .clk_in  (clk_mem_divided),
        .rst_ni  (rst_ni),
        .enable  (gate_en_mem),
        .test_en (1'b0),
        .clk_out (clk_mem)
    );

    clock_gater u_gate_ring (
        .clk_in  (clk_ring_divided),
        .rst_ni  (rst_ni),
        .enable  (gate_en_ring),
        .test_en (1'b0),
        .clk_out (clk_ring)
    );

    clock_gater u_gate_gpu (
        .clk_in  (clk_gpu_divided),
        .rst_ni  (rst_ni),
        .enable  (gate_en_gpu),
        .test_en (1'b0),
        .clk_out (clk_gpu)
    );

    clock_gater u_gate_core (
        .clk_in  (clk_core_divided),
        .rst_ni  (rst_ni),
        .enable  (gate_en_core),
        .test_en (1'b0),
        .clk_out (clk_core)
    );

    // =========================================================================
    // 8. Staged Boot & Warm Reset Sequencer
    // =========================================================================
    logic rst_mem_async_n;
    logic rst_ring_async_n;
    logic rst_gpu_async_n;
    logic rst_core_async_n;

    logic fsm_release_mem,  fsm_release_ring;
    logic fsm_release_gpu,  fsm_release_core;

    cmu_reset_sequencer u_reset_seq (
        .clk_sys                (clk_in),
        .rst_sys_ni             (rst_sys_internal_n),
        .rst_ni                 (rst_ni),
        .all_plls_locked        (all_plls_locked),
        .rst_mem_ni             (rst_mem_ni),
        .rst_gpu_ni             (rst_gpu_ni),
        .cfg_delay_mem_to_gpu   (reg_boot_stage_delay),
        .cfg_delay_gpu_to_core  (reg_boot_stage_delay),
        .cfg_warm_rst_pulse_len (reg_warm_rst_len),
        .req_warm_rst_sys       (pulse_warm_rst[0]),
        .req_warm_rst_mem       (pulse_warm_rst[1]),
        .req_warm_rst_ring      (pulse_warm_rst[2]),
        .req_warm_rst_gpu       (pulse_warm_rst[3]),
        .req_warm_rst_core      (pulse_warm_rst[4]),
        .fsm_release_mem        (fsm_release_mem),
        .fsm_release_ring       (fsm_release_ring),
        .fsm_release_gpu        (fsm_release_gpu),
        .fsm_release_core       (fsm_release_core),
        .rst_sys_async_n        (rst_sys_async_n),
        .rst_mem_async_n        (rst_mem_async_n),
        .rst_ring_async_n       (rst_ring_async_n),
        .rst_gpu_async_n        (rst_gpu_async_n),
        .rst_core_async_n       (rst_core_async_n),
        .warm_rst_busy_sys      (warm_rst_busy[0]),
        .warm_rst_busy_mem      (warm_rst_busy[1]),
        .warm_rst_busy_ring     (warm_rst_busy[2]),
        .warm_rst_busy_gpu      (warm_rst_busy[3]),
        .warm_rst_busy_core     (warm_rst_busy[4]),
        .boot_state             (boot_state),
        .boot_done              (boot_done)
    );

    // =========================================================================
    // 9. Domain Reset Synchronizers
    // =========================================================================
    reset_sync #(.STAGES(2)) u_mem_rst_sync (
        .clk        (clk_mem),
        .rst_ni     (rst_mem_async_n),
        .rst_sync_no(rst_mem_ni)
    );

    reset_sync #(.STAGES(2)) u_ring_rst_sync (
        .clk        (clk_ring),
        .rst_ni     (rst_ring_async_n),
        .rst_sync_no(rst_ring_ni)
    );

    reset_sync #(.STAGES(2)) u_gpu_rst_sync (
        .clk        (clk_gpu),
        .rst_ni     (rst_gpu_async_n),
        .rst_sync_no(rst_gpu_ni)
    );

    reset_sync #(.STAGES(2)) u_core_rst_sync (
        .clk        (clk_core),
        .rst_ni     (rst_core_async_n),
        .rst_sync_no(rst_core_ni)
    );

endmodule
