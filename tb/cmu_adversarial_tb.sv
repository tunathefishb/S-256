`timescale 1ns/1ps

// ============================================================================
// Tier 5 Adversarial Verification Testbench for S-256 CMU
// Focus: PLL loss-of-lock fault injection, concurrent warm resets, CSR hazards
// ============================================================================

module adv_runt_pulse_monitor #(
    parameter string DOMAIN_NAME     = "UNKNOWN",
    parameter real   MIN_PULSE_WIDTH = 4.8 // ns (100MHz reference half-period = 5.0ns)
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


module cmu_adversarial_tb;

    import soc_pkg::*;

    // ------------------------------------------------------------------------
    // Clock & Reset Signals
    // ------------------------------------------------------------------------
    logic clk_in;
    logic rst_ni;

    // Domain Clocks and Synchronized Resets
    logic clk_sys,  rst_sys_ni;
    logic clk_mem,  rst_mem_ni;
    logic clk_ring, rst_ring_ni;
    logic clk_gpu,  rst_gpu_ni;
    logic clk_core, rst_core_ni;

    // Bus Interface
    comms_bus_if comms_if(clk_in);

    // Monitoring & Statistics
    int pass_count = 0;
    int fail_count = 0;
    logic runt_mon_en = 1'b0;

    // Ticket Lock for Concurrent Bus Arbitration
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

    // Clock Generation: 100MHz Reference Clock (Period = 10.0ns)
    initial begin
        clk_in = 1'b0;
        forever #5.0 clk_in = ~clk_in;
    end

    // ------------------------------------------------------------------------
    // Device Under Test (DUT)
    // ------------------------------------------------------------------------
    cmu u_cmu (
        .clk_in     (clk_in),
        .rst_ni     (rst_ni),
        .bus_addr   (comms_if.addr),
        .bus_wdata  (comms_if.wdata),
        .bus_wen    (comms_if.wen),
        .bus_ren    (comms_if.ren),
        .bus_valid  (comms_if.valid),
        .bus_ready  (comms_if.ready),
        .bus_rdata  (comms_if.rdata),
        .bus_resp   (comms_if.resp),
        .clk_sys    (clk_sys),
        .rst_sys_ni (rst_sys_ni),
        .clk_mem    (clk_mem),
        .rst_mem_ni (rst_mem_ni),
        .clk_ring   (clk_ring),
        .rst_ring_ni(rst_ring_ni),
        .clk_gpu    (clk_gpu),
        .rst_gpu_ni (rst_gpu_ni),
        .clk_core   (clk_core),
        .rst_core_ni(rst_core_ni)
    );

    // Continuous Runt Pulse Monitors across all 5 Domains
    adv_runt_pulse_monitor #(.DOMAIN_NAME("SYS"),  .MIN_PULSE_WIDTH(4.8)) u_runt_sys  (.clk(clk_sys),  .monitor_en(runt_mon_en));
    adv_runt_pulse_monitor #(.DOMAIN_NAME("MEM"),  .MIN_PULSE_WIDTH(4.8)) u_runt_mem  (.clk(clk_mem),  .monitor_en(runt_mon_en));
    adv_runt_pulse_monitor #(.DOMAIN_NAME("RING"), .MIN_PULSE_WIDTH(4.8)) u_runt_ring (.clk(clk_ring), .monitor_en(runt_mon_en));
    adv_runt_pulse_monitor #(.DOMAIN_NAME("GPU"),  .MIN_PULSE_WIDTH(4.8)) u_runt_gpu  (.clk(clk_gpu),  .monitor_en(runt_mon_en));
    adv_runt_pulse_monitor #(.DOMAIN_NAME("CORE"), .MIN_PULSE_WIDTH(4.8)) u_runt_core (.clk(clk_core), .monitor_en(runt_mon_en));

    // ------------------------------------------------------------------------
    // CSR Access Tasks
    // ------------------------------------------------------------------------
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
        input logic [31:0] full_addr,
        input logic [31:0] data,
        input logic [1:0]  expected_resp
    );
        acquire_bus();
        @(posedge clk_in);
        comms_if.addr  <= full_addr;
        comms_if.wdata <= data;
        comms_if.cmd   <= data;
        comms_if.wen   <= 1'b1;
        comms_if.ren   <= 1'b0;
        comms_if.valid <= 1'b1;

        @(posedge clk_in);
        while (!comms_if.ready) @(posedge clk_in);

        if (comms_if.resp !== expected_resp) begin
            fail_count++;
            $fatal(1, "[%0t] CSR WRITE RESP MISMATCH: Expected %b, Got %b on addr 0x%08h",
                   $time, expected_resp, comms_if.resp, full_addr);
        end else begin
            pass_count++;
        end

        comms_if.valid <= 1'b0;
        comms_if.wen   <= 1'b0;
        @(posedge clk_in);
        release_bus();
    endtask

    task automatic csr_read_expect_resp(
        input  logic [31:0] full_addr,
        output logic [31:0] data,
        input  logic [1:0]  expected_resp
    );
        acquire_bus();
        @(posedge clk_in);
        comms_if.addr  <= full_addr;
        comms_if.wen   <= 1'b0;
        comms_if.ren   <= 1'b1;
        comms_if.valid <= 1'b1;

        @(posedge clk_in);
        while (!comms_if.ready) @(posedge clk_in);

        data = comms_if.rdata;

        if (comms_if.resp !== expected_resp) begin
            fail_count++;
            $fatal(1, "[%0t] CSR READ RESP MISMATCH: Expected %b, Got %b on addr 0x%08h",
                   $time, expected_resp, comms_if.resp, full_addr);
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

    // Frequency measurement helper with domain selection
    task automatic check_clock_frequency(
        input string     domain_name,
        input real       expected_period_ns,
        input real       tolerance_ns,
        input int        cycles_to_measure
    );
        realtime t_rise, t_fall, period_measured, high_time_measured;
        int cycle_count;
        cycle_count = 0;

        case (domain_name[0])
            "S": begin
                @(posedge clk_sys);
                while (cycle_count < cycles_to_measure) begin
                    t_rise = $realtime;
                    @(negedge clk_sys);
                    t_fall = $realtime;
                    high_time_measured = t_fall - t_rise;
                    @(posedge clk_sys);
                    period_measured = $realtime - t_rise;

                    if (period_measured < (expected_period_ns - tolerance_ns) ||
                        period_measured > (expected_period_ns + tolerance_ns)) begin
                        fail_count++;
                        $fatal(1, "[%0t] FREQ ERROR: Domain %s period = %0.3f ns (expected %0.3f +- %0.3f ns)",
                               $time, domain_name, period_measured, expected_period_ns, tolerance_ns);
                    end
                    cycle_count++;
                end
            end

            "M": begin
                @(posedge clk_mem);
                while (cycle_count < cycles_to_measure) begin
                    t_rise = $realtime;
                    @(negedge clk_mem);
                    t_fall = $realtime;
                    high_time_measured = t_fall - t_rise;
                    @(posedge clk_mem);
                    period_measured = $realtime - t_rise;

                    if (period_measured < (expected_period_ns - tolerance_ns) ||
                        period_measured > (expected_period_ns + tolerance_ns)) begin
                        fail_count++;
                        $fatal(1, "[%0t] FREQ ERROR: Domain %s period = %0.3f ns (expected %0.3f +- %0.3f ns)",
                               $time, domain_name, period_measured, expected_period_ns, tolerance_ns);
                    end
                    cycle_count++;
                end
            end

            "R": begin
                @(posedge clk_ring);
                while (cycle_count < cycles_to_measure) begin
                    t_rise = $realtime;
                    @(negedge clk_ring);
                    t_fall = $realtime;
                    high_time_measured = t_fall - t_rise;
                    @(posedge clk_ring);
                    period_measured = $realtime - t_rise;

                    if (period_measured < (expected_period_ns - tolerance_ns) ||
                        period_measured > (expected_period_ns + tolerance_ns)) begin
                        fail_count++;
                        $fatal(1, "[%0t] FREQ ERROR: Domain %s period = %0.3f ns (expected %0.3f +- %0.3f ns)",
                               $time, domain_name, period_measured, expected_period_ns, tolerance_ns);
                    end
                    cycle_count++;
                end
            end

            "G": begin
                @(posedge clk_gpu);
                while (cycle_count < cycles_to_measure) begin
                    t_rise = $realtime;
                    @(negedge clk_gpu);
                    t_fall = $realtime;
                    high_time_measured = t_fall - t_rise;
                    @(posedge clk_gpu);
                    period_measured = $realtime - t_rise;

                    if (period_measured < (expected_period_ns - tolerance_ns) ||
                        period_measured > (expected_period_ns + tolerance_ns)) begin
                        fail_count++;
                        $fatal(1, "[%0t] FREQ ERROR: Domain %s period = %0.3f ns (expected %0.3f +- %0.3f ns)",
                               $time, domain_name, period_measured, expected_period_ns, tolerance_ns);
                    end
                    cycle_count++;
                end
            end

            "C": begin
                @(posedge clk_core);
                while (cycle_count < cycles_to_measure) begin
                    t_rise = $realtime;
                    @(negedge clk_core);
                    t_fall = $realtime;
                    high_time_measured = t_fall - t_rise;
                    @(posedge clk_core);
                    period_measured = $realtime - t_rise;

                    if (period_measured < (expected_period_ns - tolerance_ns) ||
                        period_measured > (expected_period_ns + tolerance_ns)) begin
                        fail_count++;
                        $fatal(1, "[%0t] FREQ ERROR: Domain %s period = %0.3f ns (expected %0.3f +- %0.3f ns)",
                               $time, domain_name, period_measured, expected_period_ns, tolerance_ns);
                    end
                    cycle_count++;
                end
            end

            default: $fatal(1, "Unknown domain: %s", domain_name);
        endcase

        pass_count++;
        $display("[%0t] [PASS] Domain %s verified: %0.2f MHz (%0.2f ns) over %0d cycles.",
                 $time, domain_name, 1000.0/period_measured, period_measured, cycles_to_measure);
    endtask

    // ------------------------------------------------------------------------
    // Main Adversarial Test Execution
    // ------------------------------------------------------------------------
    initial begin
        $display("================================================================================");
        $display("          TIER 5 ADVERSARIAL STRESS HARNESS: CMU HARDENING & CONCURRENCY");
        $display("================================================================================");

        csr_init();
        rst_ni = 1'b0;
        #100;
        rst_ni = 1'b1;

        // Wait for power-on boot sequence to complete
        @(posedge rst_core_ni);
        csr_poll(CMU_REG_BOOT_STATUS, 32'h0000_0008, 32'h0000_0008, 100, "Boot Sequencer RUN state");
        runt_mon_en = 1'b1;
        #200;
        $display("[%0t] Cold boot complete, enabling runt pulse monitors.", $time);

        // ====================================================================
        // CHALLENGE SUITE 1: Multi-PLL Catastrophic Loss-of-Lock & Fallback
        // ====================================================================
        $display("\n>>> CHALLENGE 1.1: Quad-PLL Simultaneous Loss-of-Lock Injection");
        // Configure divergent division ratios first
        csr_write(CMU_REG_MEM_CLK_DIV,  8'd2);  // 50 MHz  (20ns)
        csr_write(CMU_REG_RING_CLK_DIV, 8'd4);  // 25 MHz  (40ns)
        csr_write(CMU_REG_GPU_CLK_DIV,  8'd8);  // 12.5 MHz(80ns)
        csr_write(CMU_REG_CORE_CLK_DIV, 8'd1);  // 100 MHz (10ns)
        #200;

        // Verify initial frequencies
        check_clock_frequency("MEM (pre-fault)",  20.0, 0.2, 10);
        check_clock_frequency("RING(pre-fault)", 40.0, 0.4, 10);
        check_clock_frequency("GPU (pre-fault)",  80.0, 0.8, 10);
        check_clock_frequency("CORE(pre-fault)", 10.0, 0.1, 10);

        // INJECT CATASTROPHIC SIMULTANEOUS FAULT ON ALL 4 PLLs
        $display("[%0t] Injecting simultaneous lock loss on MEM, RING, GPU, and CORE PLLs...", $time);
        force u_cmu.pll_mem_locked_raw  = 1'b0;
        force u_cmu.pll_ring_locked_raw = 1'b0;
        force u_cmu.pll_gpu_locked_raw  = 1'b0;
        force u_cmu.pll_core_locked_raw = 1'b0;
        #100;

        // Verify all domains autonomously switched to bypass
        // Bit 0 (SYS) is always 1; bits [4:1] must all be 1 -> mask 0x1F, value 0x1F
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_001F, 32'h0000_001F, "Quad Bypass Active Status");
        csr_check(CMU_REG_PLL_ERR_STATUS,  32'h0000_001E, 32'h0000_001E, "Quad Loss-of-Lock Sticky Flags");
        csr_check(CMU_REG_STATUS,          32'h0000_0004, 32'h0000_0004, "Global Loss-of-Lock Status Bit");

        // Verify clocks are still running cleanly without stall or runt pulses
        check_clock_frequency("MEM (fallback div2)",  20.0, 0.2, 10);
        check_clock_frequency("RING(fallback div4)", 40.0, 0.4, 10);
        check_clock_frequency("GPU (fallback div8)",  80.0, 0.8, 10);
        check_clock_frequency("CORE(fallback div1)", 10.0, 0.1, 10);

        // --------------------------------------------------------------------
        $display("\n>>> CHALLENGE 1.2: Adversarial W1C Clear Attempt While PLLs Still Unlocked");
        // Attempt 1: Clear MEM sticky error while MEM PLL is still raw 0
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_0002);
        #50;
        csr_check(CMU_REG_PLL_ERR_STATUS,  32'h0000_001E, 32'h0000_001E, "Sticky Error Persists after targeted W1C");
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_001F, 32'h0000_001F, "Bypass Remains Engaged after targeted W1C");

        // Attempt 2: Broadcast clear attempt (write 0xFFFF_FFFF)
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'hFFFF_FFFF);
        #50;
        csr_check(CMU_REG_PLL_ERR_STATUS,  32'h0000_001E, 32'h0000_001E, "Sticky Errors Persist after broadcast W1C");
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_001F, 32'h0000_001F, "Bypass Remains Engaged after broadcast W1C");

        // Attempt 3: High-frequency burst write storm (10 back-to-back writes)
        repeat (10) begin
            csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_001E);
        end
        csr_check(CMU_REG_PLL_ERR_STATUS,  32'h0000_001E, 32'h0000_001E, "Sticky Errors Persist after 10-burst W1C storm");
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_001F, 32'h0000_001F, "Bypass Remains Engaged after 10-burst W1C storm");

        // Verify clock continuity under W1C storm
        check_clock_frequency("CORE (post-W1C-storm)", 10.0, 0.1, 10);

        // --------------------------------------------------------------------
        $display("\n>>> CHALLENGE 1.3: Debounce Delay & Staged Software Recovery");
        // Release MEM PLL lock
        release u_cmu.pll_mem_locked_raw;
        // Check immediate state: during debounce (e.g. at 20ns = 2 cycles), lock_filtered should NOT be high yet
        #20;
        csr_check(CMU_REG_PLL_STATUS, 32'h0000_0000, 32'h0000_0002, "MEM PLL Not Synced During Debounce");
        // Wait for debounce to finish (8 cycles * 10ns = 80ns)
        #100;
        csr_check(CMU_REG_PLL_STATUS, 32'h0000_0002, 32'h0000_0002, "MEM PLL Synced After Debounce");
        // CRITICAL CHECK: Even though PLL is locked, bypass MUST remain active because sticky flag is set!
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0002, 32'h0000_0002, "MEM Remains in Bypass Until Software Clears Sticky Err");

        // Software clears MEM sticky error
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_0002);
        #50;
        csr_check(CMU_REG_PLL_ERR_STATUS,  32'h0000_0000, 32'h0000_0002, "MEM Sticky Error Successfully Cleared");
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0000, 32'h0000_0002, "MEM Restored to PLL Clock");

        // Release and recover RING, GPU, and CORE
        release u_cmu.pll_ring_locked_raw;
        release u_cmu.pll_gpu_locked_raw;
        release u_cmu.pll_core_locked_raw;
        #150;
        csr_write(CMU_REG_PLL_ERR_STATUS, 32'h0000_001C); // Clear RING, GPU, CORE
        #50;
        csr_check(CMU_REG_PLL_ERR_STATUS,  32'h0000_0000, 32'h0000_001E, "All PLL Errors Cleared");
        csr_check(CMU_REG_CLK_BYPASS_STAT, 32'h0000_0001, 32'h0000_001F, "All Domains Restored to PLL (SYS in safe ref)");
        check_clock_frequency("MEM (recovered)",  20.0, 0.2, 10);
        check_clock_frequency("CORE (recovered)", 10.0, 0.1, 10);


        // ====================================================================
        // CHALLENGE SUITE 2: Concurrent Reset & Heavy CSR Traffic
        // ====================================================================
        $display("\n>>> CHALLENGE 2.1: Heavy CSR Read Bursts During Domain Warm Reset");
        fork : heavy_csr_traffic_mem_rst
            begin : traffic_gen
                logic [31:0] val;
                for (int i = 0; i < 30; i++) begin
                    csr_read(CMU_REG_VERSION, val);
                    if (val !== 32'h2026_0904) begin
                        fail_count++;
                        $fatal(1, "[%0t] CSR DATA CORRUPTION during MEM warm reset! Got 0x%08h", $time, val);
                    end
                    csr_read(CMU_REG_SYS_CLK_DIV, val);
                    if ((val & 32'hFF) !== 32'h1) begin
                        fail_count++;
                        $fatal(1, "[%0t] CSR DATA CORRUPTION on SYS_CLK_DIV! Got 0x%08h", $time, val);
                    end
                    #15;
                end
                pass_count++;
                $display("[%0t] [PASS] CSR read stream completed with 100%% data integrity.", $time);
            end

            begin : rst_trigger
                #40;
                $display("[%0t] Triggering MEM Warm Reset while CSR reads are active...", $time);
                csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0002);
                if (rst_mem_ni === 1'b1) @(negedge rst_mem_ni);
                $display("[%0t] MEM reset asserted.", $time);
                if (rst_mem_ni === 1'b0) @(posedge rst_mem_ni);
                $display("[%0t] MEM reset deasserted cleanly.", $time);
                csr_poll(CMU_REG_WARM_RST_BUSY, 32'h0000_0002, 32'h0000_0000, 50, "MEM Reset Busy Cleared");
            end

            begin : isolation_monitor
                // Ensure unselected domain resets NEVER glitch or assert
                repeat (120) begin
                    @(posedge clk_in);
                    if (rst_sys_ni  !== 1'b1) $fatal(1, "[%0t] ISOLATION FAILURE: SYS reset glitched!", $time);
                    if (rst_ring_ni !== 1'b1) $fatal(1, "[%0t] ISOLATION FAILURE: RING reset glitched!", $time);
                    if (rst_gpu_ni  !== 1'b1) $fatal(1, "[%0t] ISOLATION FAILURE: GPU reset glitched!", $time);
                    if (rst_core_ni !== 1'b1) $fatal(1, "[%0t] ISOLATION FAILURE: CORE reset glitched!", $time);
                end
                pass_count++;
                $display("[%0t] [PASS] Isolation verified: Unselected domains remained 100%% active.", $time);
            end
        join

        // --------------------------------------------------------------------
        $display("\n>>> CHALLENGE 2.2: Multi-Domain Concurrent Reset (GPU + CORE) Under CSR Traffic");
        fork : multi_domain_rst_traffic
            begin : traffic_gen2
                logic [31:0] val;
                for (int i = 0; i < 30; i++) begin
                    csr_read(CMU_REG_STATUS, val);
                    if (comms_if.resp !== COMMS_RESP_OKAY) begin
                        fail_count++;
                        $fatal(1, "[%0t] Bus response error during multi-domain reset!", $time);
                    end
                    #15;
                end
                pass_count++;
                $display("[%0t] [PASS] Continuous CSR reads during multi-reset completed with zero errors.", $time);
            end

            begin : rst_trigger2
                #30;
                $display("[%0t] Triggering concurrent warm reset on GPU and CORE...", $time);
                csr_write(CMU_REG_WARM_RST_REQ, 32'h0000_0018); // GPU (bit 3) + CORE (bit 4)
                if (rst_gpu_ni  === 1'b1) @(negedge rst_gpu_ni);
                if (rst_core_ni === 1'b1) @(negedge rst_core_ni);
                if (rst_gpu_ni  === 1'b0) @(posedge rst_gpu_ni);
                if (rst_core_ni === 1'b0) @(posedge rst_core_ni);
                csr_poll(CMU_REG_WARM_RST_BUSY, 32'h0000_0018, 32'h0000_0000, 50, "GPU and CORE Busy Cleared");
            end

            begin : isolation_monitor2
                repeat (120) begin
                    @(posedge clk_in);
                    if (rst_sys_ni  !== 1'b1) $fatal(1, "SYS reset disturbed during multi-reset!");
                    if (rst_mem_ni  !== 1'b1) $fatal(1, "MEM reset disturbed during multi-reset!");
                    if (rst_ring_ni !== 1'b1) $fatal(1, "RING reset disturbed during multi-reset!");
                end
                pass_count++;
                $display("[%0t] [PASS] Isolation during multi-reset: SYS, MEM, RING unaffected.", $time);
            end
        join


        // ====================================================================
        // CHALLENGE SUITE 3: CSR Hazards & Unmapped Address Stress Testing
        // ====================================================================
        $display("\n>>> CHALLENGE 3.1: Unmapped CSR Address Read/Write Stress");
        begin
            logic [31:0] unmapped_addrs [0:11];
            unmapped_addrs[0]  = 32'h1000_004C; // Internal hole (between RESET_STATUS and VERSION)
            unmapped_addrs[1]  = 32'h1000_0050; // Gap
            unmapped_addrs[2]  = 32'h1000_0060; // Gap
            unmapped_addrs[3]  = 32'h1000_00F8; // Gap before VERSION (0x0FC)
            unmapped_addrs[4]  = 32'h1000_0100; // Just beyond 256B block
            unmapped_addrs[5]  = 32'h1000_0400; // Middle of 4KB aperture
            unmapped_addrs[6]  = 32'h1000_0800; // Upper 4KB aperture
            unmapped_addrs[7]  = 32'h1000_0FFC; // End of 4KB aperture
            unmapped_addrs[8]  = 32'h1000_1000; // Boundary violation (Aperture + 1)
            unmapped_addrs[9]  = 32'h1001_0000; // Non-CMU address
            unmapped_addrs[10] = 32'h2000_0000; // Foreign address space
            unmapped_addrs[11] = 32'h0000_0000; // Zero address

            for (int i = 0; i < 12; i++) begin
                logic [31:0] target_addr;
                logic [31:0] rdata;
                target_addr = unmapped_addrs[i];

                // Test Write to unmapped address: must return SLVERR without hanging
                csr_write_expect_resp(target_addr, 32'hDEAD_BEEF, COMMS_RESP_SLVERR);

                // Test Read from unmapped address: must return SLVERR and 32'h0 without hanging
                csr_read_expect_resp(target_addr, rdata, COMMS_RESP_SLVERR);
                if (rdata !== 32'h0) begin
                    fail_count++;
                    $fatal(1, "[%0t] UNMAPPED READ ERROR: Expected 0x0 rdata, got 0x%08h on addr 0x%08h",
                           $time, rdata, target_addr);
                end else begin
                    pass_count++;
                end

                // Immediately follow with valid read to ensure bus interface has no stuck state
                csr_read(CMU_REG_VERSION, rdata);
                if (rdata !== 32'h2026_0904) begin
                    fail_count++;
                    $fatal(1, "[%0t] BUS HANG / RECOVERY ERROR after unmapped addr 0x%08h: got 0x%08h",
                           $time, target_addr, rdata);
                end else begin
                    pass_count++;
                end
            end
            $display("[%0t] [PASS] All 12 unmapped address boundary checks passed with SLVERR and immediate recovery.", $time);
        end

        // --------------------------------------------------------------------
        $display("\n>>> CHALLENGE 3.2: Zero-Wait-State Read-After-Write (RAW) Hazard");
        begin
            logic [31:0] readback;

            // RAW 1: MEM Divider
            csr_write(CMU_REG_MEM_CLK_DIV, 32'h0000_0006);
            csr_read(CMU_REG_MEM_CLK_DIV, readback);
            if ((readback & 32'hFF) !== 32'd6) begin
                fail_count++;
                $fatal(1, "[%0t] RAW HAZARD: MEM_CLK_DIV expected 6, got %0d", $time, readback);
            end else begin
                pass_count++;
            end

            // RAW 2: Boot Stage Delay
            csr_write(CMU_REG_BOOT_STAGE_DLY, 32'h0000_0045);
            csr_read(CMU_REG_BOOT_STAGE_DLY, readback);
            if ((readback & 32'hFFFF) !== 32'h45) begin
                fail_count++;
                $fatal(1, "[%0t] RAW HAZARD: BOOT_STAGE_DLY expected 0x45, got 0x%04h", $time, readback);
            end else begin
                pass_count++;
            end

            // RAW 3: Warm Reset Pulse Length
            csr_write(CMU_REG_WARM_RST_LEN, 32'h0000_0028);
            csr_read(CMU_REG_WARM_RST_LEN, readback);
            if ((readback & 32'hFFFF) !== 32'h28) begin
                fail_count++;
                $fatal(1, "[%0t] RAW HAZARD: WARM_RST_LEN expected 0x28, got 0x%04h", $time, readback);
            end else begin
                pass_count++;
            end

            $display("[%0t] [PASS] Zero-wait-state Read-After-Write hazards resolved without pipeline staleness.", $time);
        end

        // Restore default settings
        csr_write(CMU_REG_MEM_CLK_DIV,  8'd2);
        csr_write(CMU_REG_RING_CLK_DIV, 8'd1);
        csr_write(CMU_REG_GPU_CLK_DIV,  8'd4);
        csr_write(CMU_REG_CORE_CLK_DIV, 8'd1);
        csr_write(CMU_REG_WARM_RST_LEN, 16'd16);
        csr_write(CMU_REG_BOOT_STAGE_DLY, 16'd32);

        #300;
        $display("\n================================================================================");
        $display("          ADVERSARIAL VERIFICATION COMPLETE — ZERO FAILURES OBSERVED");
        $display("================================================================================");
        $display(" TOTAL ADVERSARIAL CHECKS PASSED : %0d", pass_count);
        $display(" TOTAL ADVERSARIAL CHECKS FAILED : %0d", fail_count);
        $display(" RUNT PULSE COUNT                : 0 (Continuous monitor verified)");
        $display("================================================================================");

        if (fail_count == 0) begin
            $display(" *** EMPIRICAL CHALLENGE VERDICT: APPROVE ***");
            $finish(0);
        end else begin
            $display(" *** EMPIRICAL CHALLENGE VERDICT: REQUEST_CHANGES ***");
            $finish(1);
        end
    end

endmodule
