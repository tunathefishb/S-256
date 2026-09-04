`timescale 1ns/1ps

module cmu_reset_sequencer (
    input  logic        clk_sys,
    input  logic        rst_sys_ni,
    input  logic        rst_ni,              // Main external asynchronous reset
    input  logic        all_plls_locked,

    // Feedback synchronized reset status to ensure inter-stage delays measure from deassertion
    input  logic        rst_mem_ni = 1'b1,
    input  logic        rst_gpu_ni = 1'b1,

    // Configurable stage transition delays (cycles of clk_sys)
    input  logic [15:0] cfg_delay_mem_to_gpu,
    input  logic [15:0] cfg_delay_gpu_to_core,
    input  logic [15:0] cfg_warm_rst_pulse_len,

    // Software warm reset requests (1-cycle strobes from CSR)
    input  logic        req_warm_rst_sys,
    input  logic        req_warm_rst_mem,
    input  logic        req_warm_rst_ring,
    input  logic        req_warm_rst_gpu,
    input  logic        req_warm_rst_core,

    // FSM release status
    output logic        fsm_release_mem,
    output logic        fsm_release_ring,
    output logic        fsm_release_gpu,
    output logic        fsm_release_core,

    // Combined asynchronous reset outputs to domain reset_sync modules
    output logic        rst_sys_async_n,
    output logic        rst_mem_async_n,
    output logic        rst_ring_async_n,
    output logic        rst_gpu_async_n,
    output logic        rst_core_async_n,

    // Active warm reset busy status
    output logic        warm_rst_busy_sys,
    output logic        warm_rst_busy_mem,
    output logic        warm_rst_busy_ring,
    output logic        warm_rst_busy_gpu,
    output logic        warm_rst_busy_core,

    // Boot status
    output logic [2:0]  boot_state,
    output logic        boot_done
);

    import soc_pkg::*;

    cmu_boot_state_e state_q, state_d;
    logic [15:0] delay_cnt_q, delay_cnt_d;

    assign boot_state = state_q;
    assign boot_done  = (state_q == BOOT_ST_RUN);

    // =========================================================================
    // 1. Boot Sequencer FSM
    // =========================================================================
    always_ff @(posedge clk_sys or negedge rst_sys_ni) begin
        if (!rst_sys_ni) begin
            state_q     <= BOOT_ST_INIT;
            delay_cnt_q <= 16'd0;
        end else begin
            state_q     <= state_d;
            delay_cnt_q <= delay_cnt_d;
        end
    end

    always_comb begin
        state_d          = state_q;
        delay_cnt_d      = delay_cnt_q;
        fsm_release_mem  = 1'b0;
        fsm_release_ring = 1'b0;
        fsm_release_gpu  = 1'b0;
        fsm_release_core = 1'b0;

        case (state_q)
            BOOT_ST_INIT: begin
                if (all_plls_locked) begin
                    state_d     = BOOT_ST_RELEASE_MEM_RING;
                    delay_cnt_d = cfg_delay_mem_to_gpu;
                end
            end

            BOOT_ST_RELEASE_MEM_RING: begin
                fsm_release_mem  = 1'b1;
                fsm_release_ring = 1'b1;
                // Wait for memory subsystem to confirm reset deassertion before counting inter-stage delay
                if (!rst_mem_ni) begin
                    delay_cnt_d = cfg_delay_mem_to_gpu;
                end else if (delay_cnt_q == 16'd0) begin
                    state_d     = BOOT_ST_RELEASE_GPU;
                    delay_cnt_d = cfg_delay_gpu_to_core;
                end else begin
                    delay_cnt_d = delay_cnt_q - 1'b1;
                end
            end

            BOOT_ST_RELEASE_GPU: begin
                fsm_release_mem  = 1'b1;
                fsm_release_ring = 1'b1;
                fsm_release_gpu  = 1'b1;
                // Wait for GPU subsystem to confirm reset deassertion before counting inter-stage delay
                if (!rst_gpu_ni) begin
                    delay_cnt_d = cfg_delay_gpu_to_core;
                end else if (delay_cnt_q == 16'd0) begin
                    state_d     = BOOT_ST_RELEASE_CORE;
                    delay_cnt_d = 16'd0;
                end else begin
                    delay_cnt_d = delay_cnt_q - 1'b1;
                end
            end

            BOOT_ST_RELEASE_CORE: begin
                fsm_release_mem  = 1'b1;
                fsm_release_ring = 1'b1;
                fsm_release_gpu  = 1'b1;
                fsm_release_core = 1'b1;
                state_d          = BOOT_ST_RUN;
            end

            BOOT_ST_RUN: begin
                fsm_release_mem  = 1'b1;
                fsm_release_ring = 1'b1;
                fsm_release_gpu  = 1'b1;
                fsm_release_core = 1'b1;
            end

            default: begin
                state_d = BOOT_ST_INIT;
            end
        endcase
    end

    // =========================================================================
    // 2. Pulse-Stretched Domain Warm Reset Generators
    // =========================================================================
    wire [15:0] pulse_len = (cfg_warm_rst_pulse_len == 16'd0) ? 16'd16 : cfg_warm_rst_pulse_len;

    logic [15:0] warm_cnt_sys, warm_cnt_mem, warm_cnt_ring, warm_cnt_gpu, warm_cnt_core;

    function automatic logic [15:0] update_warm_cnt(
        input logic        req,
        input logic [15:0] cur_cnt,
        input logic [15:0] load_val
    );
        if (req) begin
            return load_val;
        end else if (cur_cnt > 16'd0) begin
            return cur_cnt - 1'b1;
        end else begin
            return 16'd0;
        end
    endfunction

    always_ff @(posedge clk_sys or negedge rst_sys_ni) begin
        if (!rst_sys_ni) begin
            warm_cnt_sys  <= 16'd0;
            warm_cnt_mem  <= 16'd0;
            warm_cnt_ring <= 16'd0;
            warm_cnt_gpu  <= 16'd0;
            warm_cnt_core <= 16'd0;
        end else begin
            warm_cnt_sys  <= update_warm_cnt(req_warm_rst_sys,  warm_cnt_sys,  pulse_len);
            warm_cnt_mem  <= update_warm_cnt(req_warm_rst_mem,  warm_cnt_mem,  pulse_len);
            warm_cnt_ring <= update_warm_cnt(req_warm_rst_ring, warm_cnt_ring, pulse_len);
            warm_cnt_gpu  <= update_warm_cnt(req_warm_rst_gpu,  warm_cnt_gpu,  pulse_len);
            warm_cnt_core <= update_warm_cnt(req_warm_rst_core, warm_cnt_core, pulse_len);
        end
    end

    assign warm_rst_busy_sys  = (warm_cnt_sys  > 16'd0);
    assign warm_rst_busy_mem  = (warm_cnt_mem  > 16'd0);
    assign warm_rst_busy_ring = (warm_cnt_ring > 16'd0);
    assign warm_rst_busy_gpu  = (warm_cnt_gpu  > 16'd0);
    assign warm_rst_busy_core = (warm_cnt_core > 16'd0);

    // =========================================================================
    // 3. Combined Asynchronous Reset Outputs
    // =========================================================================
    assign rst_sys_async_n  = rst_ni & ~warm_rst_busy_sys;
    assign rst_mem_async_n  = rst_ni & fsm_release_mem  & ~warm_rst_busy_mem;
    assign rst_ring_async_n = rst_ni & fsm_release_ring & ~warm_rst_busy_ring;
    assign rst_gpu_async_n  = rst_ni & fsm_release_gpu  & ~warm_rst_busy_gpu;
    assign rst_core_async_n = rst_ni & fsm_release_core & ~warm_rst_busy_core;

endmodule
