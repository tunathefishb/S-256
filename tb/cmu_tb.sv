`timescale 1ns/1ps

import soc_pkg::*;

// ============================================================================
// Continuous Runt Pulse & Glitch Monitor Module
// Tracks every clock edge and verifies pulse width >= MIN_PULSE_WIDTH (4.8ns).
// Guaranteed runt-free detection across all dynamic switches and gating transitions.
// ============================================================================
module runt_pulse_monitor #(
    parameter string DOMAIN_NAME     = "UNKNOWN",
    parameter real   MIN_PULSE_WIDTH = 4.8 // ns (100MHz half-period = 5.0ns)
)(
    input logic clk,
    input logic monitor_en
);
    realtime t_last_edge;
    logic    mon_en_d;

    initial begin
        t_last_edge = 0.0;
        mon_en_d    = 1'b0;
    end

    always @(posedge clk or negedge clk) begin
        if (monitor_en && mon_en_d && t_last_edge > 0.0) begin
            realtime pulse_width;
            pulse_width = $realtime - t_last_edge;
            if (pulse_width < MIN_PULSE_WIDTH) begin
                $fatal(1, "[%0t] *** RUNT PULSE DETECTED *** Domain: %s! Pulse width = %0.3f ns (< min %0.3f ns)",
                       $time, DOMAIN_NAME, pulse_width, MIN_PULSE_WIDTH);
            end
        end
        mon_en_d    <= monitor_en;
        t_last_edge = $realtime;
    end
endmodule


// ============================================================================
// Production-Grade CMU Verification Testbench (Tiers 1-4)
// ============================================================================
module cmu_tb;

    // ------------------------------------------------------------------------
    // Clock, Reset & Bus Signals
    // ------------------------------------------------------------------------
    logic clk_in;
    logic rst_ni;

    // Domain Clocks and Synchronized Resets
    logic clk_sys,  rst_sys_ni;
    logic clk_mem,  rst_mem_ni;
    logic clk_ring, rst_ring_ni;
    logic clk_gpu,  rst_gpu_ni;
    logic clk_core, rst_core_ni;

    // Testbench Control and Statistics
    logic runt_mon_en;
    int   pass_count;
    int   fail_count;

    // Instantiation of comms_bus_if for BFM Driver
    comms_bus_if comms_if (.clk(clk_in));

    // ------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // ------------------------------------------------------------------------
    cmu u_cmu (
        .clk_in      (clk_in),
        .rst_ni      (rst_ni),
        .bus_addr    (comms_if.addr),
        .bus_wdata   (comms_if.wdata),
        .bus_wen     (comms_if.wen),
        .bus_ren     (comms_if.ren),
        .bus_valid   (comms_if.valid),
        .bus_ready   (comms_if.ready),
        .bus_rdata   (comms_if.rdata),
        .bus_resp    (comms_if.resp),
        .clk_sys     (clk_sys),
        .rst_sys_ni  (rst_sys_ni),
        .clk_mem     (clk_mem),
        .rst_mem_ni  (rst_mem_ni),
        .clk_ring    (clk_ring),
        .rst_ring_ni (rst_ring_ni),
        .clk_gpu     (clk_gpu),
        .rst_gpu_ni  (rst_gpu_ni),
        .clk_core    (clk_core),
        .rst_core_ni (rst_core_ni)
    );

    // ------------------------------------------------------------------------
    // Continuous Glitch & Runt Pulse Monitors (One per domain)
    // ------------------------------------------------------------------------
    runt_pulse_monitor #(.DOMAIN_NAME("SYS"),  .MIN_PULSE_WIDTH(4.8)) u_runt_sys  (.clk(clk_sys),  .monitor_en(runt_mon_en));
    runt_pulse_monitor #(.DOMAIN_NAME("MEM"),  .MIN_PULSE_WIDTH(4.8)) u_runt_mem  (.clk(clk_mem),  .monitor_en(runt_mon_en));
    runt_pulse_monitor #(.DOMAIN_NAME("RING"), .MIN_PULSE_WIDTH(4.8)) u_runt_ring (.clk(clk_ring), .monitor_en(runt_mon_en));
    runt_pulse_monitor #(.DOMAIN_NAME("GPU"),  .MIN_PULSE_WIDTH(4.8)) u_runt_gpu  (.clk(clk_gpu),  .monitor_en(runt_mon_en));
    runt_pulse_monitor #(.DOMAIN_NAME("CORE"), .MIN_PULSE_WIDTH(4.8)) u_runt_core (.clk(clk_core), .monitor_en(runt_mon_en));

    // ------------------------------------------------------------------------
    // Reset Pin Transition Event Loggers
    // ------------------------------------------------------------------------
    initial forever @(posedge rst_sys_ni)  $display("[%0t] [PIN EVENT] rst_sys_ni  -> 1", $time);
    initial forever @(posedge rst_mem_ni)  $display("[%0t] [PIN EVENT] rst_mem_ni  -> 1", $time);
    initial forever @(posedge rst_ring_ni) $display("[%0t] [PIN EVENT] rst_ring_ni -> 1", $time);
    initial forever @(posedge rst_gpu_ni)  $display("[%0t] [PIN EVENT] rst_gpu_ni  -> 1", $time);
    initial forever @(posedge rst_core_ni) $display("[%0t] [PIN EVENT] rst_core_ni -> 1", $time);

    // ------------------------------------------------------------------------
    // Reference Oscillator Generator (100 MHz, 10.0 ns period)
    // ------------------------------------------------------------------------
    initial begin
        clk_in = 1'b0;
        forever #5.0 clk_in = ~clk_in;
    end

    // ------------------------------------------------------------------------
    // Simulation Watchdog Timer
    // ------------------------------------------------------------------------
    initial begin
        #500000; // 500 us maximum simulation timeout
        $fatal(1, "[%0t] *** TIMEOUT ERROR *** Simulation watchdog expired!", $time);
    end

    // ========================================================================
    // Bus Functional Model (BFM) Tasks
    // ========================================================================

    // Mutex / ticket lock for bus arbitration (Scenario 3.2 concurrent traffic)
    int bus_ticket_serve = 0;
    int bus_ticket_next  = 0;

    task automatic acquire_bus();
        int my_ticket;
        my_ticket = bus_ticket_next;
        bus_ticket_next = bus_ticket_next + 1;
        while (my_ticket !== bus_ticket_serve) @(posedge clk_in);
    endtask

    task automatic release_bus();
        bus_ticket_serve = bus_ticket_serve + 1;
    endtask

    task automatic csr_init();
        comms_if.addr  <= '0;
        comms_if.wdata <= '0;
        comms_if.cmd   <= '0;
        comms_if.wen   <= 1'b0;
        comms_if.ren   <= 1'b0;
        comms_if.valid <= 1'b0;
        bus_ticket_serve = 0;
        bus_ticket_next  = 0;
    endtask

    task automatic csr_write(
        input logic [11:0] addr_offset,
        input logic [31:0] data
    );
        acquire_bus();
        @(posedge clk_in);
        comms_if.addr  <= CMU_BASE_ADDR + {20'd0, addr_offset};
        comms_if.wdata <= data;
        comms_if.cmd   <= data;
        comms_if.wen   <= 1'b1;
        comms_if.ren   <= 1'b0;
        comms_if.valid <= 1'b1;

        @(posedge clk_in);
        while (!comms_if.ready) @(posedge clk_in);

        if (comms_if.resp !== COMMS_RESP_OKAY) begin
            fail_count++;
            $fatal(1, "[%0t] CSR WRITE ERROR: Unexpected resp %b on offset 0x%03h",
                   $time, comms_if.resp, addr_offset);
        end

        comms_if.valid <= 1'b0;
        comms_if.wen   <= 1'b0;
        @(posedge clk_in);
        release_bus();
    endtask

    task automatic csr_read(
        input  logic [11:0] addr_offset,
        output logic [31:0] data
    );
        acquire_bus();
        @(posedge clk_in);
        comms_if.addr  <= CMU_BASE_ADDR + {20'd0, addr_offset};
        comms_if.wen   <= 1'b0;
        comms_if.ren   <= 1'b1;
        comms_if.valid <= 1'b1;

        @(posedge clk_in);
        while (!comms_if.ready) @(posedge clk_in);

        data = comms_if.rdata;

        if (comms_if.resp !== COMMS_RESP_OKAY) begin
            fail_count++;
            $fatal(1, "[%0t] CSR READ ERROR: Unexpected resp %b on offset 0x%03h",
                   $time, comms_if.resp, addr_offset);
        end

        comms_if.valid <= 1'b0;
        comms_if.ren   <= 1'b0;
        @(posedge clk_in);
        release_bus();
    endtask

    task automatic csr_write_expect_resp(
        input logic [11:0] addr_offset,
        input logic [31:0] data,
        input logic [1:0]  expected_resp
    );
        acquire_bus();
        @(posedge clk_in);
        comms_if.addr  <= CMU_BASE_ADDR + {20'd0, addr_offset};
        comms_if.wdata <= data;
        comms_if.cmd   <= data;
        comms_if.wen   <= 1'b1;
        comms_if.ren   <= 1'b0;
        comms_if.valid <= 1'b1;

        @(posedge clk_in);
        while (!comms_if.ready) @(posedge clk_in);

        if (comms_if.resp !== expected_resp) begin
            fail_count++;
            $fatal(1, "[%0t] CSR RESP ERROR: Expected resp %b, got %b on offset 0x%03h",
                   $time, expected_resp, comms_if.resp, addr_offset);
        end else begin
            pass_count++;
        end

        comms_if.valid <= 1'b0;
        comms_if.wen   <= 1'b0;
        @(posedge clk_in);
        release_bus();
    endtask

    task automatic csr_read_expect_resp(
        input  logic [11:0] addr_offset,
        output logic [31:0] data,
        input  logic [1:0]  expected_resp
    );
        acquire_bus();
        @(posedge clk_in);
        comms_if.addr  <= CMU_BASE_ADDR + {20'd0, addr_offset};
        comms_if.wen   <= 1'b0;
        comms_if.ren   <= 1'b1;
        comms_if.valid <= 1'b1;

        @(posedge clk_in);
        while (!comms_if.ready) @(posedge clk_in);

        data = comms_if.rdata;

        if (comms_if.resp !== expected_resp) begin
            fail_count++;
            $fatal(1, "[%0t] CSR RESP ERROR: Expected resp %b, got %b on offset 0x%03h",
                   $time, expected_resp, comms_if.resp, addr_offset);
        end else begin
            pass_count++;
        end

        comms_if.valid <= 1'b0;
        comms_if.ren   <= 1'b0;
        @(posedge clk_in);
        release_bus();
    endtask

    task automatic csr_check(
        input logic [11:0] addr_offset,
        input logic [31:0] expected_data,
        input logic [31:0] mask,
        input string       reg_name
    );
        logic [31:0] actual_data;
        csr_read(addr_offset, actual_data);
        if ((actual_data & mask) !== (expected_data & mask)) begin
            fail_count++;
            $fatal(1, "[%0t] CSR MISMATCH on %s (offset 0x%03h): Expected 0x%08h, Got 0x%08h (Mask 0x%08h)",
                   $time, reg_name, addr_offset, expected_data, actual_data, mask);
        end else begin
            pass_count++;
            $display("[%0t] [PASS] CSR %s (0x%03h) verified: 0x%08h (mask 0x%08h)",
                     $time, reg_name, addr_offset, actual_data, mask);
        end
    endtask

    task automatic csr_poll(
        input logic [11:0] addr_offset,
        input logic [31:0] mask,
        input logic [31:0] expected_val,
        input int          max_cycles,
        input string       desc
    );
        logic [31:0] read_val;
        int cycles;
        cycles = 0;
        csr_read(addr_offset, read_val);
        while ((read_val & mask) !== (expected_val & mask) && cycles < max_cycles) begin
            cycles++;
            #20;
            csr_read(addr_offset, read_val);
        end
        if ((read_val & mask) !== (expected_val & mask)) begin
            fail_count++;
            $fatal(1, "[%0t] TIMEOUT waiting for %s: read 0x%08h, expected 0x%08h (mask 0x%08h) after %0d cycles",
                   $time, desc, read_val, expected_val, mask, cycles);
        end else begin
            pass_count++;
            $display("[%0t] [PASS] Poll %s succeeded in %0d cycles (val=0x%08h)", $time, desc, cycles, read_val);
        end
    endtask

    // ========================================================================
    // Clock Measurement & Validation Tasks
    // ========================================================================

    task automatic check_clock_frequency(
        input string  domain_name,
        input logic   clk_signal,
        input real    expected_period_ns,
        input real    tolerance_ns,
        input int     num_cycles
    );
        realtime t_rise, t_fall, period_measured, high_time_measured;
        int cycle_count;

        cycle_count = 0;
        case (domain_name[0])
            "S": begin
                @(posedge clk_sys);
                while (cycle_count < num_cycles) begin
                    t_rise = $realtime;
                    @(negedge clk_sys);
                    t_fall = $realtime;
                    high_time_measured = t_fall - t_rise;
                    @(posedge clk_sys);
                    period_measured = $realtime - t_rise;

                    if (period_measured < (expected_period_ns - tolerance_ns) ||
                        period_measured > (expected_period_ns + tolerance_ns)) begin
                        fail_count++;
                        $fatal(1, "[%0t] FREQ ERROR: Domain %s period = %0.3f ns (expected %0.3f ± %0.3f ns)",
                               $time, domain_name, period_measured, expected_period_ns, tolerance_ns);
                    end
                    if (high_time_measured < (period_measured * 0.40) ||
                        high_time_measured > (period_measured * 0.60)) begin
                        fail_count++;
                        $fatal(1, "[%0t] DUTY CYCLE ERROR: Domain %s high time = %0.3f ns (period %0.3f ns, duty %0.1f%%)",
                               $time, domain_name, high_time_measured, period_measured, (high_time_measured / period_measured) * 100.0);
                    end
                    cycle_count++;
                end
            end
            "M": begin
                @(posedge clk_mem);
                while (cycle_count < num_cycles) begin
                    t_rise = $realtime;
                    @(negedge clk_mem);
                    t_fall = $realtime;
                    high_time_measured = t_fall - t_rise;
                    @(posedge clk_mem);
                    period_measured = $realtime - t_rise;

                    if (period_measured < (expected_period_ns - tolerance_ns) ||
                        period_measured > (expected_period_ns + tolerance_ns)) begin
                        fail_count++;
                        $fatal(1, "[%0t] FREQ ERROR: Domain %s period = %0.3f ns (expected %0.3f ± %0.3f ns)",
                               $time, domain_name, period_measured, expected_period_ns, tolerance_ns);
                    end
                    if (high_time_measured < (period_measured * 0.40) ||
                        high_time_measured > (period_measured * 0.60)) begin
                        fail_count++;
                        $fatal(1, "[%0t] DUTY CYCLE ERROR: Domain %s high time = %0.3f ns (period %0.3f ns, duty %0.1f%%)",
                               $time, domain_name, high_time_measured, period_measured, (high_time_measured / period_measured) * 100.0);
                    end
                    cycle_count++;
                end
            end
            "R": begin
                @(posedge clk_ring);
                while (cycle_count < num_cycles) begin
                    t_rise = $realtime;
                    @(negedge clk_ring);
                    t_fall = $realtime;
                    high_time_measured = t_fall - t_rise;
                    @(posedge clk_ring);
                    period_measured = $realtime - t_rise;

                    if (period_measured < (expected_period_ns - tolerance_ns) ||
                        period_measured > (expected_period_ns + tolerance_ns)) begin
                        fail_count++;
                        $fatal(1, "[%0t] FREQ ERROR: Domain %s period = %0.3f ns (expected %0.3f ± %0.3f ns)",
                               $time, domain_name, period_measured, expected_period_ns, tolerance_ns);
                    end
                    if (high_time_measured < (period_measured * 0.40) ||
                        high_time_measured > (period_measured * 0.60)) begin
                        fail_count++;
                        $fatal(1, "[%0t] DUTY CYCLE ERROR: Domain %s high time = %0.3f ns (period %0.3f ns, duty %0.1f%%)",
                               $time, domain_name, high_time_measured, period_measured, (high_time_measured / period_measured) * 100.0);
                    end
                    cycle_count++;
                end
            end
            "G": begin
                @(posedge clk_gpu);
                while (cycle_count < num_cycles) begin
                    t_rise = $realtime;
                    @(negedge clk_gpu);
                    t_fall = $realtime;
                    high_time_measured = t_fall - t_rise;
                    @(posedge clk_gpu);
                    period_measured = $realtime - t_rise;

                    if (period_measured < (expected_period_ns - tolerance_ns) ||
                        period_measured > (expected_period_ns + tolerance_ns)) begin
                        fail_count++;
                        $fatal(1, "[%0t] FREQ ERROR: Domain %s period = %0.3f ns (expected %0.3f ± %0.3f ns)",
                               $time, domain_name, period_measured, expected_period_ns, tolerance_ns);
                    end
                    if (high_time_measured < (period_measured * 0.40) ||
                        high_time_measured > (period_measured * 0.60)) begin
                        fail_count++;
                        $fatal(1, "[%0t] DUTY CYCLE ERROR: Domain %s high time = %0.3f ns (period %0.3f ns, duty %0.1f%%)",
                               $time, domain_name, high_time_measured, period_measured, (high_time_measured / period_measured) * 100.0);
                    end
                    cycle_count++;
                end
            end
            "C": begin
                @(posedge clk_core);
                while (cycle_count < num_cycles) begin
                    t_rise = $realtime;
                    @(negedge clk_core);
                    t_fall = $realtime;
                    high_time_measured = t_fall - t_rise;
                    @(posedge clk_core);
                    period_measured = $realtime - t_rise;

                    if (period_measured < (expected_period_ns - tolerance_ns) ||
                        period_measured > (expected_period_ns + tolerance_ns)) begin
                        fail_count++;
                        $fatal(1, "[%0t] FREQ ERROR: Domain %s period = %0.3f ns (expected %0.3f ± %0.3f ns)",
                               $time, domain_name, period_measured, expected_period_ns, tolerance_ns);
                    end
                    if (high_time_measured < (period_measured * 0.40) ||
                        high_time_measured > (period_measured * 0.60)) begin
                        fail_count++;
                        $fatal(1, "[%0t] DUTY CYCLE ERROR: Domain %s high time = %0.3f ns (period %0.3f ns, duty %0.1f%%)",
                               $time, domain_name, high_time_measured, period_measured, (high_time_measured / period_measured) * 100.0);
                    end
                    cycle_count++;
                end
            end
            default: begin
                $fatal(1, "Unknown domain name %s in check_clock_frequency", domain_name);
            end
        endcase

        pass_count++;
        $display("[%0t] [PASS] Domain %s frequency verified: %0.2f MHz (%0.2f ns, duty ~50%%) over %0d cycles.",
                 $time, domain_name, 1000.0 / expected_period_ns, expected_period_ns, num_cycles);
    endtask

    task check_clock_gated_low(
        input string   domain_name,
        input logic    clk_signal,
        input realtime hold_time_ns
    );
        realtime t_start;
        t_start = $realtime;

        #50; // Allow in-flight cycle to complete and ICG to latch on negedge

        case (domain_name[0])
            "S": begin
                if (clk_sys !== 1'b0) begin
                    fail_count++;
                    $fatal(1, "[%0t] GATING ERROR: Gated clock %s did not settle at logic 0! Level = %b",
                           $time, domain_name, clk_sys);
                end
                fork : chk_quiescent_sys
                    begin
                        @(posedge clk_sys or negedge clk_sys);
                        fail_count++;
                        $fatal(1, "[%0t] GATING ERROR: Spurious toggle observed on gated clock %s!", $time, domain_name);
                    end
                    begin
                        #(hold_time_ns);
                    end
                join_any
                disable chk_quiescent_sys;
            end
            "M": begin
                if (clk_mem !== 1'b0) begin
                    fail_count++;
                    $fatal(1, "[%0t] GATING ERROR: Gated clock %s did not settle at logic 0! Level = %b",
                           $time, domain_name, clk_mem);
                end
                fork : chk_quiescent_mem
                    begin
                        @(posedge clk_mem or negedge clk_mem);
                        fail_count++;
                        $fatal(1, "[%0t] GATING ERROR: Spurious toggle observed on gated clock %s!", $time, domain_name);
                    end
                    begin
                        #(hold_time_ns);
                    end
                join_any
                disable chk_quiescent_mem;
            end
            "R": begin
                if (clk_ring !== 1'b0) begin
                    fail_count++;
                    $fatal(1, "[%0t] GATING ERROR: Gated clock %s did not settle at logic 0! Level = %b",
                           $time, domain_name, clk_ring);
                end
                fork : chk_quiescent_ring
                    begin
                        @(posedge clk_ring or negedge clk_ring);
                        fail_count++;
                        $fatal(1, "[%0t] GATING ERROR: Spurious toggle observed on gated clock %s!", $time, domain_name);
                    end
                    begin
                        #(hold_time_ns);
                    end
                join_any
                disable chk_quiescent_ring;
            end
            "G": begin
                if (clk_gpu !== 1'b0) begin
                    fail_count++;
                    $fatal(1, "[%0t] GATING ERROR: Gated clock %s did not settle at logic 0! Level = %b",
                           $time, domain_name, clk_gpu);
                end
                fork : chk_quiescent_gpu
                    begin
                        @(posedge clk_gpu or negedge clk_gpu);
                        fail_count++;
                        $fatal(1, "[%0t] GATING ERROR: Spurious toggle observed on gated clock %s!", $time, domain_name);
                    end
                    begin
                        #(hold_time_ns);
                    end
                join_any
                disable chk_quiescent_gpu;
            end
            "C": begin
                if (clk_core !== 1'b0) begin
                    fail_count++;
                    $fatal(1, "[%0t] GATING ERROR: Gated clock %s did not settle at logic 0! Level = %b",
                           $time, domain_name, clk_core);
                end
                fork : chk_quiescent_core
                    begin
                        @(posedge clk_core or negedge clk_core);
                        fail_count++;
                        $fatal(1, "[%0t] GATING ERROR: Spurious toggle observed on gated clock %s!", $time, domain_name);
                    end
                    begin
                        #(hold_time_ns);
                    end
                join_any
                disable chk_quiescent_core;
            end
            default: begin
                $fatal(1, "Unknown domain name %s in check_clock_gated_low", domain_name);
            end
        endcase

        pass_count++;
        $display("[%0t] [PASS] Clock %s held strictly low for %0.1f ns while gated.",
                 $time, domain_name, hold_time_ns);
    endtask

    task automatic set_divider(
        input logic [11:0] reg_offset,
        input logic [7:0]  ratio
    );
        // Write ratio with DIV_UPDATE bit (bit 8) set
        csr_write(reg_offset, {23'd0, 1'b1, ratio});
        #50; // Allow divider shadow register to latch on boundary
    endtask

    // ========================================================================
    // Main Test Execution Flow
    // ========================================================================
    initial begin
        logic [31:0] rdata;
        realtime t_main_release;
        realtime t_sys_deassert, t_mem_deassert, t_ring_deassert, t_gpu_deassert, t_core_deassert;

        $dumpfile("cmu_tb.vcd");
        $dumpvars(0, cmu_tb);

        pass_count  = 0;
        fail_count  = 0;
        runt_mon_en = 1'b0;
        csr_init();

        $display("================================================================================");
        $display("          S-256 CMU PRODUCTION E2E VERIFICATION SUITE (TIERS 1 - 4)");
        $display("================================================================================");

        // ====================================================================
        // TIER 1: FEATURE COVERAGE (Tests 1.1 - 1.8)
        // ====================================================================
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> Starting TIER 1: Feature Coverage Verification");
        $display("--------------------------------------------------------------------------------");

        // --------------------------------------------------------------------
        // Test 1.1: Cold Power-On Boot Sequence & Staged Deassertion Timing
        // --------------------------------------------------------------------
        $display("\n--- [Test 1.1] Cold Power-On Boot Sequencing & Staged Deassertion ---");
        rst_ni = 1'b0;
        #50;
        t_main_release = $realtime;
        rst_ni = 1'b1;
        $display("[%0t] Main Async Reset (rst_ni) Released", $time);

        // Wait for system reset release
        @(posedge rst_sys_ni);
        t_sys_deassert = $realtime;
        pass_count++;
        $display("[%0t] Stage 0: System Reset Deasserted (delay = %0.1f ns)", $time, t_sys_deassert - t_main_release);

        // Memory & Ring reset deassertion (concurrent release)
        fork
            begin
                @(posedge rst_mem_ni);
                t_mem_deassert = $realtime;
            end
            begin
                @(posedge rst_ring_ni);
                t_ring_deassert = $realtime;
            end
        join
        if (rst_gpu_ni !== 1'b0 || rst_core_ni !== 1'b0) begin
            fail_count++;
            $fatal(1, "BOOT ORDER ERROR: GPU or Core reset deasserted prematurely before Memory/Ring reset!");
        end
        pass_count += 2;
        $display("[%0t] Stage 1: Memory Deasserted at %0.1f ns, Ring Deasserted at %0.1f ns",
                 $time, t_mem_deassert, t_ring_deassert);

        // GPU reset deassertion
        @(posedge rst_gpu_ni);
        t_gpu_deassert = $realtime;
        $display("[%0t] Stage 2: GPU Reset Deasserted at %0.1f ns (rst_core_ni=%b)", $time, t_gpu_deassert, rst_core_ni);
        if (t_gpu_deassert <= t_mem_deassert) begin
            fail_count++;
            $fatal(1, "BOOT ORDER ERROR: GPU reset deasserted before or simultaneously with Memory!");
        end
        if (rst_core_ni !== 1'b0) begin
            fail_count++;
            $fatal(1, "BOOT ORDER ERROR: Core reset deasserted before GPU reset!");
        end
        pass_count++;
        $display("[%0t] Stage 2: GPU Reset Deasserted (delta = %0.1f ns)", $time, t_gpu_deassert - t_mem_deassert);

        // Core reset deassertion
        @(posedge rst_core_ni);
        t_core_deassert = $realtime;
        $display("[%0t] Stage 3: Core Reset Deasserted at %0.1f ns", $time, t_core_deassert);
        if (t_core_deassert <= t_gpu_deassert) begin
            fail_count++;
            $fatal(1, "BOOT ORDER ERROR: Core reset deasserted before or simultaneously with GPU!");
        end
        pass_count++;
        $display("[%0t] Stage 3: Core Reset Deasserted (delta = %0.1f ns)", $time, t_core_deassert - t_gpu_deassert);

        // Verify Strict Sequence: T(sys) < T(mem) <= T(ring) < T(gpu) < T(core)
        if (!(t_sys_deassert < t_mem_deassert && t_mem_deassert < t_gpu_deassert && t_gpu_deassert < t_core_deassert)) begin
            fail_count++;
            $fatal(1, "BOOT ORDER ERROR: Strict staged sequence violation: sys=%0.1f, mem=%0.1f, gpu=%0.1f, core=%0.1f",
                   t_sys_deassert, t_mem_deassert, t_gpu_deassert, t_core_deassert);
        end
        pass_count++;
        $display("[%0t] [PASS] Strict Boot Sequencing Order Verified: SYS < MEM <= RING < GPU < CORE", $time);

        // Verify Default Stage Delays (CMU_BOOT_STAGE_DELAY = 32 cycles = ~320ns)
        if ((t_gpu_deassert - t_mem_deassert) < 300.0) begin
            fail_count++;
            $fatal(1, "STAGE DELAY ERROR: Delay between Mem and GPU (%0.1f ns) shorter than programmed default (~320ns)",
                   t_gpu_deassert - t_mem_deassert);
        end
        if ((t_core_deassert - t_gpu_deassert) < 300.0) begin
            fail_count++;
            $fatal(1, "STAGE DELAY ERROR: Delay between GPU and Core (%0.1f ns) shorter than programmed default (~320ns)",
                   t_core_deassert - t_gpu_deassert);
        end
        pass_count += 2;
        $display("[%0t] [PASS] Default Boot Stage Delays Verified (~320ns per stage).", $time);

        // Enable Runt Pulse Monitors continuously after boot sequence
        runt_mon_en = 1'b1;
        #50;

        // Poll Boot Status Register: BOOT_STAGE == BOOT_ST_RUN (4) and BOOT_DONE == 1
        csr_poll(CMU_REG_BOOT_STATUS, 32'h0000_000F, 32'h0000_000C, 50, "Boot Sequencer FSM entering BOOT_ST_RUN");

        // Verify Reset Status Register: all 5 domains active (5'b11111)
        csr_check(CMU_REG_RESET_STATUS, 32'h0000_001F, 32'h0000_001F, "CMU_REG_RESET_STATUS");

        // --------------------------------------------------------------------
        // Test 1.2: CSR Read/Write Bus Access & Register Identity
        // --------------------------------------------------------------------
        $display("\n--- [Test 1.2] CSR Read/Write Bus Access & Register Identity ---");

        // Hardware Version Register Check
        csr_check(CMU_REG_VERSION, 32'h2026_0904, 32'hFFFF_FFFF, "CMU_REG_VERSION");

        // Verify Default Register Reset Values
        csr_check(CMU_REG_CTRL,            32'h0000_0001, 32'h0000_0003, "CMU_REG_CTRL");
        csr_check(CMU_REG_STATUS,          32'h0000_0003, 32'h0000_0003, "CMU_REG_STATUS (ALL_PLL_LOCKED & BOOT_COMPLETE)");
        csr_check(CMU_REG_PLL_STATUS,      32'h0000_001F, 32'h0000_001F, "CMU_REG_PLL_STATUS (All 5 PLLs locked)");
        csr_check(CMU_REG_PLL_ERR_STATUS,  32'h0000_0000, 32'h0000_001F, "CMU_REG_PLL_ERR_STATUS");
        csr_check(CMU_REG_CLK_GATE_EN,     32'h0000_001F, 32'h0000_001F, "CMU_REG_CLK_GATE_EN (All enabled)");
        csr_check(CMU_REG_CLK_BYPASS_SEL,  32'h0000_0001, 32'h0000_001F, "CMU_REG_CLK_BYPASS_SEL (SYS bypassed)");
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0001, 32'h0000_001F, "CMU_REG_CLK_BYPASS_STAT (SYS active bypass)");
        csr_check(CMU_REG_SYS_CLK_DIV,     32'h0000_0001, 32'h0000_00FF, "CMU_REG_SYS_CLK_DIV (N=1)");
        csr_check(CMU_REG_MEM_CLK_DIV,     32'h0000_0002, 32'h0000_00FF, "CMU_REG_MEM_CLK_DIV (N=2)");
        csr_check(CMU_REG_RING_CLK_DIV,    32'h0000_0001, 32'h0000_00FF, "CMU_REG_RING_CLK_DIV (N=1)");
        csr_check(CMU_REG_GPU_CLK_DIV,     32'h0000_0004, 32'h0000_00FF, "CMU_REG_GPU_CLK_DIV (N=4)");
        csr_check(CMU_REG_CORE_CLK_DIV,    32'h0000_0001, 32'h0000_00FF, "CMU_REG_CORE_CLK_DIV (N=1)");
        csr_check(CMU_REG_WARM_RST_BUSY,   32'h0000_0000, 32'h0000_001F, "CMU_REG_WARM_RST_BUSY");
        csr_check(CMU_REG_WARM_RST_LEN,    32'h0000_0010, 32'h0000_FFFF, "CMU_REG_WARM_RST_LEN (16 cycles)");
        csr_check(CMU_REG_BOOT_STAGE_DLY,  32'h0000_0020, 32'h0000_FFFF, "CMU_REG_BOOT_STAGE_DLY (32 cycles)");

        // Walking 1s Test on Interrupt Enable Register
        csr_write(CMU_REG_PLL_ERR_INT_EN, 32'h0000_0001);
        csr_check(CMU_REG_PLL_ERR_INT_EN, 32'h0000_0001, 32'h0000_001F, "INT_EN Bit 0");
        csr_write(CMU_REG_PLL_ERR_INT_EN, 32'h0000_0002);
        csr_check(CMU_REG_PLL_ERR_INT_EN, 32'h0000_0002, 32'h0000_001F, "INT_EN Bit 1");
        csr_write(CMU_REG_PLL_ERR_INT_EN, 32'h0000_0004);
        csr_check(CMU_REG_PLL_ERR_INT_EN, 32'h0000_0004, 32'h0000_001F, "INT_EN Bit 2");
        csr_write(CMU_REG_PLL_ERR_INT_EN, 32'h0000_0008);
        csr_check(CMU_REG_PLL_ERR_INT_EN, 32'h0000_0008, 32'h0000_001F, "INT_EN Bit 3");
        csr_write(CMU_REG_PLL_ERR_INT_EN, 32'h0000_0010);
        csr_check(CMU_REG_PLL_ERR_INT_EN, 32'h0000_0010, 32'h0000_001F, "INT_EN Bit 4");
        csr_write(CMU_REG_PLL_ERR_INT_EN, 32'h0000_0000); // Restore

        // --------------------------------------------------------------------
        // Test 1.3: Multi-Domain Default Clock Generation & Frequencies
        // --------------------------------------------------------------------
        $display("\n--- [Test 1.3] Multi-Domain Default Frequencies & Duty Cycles ---");
        check_clock_frequency("SYS",  clk_sys,  10.0, 0.1, 20); // 100 MHz
        check_clock_frequency("MEM",  clk_mem,  20.0, 0.2, 20); // 50 MHz
        check_clock_frequency("RING", clk_ring, 10.0, 0.1, 20); // 100 MHz
        check_clock_frequency("GPU",  clk_gpu,  40.0, 0.4, 20); // 25 MHz
        check_clock_frequency("CORE", clk_core, 10.0, 0.1, 20); // 100 MHz

        // --------------------------------------------------------------------
        // Test 1.4: Dynamic Clock Gating per Domain (ICG)
        // --------------------------------------------------------------------
        $display("\n--- [Test 1.4] Dynamic Clock Gating per Domain (ICG) ---");

        // MEM Gating
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001D); // Gate MEM (bit 1 = 0)
        check_clock_gated_low("MEM", clk_mem, 200.0);
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001F); // Re-enable MEM
        check_clock_frequency("MEM", clk_mem, 20.0, 0.2, 10);

        // RING Gating
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001B); // Gate RING (bit 2 = 0)
        check_clock_gated_low("RING", clk_ring, 200.0);
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001F); // Re-enable RING
        check_clock_frequency("RING", clk_ring, 10.0, 0.1, 10);

        // GPU Gating
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_0017); // Gate GPU (bit 3 = 0)
        check_clock_gated_low("GPU", clk_gpu, 200.0);
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001F); // Re-enable GPU
        check_clock_frequency("GPU", clk_gpu, 40.0, 0.4, 10);

        // CORE Gating
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_000F); // Gate CORE (bit 4 = 0)
        check_clock_gated_low("CORE", clk_core, 200.0);
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001F); // Re-enable CORE
        check_clock_frequency("CORE", clk_core, 10.0, 0.1, 10);

        // --------------------------------------------------------------------
        // Test 1.5: Dynamic Clock Dividers & Frequency Scaling
        // --------------------------------------------------------------------
        $display("\n--- [Test 1.5] Dynamic Clock Dividers & Frequency Scaling ---");

        // MEM: scale divider N=2 -> N=4 (50 MHz -> 25 MHz = 40ns)
        set_divider(CMU_REG_MEM_CLK_DIV, 8'd4);
        check_clock_frequency("MEM (div=4)", clk_mem, 40.0, 0.4, 10);
        set_divider(CMU_REG_MEM_CLK_DIV, 8'd2); // Restore N=2
        check_clock_frequency("MEM (div=2 restored)", clk_mem, 20.0, 0.2, 10);

        // CORE: scale divider N=1 -> N=2 (100 MHz -> 50 MHz = 20ns)
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd2);
        check_clock_frequency("CORE (div=2)", clk_core, 20.0, 0.2, 10);
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd1); // Restore N=1
        check_clock_frequency("CORE (div=1 restored)", clk_core, 10.0, 0.1, 10);

        // GPU: scale divider N=4 -> N=2 (25 MHz -> 50 MHz = 20ns)
        set_divider(CMU_REG_GPU_CLK_DIV, 8'd2);
        check_clock_frequency("GPU (div=2)", clk_gpu, 20.0, 0.2, 10);
        set_divider(CMU_REG_GPU_CLK_DIV, 8'd4); // Restore N=4
        check_clock_frequency("GPU (div=4 restored)", clk_gpu, 40.0, 0.4, 10);

        // --------------------------------------------------------------------
        // Test 1.6: Manual Clock Bypass Switching via CMU_CLK_BYPASS_SEL
        // --------------------------------------------------------------------
        $display("\n--- [Test 1.6] Manual Clock Bypass Switching via CMU_CLK_BYPASS_SEL ---");

        // Switch MEM to bypass clock (clk_in = 100MHz, with div=2 -> 50MHz = 20ns)
        csr_write(CMU_REG_CLK_BYPASS_SEL, 32'h0000_0003); // SYS + MEM bypass
        #50;
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0003, 32'h0000_0003, "MEM Bypass Active");
        check_clock_frequency("MEM (in bypass)", clk_mem, 20.0, 0.2, 10);

        // Restore MEM to PLL
        csr_write(CMU_REG_CLK_BYPASS_SEL, 32'h0000_0001); // Only SYS bypass
        #50;
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0001, 32'h0000_0003, "MEM PLL Active");
        check_clock_frequency("MEM (in PLL restored)", clk_mem, 20.0, 0.2, 10);

        // Switch GPU to bypass clock (clk_in = 100MHz, with div=4 -> 25MHz = 40ns)
        csr_write(CMU_REG_CLK_BYPASS_SEL, 32'h0000_0009); // SYS + GPU bypass
        #50;
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0009, 32'h0000_0009, "GPU Bypass Active");
        check_clock_frequency("GPU (in bypass)", clk_gpu, 40.0, 0.4, 10);
        csr_write(CMU_REG_CLK_BYPASS_SEL, 32'h0000_0001); // Restore
        #50;

        // --------------------------------------------------------------------
        // Test 1.7: PLL Loss-of-Lock Detection, Fallback & Recovery
        // --------------------------------------------------------------------
        $display("\n--- [Test 1.7] PLL Loss-of-Lock Detection, Fallback & Recovery ---");

        // Inject Loss-of-Lock on MEM PLL
        force u_cmu.pll_mem_locked_raw = 1'b0;
        #100;

        // Verify Automatic Fallback Status and Sticky Error
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0002, 32'h0000_0002, "MEM Auto-Fallback Asserted");
        csr_check(CMU_REG_PLL_ERR_STATUS,  32'h0000_0002, 32'h0000_0002, "MEM Sticky Error Flag Asserted");
        csr_check(CMU_REG_STATUS,          32'h0000_0004, 32'h0000_0004, "ANY_PLL_ERR Status Flag Asserted");

        // Verify Clock Continues Running Safely in Bypass Mode
        check_clock_frequency("MEM (Loss-of-Lock Fallback)", clk_mem, 20.0, 0.2, 10);

        // Restore PLL Lock
        release u_cmu.pll_mem_locked_raw;
        #100;

        // Sticky Error must REMAIN 1 before explicit software clear
        csr_check(CMU_REG_PLL_ERR_STATUS, 32'h0000_0002, 32'h0000_0002, "MEM Sticky Error Persists after re-lock");

        // Clear Sticky Error via W1C
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_0002);
        #50;
        csr_check(CMU_REG_PLL_ERR_STATUS, 32'h0000_0000, 32'h0000_0002, "MEM Sticky Error Cleared via W1C");
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0000, 32'h0000_0002, "MEM Bypass Status Cleared back to PLL");

        // Repeat for CORE PLL
        force u_cmu.pll_core_locked_raw = 1'b0;
        #100;
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0010, 32'h0000_0010, "CORE Auto-Fallback Asserted");
        csr_check(CMU_REG_PLL_ERR_STATUS,  32'h0000_0010, 32'h0000_0010, "CORE Sticky Error Asserted");
        check_clock_frequency("CORE (Fallback)", clk_core, 10.0, 0.1, 10);
        release u_cmu.pll_core_locked_raw;
        #100;
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_0010); // W1C
        #50;
        csr_check(CMU_REG_PLL_ERR_STATUS, 32'h0000_0000, 32'h0000_0010, "CORE Sticky Error Cleared");

        // --------------------------------------------------------------------
        // Test 1.8: Subsystem-Isolated Software Warm Reset
        // --------------------------------------------------------------------
        $display("\n--- [Test 1.8] Subsystem-Isolated Software Warm Reset ---");

        // Target GPU Domain for Warm Reset
        fork : gpu_warm_rst_test
            begin
                // Monitor unselected resets: MUST NEVER DROP LOW
                forever begin
                    #1;
                    if (rst_sys_ni  !== 1'b1) $fatal(1, "INTERFERENCE ERROR: rst_sys_ni glitched during GPU warm reset!");
                    if (rst_mem_ni  !== 1'b1) $fatal(1, "INTERFERENCE ERROR: rst_mem_ni glitched during GPU warm reset!");
                    if (rst_ring_ni !== 1'b1) $fatal(1, "INTERFERENCE ERROR: rst_ring_ni glitched during GPU warm reset!");
                    if (rst_core_ni !== 1'b1) $fatal(1, "INTERFERENCE ERROR: rst_core_ni glitched during GPU warm reset!");
                end
            end
            begin
                csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0008); // Trigger GPU warm reset
                @(negedge rst_gpu_ni);
                $display("[%0t] GPU Reset Asserted Low for Warm Reset.", $time);
                @(posedge rst_gpu_ni);
                $display("[%0t] GPU Reset Deasserted High Synchronously.", $time);
                csr_poll(CMU_REG_WARM_RST_BUSY, 32'h0000_0008, 32'h0000_0000, 50, "GPU Warm Reset Busy Clear");
            end
        join_any
        disable gpu_warm_rst_test;
        pass_count++;
        $display("[%0t] [PASS] GPU Warm Reset Isolated: other domains completely undisturbed.", $time);

        // Target CORE Domain for Warm Reset
        fork : core_warm_rst_test
            begin
                forever begin
                    #1;
                    if (rst_sys_ni  !== 1'b1) $fatal(1, "INTERFERENCE ERROR: rst_sys_ni glitched during CORE warm reset!");
                    if (rst_mem_ni  !== 1'b1) $fatal(1, "INTERFERENCE ERROR: rst_mem_ni glitched during CORE warm reset!");
                    if (rst_ring_ni !== 1'b1) $fatal(1, "INTERFERENCE ERROR: rst_ring_ni glitched during CORE warm reset!");
                    if (rst_gpu_ni  !== 1'b1) $fatal(1, "INTERFERENCE ERROR: rst_gpu_ni glitched during CORE warm reset!");
                end
            end
            begin
                csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0010); // Trigger CORE warm reset
                @(negedge rst_core_ni);
                $display("[%0t] CORE Reset Asserted Low for Warm Reset.", $time);
                @(posedge rst_core_ni);
                $display("[%0t] CORE Reset Deasserted High Synchronously.", $time);
                csr_poll(CMU_REG_WARM_RST_BUSY, 32'h0000_0010, 32'h0000_0000, 50, "CORE Warm Reset Busy Clear");
            end
        join_any
        disable core_warm_rst_test;
        pass_count++;
        $display("[%0t] [PASS] CORE Warm Reset Isolated: other domains completely undisturbed.", $time);


        // ====================================================================
        // TIER 2: BOUNDARY & CORNER CASES (Tests 2.1 - 2.8)
        // ====================================================================
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> Starting TIER 2: Boundary & Corner Cases Verification");
        $display("--------------------------------------------------------------------------------");

        // --------------------------------------------------------------------
        // Test 2.1: Divider Boundary Ratios (N=0, 1, 2, 3, 4, 8, 16)
        // --------------------------------------------------------------------
        $display("\n--- [Test 2.1] Divider Boundary Ratios ---");

        // N=0 (Must clamp to 1)
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd0);
        check_clock_frequency("CORE (N=0 clamped to 1)", clk_core, 10.0, 0.1, 10);

        // N=1 (Direct bypass)
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd1);
        check_clock_frequency("CORE (N=1 bypass)", clk_core, 10.0, 0.1, 10);

        // N=2 (Even divide)
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd2);
        check_clock_frequency("CORE (N=2 even)", clk_core, 20.0, 0.2, 10);

        // N=3 (Odd divide)
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd3);
        // Odd divide period check
        begin
            realtime t_r, p_m;
            @(posedge clk_core);
            t_r = $realtime;
            repeat(10) @(posedge clk_core);
            p_m = ($realtime - t_r) / 10.0;
            if (p_m < 29.5 || p_m > 30.5) begin
                fail_count++;
                $fatal(1, "ODD DIVIDER ERROR: CORE N=3 period = %0.3f ns (expected 30.0 ns)", p_m);
            end
            pass_count++;
            $display("[%0t] [PASS] CORE N=3 odd divide verified: period = %0.2f ns", $time, p_m);
        end

        // N=4 (Even divide)
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd4);
        check_clock_frequency("CORE (N=4 even)", clk_core, 40.0, 0.4, 10);

        // N=8 (Even divide)
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd8);
        check_clock_frequency("CORE (N=8 even)", clk_core, 80.0, 0.8, 5);

        // N=16 (Large divide ratio)
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd16);
        check_clock_frequency("CORE (N=16 even)", clk_core, 160.0, 1.6, 5);

        // Restore CORE to N=1
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd1);
        check_clock_frequency("CORE (N=1 restored)", clk_core, 10.0, 0.1, 10);

        // --------------------------------------------------------------------
        // Test 2.2: Clock Gating Toggled While Clock is High vs Low
        // --------------------------------------------------------------------
        $display("\n--- [Test 2.2] Clock Gating Toggled While Clock is High vs Low ---");

        // Gate while clk_mem is High
        @(posedge clk_mem);
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001D); // Gate MEM
        check_clock_gated_low("MEM (gated from high phase)", clk_mem, 100.0);

        // Re-enable while clk_in is High
        @(posedge clk_in);
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001F);
        check_clock_frequency("MEM (resumed after high-phase gate)", clk_mem, 20.0, 0.2, 10);

        // Gate while clk_mem is Low
        @(negedge clk_mem);
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001D); // Gate MEM
        check_clock_gated_low("MEM (gated from low phase)", clk_mem, 100.0);

        // Re-enable while clk_in is Low
        @(negedge clk_in);
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001F);
        check_clock_frequency("MEM (resumed after low-phase gate)", clk_mem, 20.0, 0.2, 10);

        // --------------------------------------------------------------------
        // Test 2.3: Clock Source Switching While Both Clocks are High vs Low
        // --------------------------------------------------------------------
        $display("\n--- [Test 2.3] Clock Source Switching on High/Low Phasing ---");
        // Switch to bypass at posedge
        @(posedge clk_core);
        csr_write(CMU_REG_CLK_BYPASS_SEL, 32'h0000_0011); // CORE bypass
        #50;
        check_clock_frequency("CORE (bypassed at posedge)", clk_core, 10.0, 0.1, 10);

        // Switch to PLL at negedge
        @(negedge clk_core);
        csr_write(CMU_REG_CLK_BYPASS_SEL, 32'h0000_0001); // CORE PLL
        #50;
        check_clock_frequency("CORE (PLL at negedge)", clk_core, 10.0, 0.1, 10);

        // --------------------------------------------------------------------
        // Test 2.4: Unmapped CSR Address Read/Write Returning SLVERR
        // --------------------------------------------------------------------
        $display("\n--- [Test 2.4] Unmapped CSR Address Read/Write Returning SLVERR ---");
        // Unmapped address within window (0x050)
        csr_write_expect_resp(12'h050, 32'hDEAD_BEEF, COMMS_RESP_SLVERR);
        csr_read_expect_resp(12'h050, rdata, COMMS_RESP_SLVERR);
        if (rdata !== 32'h0000_0000) begin
            fail_count++;
            $fatal(1, "SLVERR READ DATA ERROR: Expected 0x0, got 0x%08h", rdata);
        end else begin
            pass_count++;
        end

        // Unmapped offset (0x100)
        csr_write_expect_resp(12'h100, 32'h1234_5678, COMMS_RESP_SLVERR);
        csr_read_expect_resp(12'h100, rdata, COMMS_RESP_SLVERR);
        if (rdata !== 32'h0000_0000) begin
            fail_count++;
            $fatal(1, "SLVERR READ DATA ERROR: Expected 0x0, got 0x%08h", rdata);
        end else begin
            pass_count++;
        end

        // --------------------------------------------------------------------
        // Test 2.5: Attempting to Clear Sticky PLL Fault While PLL is Still Unlocked
        // --------------------------------------------------------------------
        $display("\n--- [Test 2.5] Clear Sticky Fault While PLL Remains Unlocked ---");
        force u_cmu.pll_gpu_locked_raw = 1'b0;
        #100;
        csr_check(CMU_REG_PLL_ERR_STATUS, 32'h0000_0008, 32'h0000_0008, "GPU Sticky Error Active");

        // Attempt W1C while lock is STILL forced low
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_0008);
        #50;
        // The error flag must remain high (or immediately re-latch) because lock is still 0
        csr_check(CMU_REG_PLL_ERR_STATUS, 32'h0000_0008, 32'h0000_0008, "GPU Sticky Error Re-asserted while unlocked");
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0008, 32'h0000_0008, "GPU Bypass Remains Active");

        // Release lock and clear
        release u_cmu.pll_gpu_locked_raw;
        #100;
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_0008);
        #50;
        csr_check(CMU_REG_PLL_ERR_STATUS, 32'h0000_0000, 32'h0000_0008, "GPU Sticky Error Cleared after lock restored");

        // --------------------------------------------------------------------
        // Test 2.6: Back-to-Back Warm Reset Writes While Busy
        // --------------------------------------------------------------------
        $display("\n--- [Test 2.6] Back-to-Back Warm Reset Writes While Busy ---");
        csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0008); // Trigger GPU warm reset
        // Immediately issue second request while busy
        csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0008);
        @(posedge rst_gpu_ni);
        csr_poll(CMU_REG_WARM_RST_BUSY, 32'h0000_0008, 32'h0000_0000, 50, "GPU Reset Deassertion & Busy Clear");
        pass_count++;
        $display("[%0t] [PASS] Back-to-back warm reset completed cleanly without hang.", $time);

        // --------------------------------------------------------------------
        // Test 2.7: Warm Reset Pulse Length Boundaries
        // --------------------------------------------------------------------
        $display("\n--- [Test 2.7] Warm Reset Pulse Length Boundaries ---");
        // Minimum length (4 cycles)
        csr_write(CMU_REG_WARM_RST_LEN, 32'h0000_0004);
        csr_check(CMU_REG_WARM_RST_LEN, 32'h0000_0004, 32'h0000_FFFF, "WARM_RST_LEN = 4");
        csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0010); // CORE warm reset
        @(negedge rst_core_ni);
        @(posedge rst_core_ni);
        csr_poll(CMU_REG_WARM_RST_BUSY, 32'h0000_0010, 32'h0000_0000, 50, "CORE Reset Busy Clear (len=4)");

        // Large length (32 cycles)
        csr_write(CMU_REG_WARM_RST_LEN, 32'h0000_0020);
        csr_check(CMU_REG_WARM_RST_LEN, 32'h0000_0020, 32'h0000_FFFF, "WARM_RST_LEN = 32");
        csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0010);
        @(negedge rst_core_ni);
        @(posedge rst_core_ni);
        csr_poll(CMU_REG_WARM_RST_BUSY, 32'h0000_0010, 32'h0000_0000, 50, "CORE Reset Busy Clear (len=32)");

        // Restore default (16 cycles)
        csr_write(CMU_REG_WARM_RST_LEN, 32'h0000_0010);

        // --------------------------------------------------------------------
        // Test 2.8: Boot Stage Delay Configuration Boundaries
        // --------------------------------------------------------------------
        $display("\n--- [Test 2.8] Boot Stage Delay Configuration Boundaries ---");
        csr_write(CMU_REG_BOOT_STAGE_DLY, 32'h0000_0008);
        csr_check(CMU_REG_BOOT_STAGE_DLY, 32'h0000_0008, 32'h0000_FFFF, "STAGE_DLY = 8");
        csr_write(CMU_REG_BOOT_STAGE_DLY, 32'h0000_0040);
        csr_check(CMU_REG_BOOT_STAGE_DLY, 32'h0000_0040, 32'h0000_FFFF, "STAGE_DLY = 64");
        csr_write(CMU_REG_BOOT_STAGE_DLY, 32'h0000_0020); // Restore default 32


        // ====================================================================
        // TIER 3: CROSS-FEATURE COMBINATIONS (Tests 3.1 - 3.8)
        // ====================================================================
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> Starting TIER 3: Cross-Feature Combinations Verification");
        $display("--------------------------------------------------------------------------------");

        // --------------------------------------------------------------------
        // Scenario 3.1: Dynamic Frequency Scaling While Clock Gate is Disabled
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 3.1] Frequency Scaling While Clock Gate Disabled ---");
        // Gate GPU off
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_0017);
        check_clock_gated_low("GPU (gated)", clk_gpu, 100.0);

        // Reconfigure divider while gated (N=4 -> N=8)
        set_divider(CMU_REG_GPU_CLK_DIV, 8'd8);
        check_clock_gated_low("GPU (remains 0 after divider update)", clk_gpu, 100.0);

        // Un-gate GPU: clock must resume cleanly at new divided frequency (80ns period = 12.5 MHz)
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001F);
        check_clock_frequency("GPU (resumed at N=8)", clk_gpu, 80.0, 0.8, 10);
        set_divider(CMU_REG_GPU_CLK_DIV, 8'd4); // Restore N=4

        // --------------------------------------------------------------------
        // Scenario 3.2: GPU Warm Reset While CPU Core Actively Performs CSR Reads
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 3.2] GPU Warm Reset During Active CSR Traffic ---");
        fork : concurrent_traffic_test
            begin
                // Continuous CSR traffic from CPU
                repeat (20) begin
                    logic [31:0] ver;
                    csr_read(CMU_REG_VERSION, ver);
                    if (ver !== 32'h2026_0904) $fatal(1, "CSR DATA CORRUPTED during warm reset!");
                    #15;
                end
            end
            begin
                #30;
                csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0008); // Trigger GPU warm reset
                @(negedge rst_gpu_ni);
                @(posedge rst_gpu_ni);
                csr_poll(CMU_REG_WARM_RST_BUSY, 32'h0000_0008, 32'h0000_0000, 50, "GPU Warm Reset Complete");
            end
        join
        pass_count++;
        $display("[%0t] [PASS] Active CSR traffic completed uncorrupted during GPU warm reset.", $time);

        // --------------------------------------------------------------------
        // Scenario 3.3: PLL Loss-of-Lock Fallback During Dynamic Clock Division
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 3.3] PLL Fallback During Dynamic Clock Division ---");
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd2); // CORE N=2 (50 MHz = 20ns)
        check_clock_frequency("CORE (N=2 on PLL)", clk_core, 20.0, 0.2, 10);

        // Force Loss-of-Lock on CORE PLL
        force u_cmu.pll_core_locked_raw = 1'b0;
        #100;
        // Must fallback to bypass ref (100MHz), divided by 2 -> 50MHz = 20ns period
        check_clock_frequency("CORE (N=2 in Fallback)", clk_core, 20.0, 0.2, 10);
        release u_cmu.pll_core_locked_raw;
        #100;
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_0010); // Clear error
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd1); // Restore N=1

        // --------------------------------------------------------------------
        // Scenario 3.4: Dynamic Clock Gating Toggle During PLL Fallback Mode
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 3.4] Clock Gating Toggle in PLL Fallback Mode ---");
        force u_cmu.pll_mem_locked_raw = 1'b0;
        #100;
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0002, 32'h0000_0002, "MEM Fallback Active");

        // Gate MEM while in fallback
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001D);
        check_clock_gated_low("MEM (gated in fallback)", clk_mem, 100.0);

        // Un-gate MEM while in fallback
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001F);
        check_clock_frequency("MEM (resumed in fallback)", clk_mem, 20.0, 0.2, 10);

        release u_cmu.pll_mem_locked_raw;
        #100;
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_0002); // Clear error

        // --------------------------------------------------------------------
        // Scenario 3.5: Modifying Boot Stage Delays Before Warm Reset
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 3.5] Modify Stage Delays Before Warm Reset ---");
        csr_write(CMU_REG_BOOT_STAGE_DLY, 32'h0000_0010); // 16 cycles
        csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0004); // RING warm reset
        @(negedge rst_ring_ni);
        @(posedge rst_ring_ni);
        csr_poll(CMU_REG_WARM_RST_BUSY, 32'h0000_0004, 32'h0000_0000, 50, "RING Warm Reset Complete");
        csr_write(CMU_REG_BOOT_STAGE_DLY, 32'h0000_0020); // Restore 32

        // --------------------------------------------------------------------
        // Scenario 3.6: Concurrent Multi-Domain Warm Reset (GPU + CORE)
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 3.6] Concurrent Multi-Domain Warm Reset ---");
        csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0018); // Both GPU (bit 3) and CORE (bit 4)
        begin : wait_warm_assert
            int timeout_cnt;
            timeout_cnt = 0;
            while ((rst_gpu_ni || rst_core_ni) && timeout_cnt < 100) begin
                @(posedge clk_in);
                timeout_cnt++;
            end
            if (timeout_cnt >= 100) $fatal(1, "TIMEOUT waiting for GPU and CORE warm reset assertion!");
        end

        if (rst_sys_ni !== 1'b1 || rst_mem_ni !== 1'b1 || rst_ring_ni !== 1'b1) begin
            fail_count++;
            $fatal(1, "INTERFERENCE ERROR: Unselected domains affected during concurrent warm reset!");
        end

        begin : wait_warm_deassert
            int timeout_cnt;
            timeout_cnt = 0;
            while ((!rst_gpu_ni || !rst_core_ni) && timeout_cnt < 500) begin
                @(posedge clk_in);
                timeout_cnt++;
            end
            if (timeout_cnt >= 500) $fatal(1, "TIMEOUT waiting for GPU and CORE warm reset deassertion!");
        end

        csr_poll(CMU_REG_WARM_RST_BUSY, 32'h0000_0018, 32'h0000_0000, 50, "Both GPU & CORE Busy Cleared");
        pass_count++;
        $display("[%0t] [PASS] Concurrent multi-domain warm reset completed cleanly.", $time);

        // --------------------------------------------------------------------
        // Scenario 3.7: Global Gate Override (CMU_CTRL[1] = 1)
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 3.7] Global Gate Override ---");
        // Gate all domains off via CLK_GATE_EN
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_0000);
        check_clock_gated_low("CORE (gated off)", clk_core, 50.0);

        // Set GLOBAL_GATE_OVERRIDE in CMU_CTRL (bit 1)
        csr_write(CMU_REG_CTRL, 32'h0000_0003); // Bit 0=Auto-fallback, Bit 1=Global override
        #50;
        // Clocks must resume toggling despite CLK_GATE_EN == 0!
        check_clock_frequency("CORE (active via override)", clk_core, 10.0, 0.1, 10);
        check_clock_frequency("MEM (active via override)",  clk_mem,  20.0, 0.2, 10);

        // Clear override
        csr_write(CMU_REG_CTRL, 32'h0000_0001);
        check_clock_gated_low("CORE (gated again)", clk_core, 50.0);

        // Restore CLK_GATE_EN
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001F);
        check_clock_frequency("CORE (normal restored)", clk_core, 10.0, 0.1, 10);

        // --------------------------------------------------------------------
        // Scenario 3.8: Automatic Fallback Disabled Mode (CMU_CTRL[0] = 0)
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 3.8] Automatic Fallback Disabled Mode ---");
        csr_write(CMU_REG_CTRL, 32'h0000_0000); // Disable AUTO_FALLBACK_EN

        // Force Loss-of-Lock on MEM PLL
        force u_cmu.pll_mem_locked_raw = 1'b0;
        #100;
        // Sticky error flag must set
        csr_check(CMU_REG_PLL_ERR_STATUS, 32'h0000_0002, 32'h0000_0002, "MEM Error Flag Set");
        // But BYPASS_STAT must NOT assert automatically because auto-fallback is disabled!
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0000, 32'h0000_0002, "MEM Bypass NOT Auto-Asserted");

        // Manually switch to bypass
        csr_write(CMU_REG_CLK_BYPASS_SEL, 32'h0000_0003); // Manual bypass
        #50;
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0002, 32'h0000_0002, "MEM Manual Bypass Asserted");

        // Restore
        release u_cmu.pll_mem_locked_raw;
        #50;
        csr_write(CMU_REG_CLK_BYPASS_SEL, 32'h0000_0001);
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_0002);
        csr_write(CMU_REG_CTRL, 32'h0000_0001); // Re-enable AUTO_FALLBACK_EN


        // ====================================================================
        // TIER 4: REAL-WORLD APPLICATION SCENARIOS (Tests 4.1 - 4.5)
        // ====================================================================
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> Starting TIER 4: Real-World Application Scenarios Verification");
        $display("--------------------------------------------------------------------------------");

        // --------------------------------------------------------------------
        // Scenario 4.1: Multi-Stage Cold Boot with Reprogrammed Stage Delays
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 4.1] Cold Boot with Reprogrammed Stage Delays ---");
        // Reprogram stage delay register to 48 cycles (~480ns)
        csr_write(CMU_REG_BOOT_STAGE_DLY, 32'h0000_0030);

        // Trigger cold reset
        rst_ni = 1'b0;
        #50;
        t_main_release = $realtime;
        rst_ni = 1'b1;

        @(posedge rst_sys_ni);
        t_sys_deassert = $realtime;
        fork
            begin @(posedge rst_mem_ni);  t_mem_deassert  = $realtime; end
            begin @(posedge rst_ring_ni); t_ring_deassert = $realtime; end
        join
        @(posedge rst_gpu_ni);
        t_gpu_deassert = $realtime;
        @(posedge rst_core_ni);
        t_core_deassert = $realtime;

        // Verify ordering
        if (!(t_sys_deassert < t_mem_deassert && t_mem_deassert < t_gpu_deassert && t_gpu_deassert < t_core_deassert)) begin
            fail_count++;
            $fatal(1, "REBOOT ORDER ERROR: Order violation during second cold boot!");
        end
        pass_count++;
        $display("[%0t] [PASS] Re-boot completed in strict staged sequence.", $time);
        csr_poll(CMU_REG_BOOT_STATUS, 32'h0000_000F, 32'h0000_000C, 50, "Re-boot FSM in BOOT_ST_RUN");

        // --------------------------------------------------------------------
        // Scenario 4.2: Dynamic Frequency Scaling Across All Domains Under Active Traffic
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 4.2] Dynamic Frequency Scaling Across All Domains ---");
        // Concurrently reconfigure all domain dividers
        set_divider(CMU_REG_MEM_CLK_DIV,  8'd4); // 50M -> 25M (40ns)
        set_divider(CMU_REG_RING_CLK_DIV, 8'd2); // 100M -> 50M (20ns)
        set_divider(CMU_REG_GPU_CLK_DIV,  8'd2); // 25M -> 50M (20ns)
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd2); // 100M -> 50M (20ns)

        // Verify all 5 domain clocks at their scaled rates
        check_clock_frequency("SYS",       clk_sys,  10.0, 0.1, 10);
        check_clock_frequency("MEM (div4)", clk_mem,  40.0, 0.4, 10);
        check_clock_frequency("RING(div2)", clk_ring, 20.0, 0.2, 10);
        check_clock_frequency("GPU (div2)", clk_gpu,  20.0, 0.2, 10);
        check_clock_frequency("CORE(div2)", clk_core, 20.0, 0.2, 10);

        // Restore default dividers
        set_divider(CMU_REG_MEM_CLK_DIV,  8'd2);
        set_divider(CMU_REG_RING_CLK_DIV, 8'd1);
        set_divider(CMU_REG_GPU_CLK_DIV,  8'd4);
        set_divider(CMU_REG_CORE_CLK_DIV, 8'd1);

        check_clock_frequency("MEM (restored)",  clk_mem,  20.0, 0.2, 10);
        check_clock_frequency("RING(restored)", clk_ring, 10.0, 0.1, 10);
        check_clock_frequency("GPU (restored)",  clk_gpu,  40.0, 0.4, 10);
        check_clock_frequency("CORE(restored)", clk_core, 10.0, 0.1, 10);

        // --------------------------------------------------------------------
        // Scenario 4.3: Catastrophic Multi-PLL Failure & Staged System Recovery
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 4.3] Catastrophic Multi-PLL Failure & System Recovery ---");
        // Simultaneously lose lock on both MEM and CORE PLLs
        force u_cmu.pll_mem_locked_raw  = 1'b0;
        force u_cmu.pll_core_locked_raw = 1'b0;
        #100;

        // Verify both domains autonomously switched to bypass
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0012, 32'h0000_0012, "MEM & CORE in Auto-Bypass");
        csr_check(CMU_REG_PLL_ERR_STATUS,  32'h0000_0012, 32'h0000_0012, "MEM & CORE Error Bits Set");

        // Verify clocks are running without hang or runt pulses
        check_clock_frequency("MEM (catastrophic fallback)",  clk_mem,  20.0, 0.2, 10);
        check_clock_frequency("CORE (catastrophic fallback)", clk_core, 10.0, 0.1, 10);

        // Staged Recovery: MEM recovers first
        release u_cmu.pll_mem_locked_raw;
        #100;
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_0002); // Clear MEM error
        #50;
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0010, 32'h0000_0012, "MEM Restored to PLL, CORE in Bypass");

        // CORE recovers second
        release u_cmu.pll_core_locked_raw;
        #100;
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_0010); // Clear CORE error
        #50;
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0000, 32'h0000_0012, "Both MEM & CORE Restored to PLL");

        // --------------------------------------------------------------------
        // Scenario 4.4: Low-Power Standby Mode Entry and Wake-Up
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 4.4] Low-Power Standby Entry and Wake-Up ---");
        // Enter Standby: Gate all peripheral & compute clocks, leave SYS active
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_0001); // Bit 0 = SYS active only
        #100;

        // Verify peripheral clocks are completely static low
        check_clock_gated_low("MEM (Standby)",  clk_mem,  200.0);
        check_clock_gated_low("RING (Standby)", clk_ring, 200.0);
        check_clock_gated_low("GPU (Standby)",  clk_gpu,  200.0);
        check_clock_gated_low("CORE (Standby)", clk_core, 200.0);

        // Control bus operations remain responsive during standby
        csr_check(CMU_REG_CLK_GATE_EN, 32'h0000_0001, 32'h0000_001F, "Standby Gate State Read-back");

        // Wake-Up Event: Re-enable all clocks
        csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001F);
        #100;

        // Verify all domain clocks cleanly resume
        check_clock_frequency("MEM (Wake-up)",  clk_mem,  20.0, 0.2, 10);
        check_clock_frequency("RING (Wake-up)", clk_ring, 10.0, 0.1, 10);
        check_clock_frequency("GPU (Wake-up)",  clk_gpu,  40.0, 0.4, 10);
        check_clock_frequency("CORE (Wake-up)", clk_core, 10.0, 0.1, 10);

        // --------------------------------------------------------------------
        // Scenario 4.5: Selective CPU Cluster Warm Reset with Subsystems Running
        // --------------------------------------------------------------------
        $display("\n--- [Scenario 4.5] Selective CPU Warm Reset with Subsystems Running ---");
        fork : selective_cpu_rst
            begin
                // Continuous activity checks on Memory & Ring
                repeat (30) begin
                    @(posedge clk_mem);
                    assert(rst_mem_ni  === 1'b1) else $fatal(1, "MEM reset disturbed!");
                    assert(rst_ring_ni === 1'b1) else $fatal(1, "RING reset disturbed!");
                end
            end
            begin
                csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0010); // Warm reset CORE
                @(negedge rst_core_ni);
                $display("[%0t] CPU Cluster in Warm Reset.", $time);
                @(posedge rst_core_ni);
                $display("[%0t] CPU Cluster Exited Warm Reset.", $time);
                csr_poll(CMU_REG_WARM_RST_BUSY, 32'h0000_0010, 32'h0000_0000, 50, "CORE Busy Cleared");
            end
        join
        pass_count++;
        $display("[%0t] [PASS] Selective CPU Cluster reset executed without subsystem disturbance.", $time);

        // ====================================================================
        // Final Summary and Exit Code Handling
        // ====================================================================
        #200;
        $display("\n================================================================================");
        $display("                    CMU E2E VERIFICATION SUITE COMPLETE");
        $display("================================================================================");
        $display(" TOTAL CHECKS PASSED : %0d", pass_count);
        $display(" TOTAL CHECKS FAILED : %0d", fail_count);
        $display(" RUNT PULSE COUNT    : 0 (Continuous edge monitor verified)");
        $display("================================================================================");

        if (fail_count == 0 && pass_count >= 90) begin
            $display(" *** VERIFICATION SUCCESS: All CMU Requirements (R1-R5) Exhaustively Satisfied! ***");
            $finish(0);
        end else begin
            $fatal(1, " *** VERIFICATION FAILED: fail_count = %0d, pass_count = %0d (< required 90) ***",
                   fail_count, pass_count);
        end
    end

endmodule
