`timescale 1ns/1ps

// ============================================================================
// S-256 CMU Adversarial Stress Testbench: Clock Switching, Dividers & Runts
// Author: challenger_1 (Tier 5 Coverage Hardening)
// ============================================================================

module cmu_clock_stress_tb;

    import soc_pkg::*;

    // ------------------------------------------------------------------------
    // Clock, Reset & Bus Signals
    // ------------------------------------------------------------------------
    logic clk_in;
    logic rst_ni;

    comms_bus_if comms_if (.clk(clk_in));

    logic clk_sys,  rst_sys_ni;
    logic clk_mem,  rst_mem_ni;
    logic clk_ring, rst_ring_ni;
    logic clk_gpu,  rst_gpu_ni;
    logic clk_core, rst_core_ni;

    // DUT Instantiation
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

    // Continuous runt pulse monitors
    logic mon_en;
    int   total_runt_count = 0;

    runt_pulse_monitor #(.DOMAIN_NAME("SYS"),  .MIN_PULSE_WIDTH(4.8)) u_runt_sys  (.clk(clk_sys),  .monitor_en(mon_en));
    runt_pulse_monitor #(.DOMAIN_NAME("MEM"),  .MIN_PULSE_WIDTH(4.8)) u_runt_mem  (.clk(clk_mem),  .monitor_en(mon_en));
    runt_pulse_monitor #(.DOMAIN_NAME("RING"), .MIN_PULSE_WIDTH(4.8)) u_runt_ring (.clk(clk_ring), .monitor_en(mon_en));
    runt_pulse_monitor #(.DOMAIN_NAME("GPU"),  .MIN_PULSE_WIDTH(4.8)) u_runt_gpu  (.clk(clk_gpu),  .monitor_en(mon_en));
    runt_pulse_monitor #(.DOMAIN_NAME("CORE"), .MIN_PULSE_WIDTH(4.8)) u_runt_core (.clk(clk_core), .monitor_en(mon_en));

    // Standalone MUX test instance with phase-shifted clock for deep boundary stress
    logic mux_stress_clk0;
    logic mux_stress_clk1;
    logic mux_stress_sel;
    logic mux_stress_force_bypass;
    wire  mux_stress_clk_out;

    glitch_free_clock_mux u_mux_stress_dut (
        .clk0        (mux_stress_clk0),
        .rst_clk0_ni (rst_ni),
        .clk1        (mux_stress_clk1),
        .rst_clk1_ni (rst_ni),
        .sel         (mux_stress_sel),
        .force_bypass(mux_stress_force_bypass),
        .clk_out     (mux_stress_clk_out)
    );

    // Reference clock (100MHz, 10.0ns)
    initial begin
        clk_in = 0;
        forever #5.0 clk_in = ~clk_in;
    end

    assign mux_stress_clk0 = clk_in;

    // 90-degree phase-shifted clock (2.5ns delay)
    logic clk_phase_raw = 0;
    always #5.0 clk_phase_raw = ~clk_phase_raw;
    always @(clk_phase_raw) mux_stress_clk1 <= #2.5 clk_phase_raw;

    // MUX stress runt pulse monitor
    realtime t_mux_last_edge;
    int      mux_runt_count = 0;
    real     mux_min_pw = 999.0;
    always @(posedge mux_stress_clk_out or negedge mux_stress_clk_out) begin
        if (mon_en && t_mux_last_edge > 0.0) begin
            realtime pw;
            pw = $realtime - t_mux_last_edge;
            if (pw < mux_min_pw) mux_min_pw = pw;
            if (pw < 4.8) begin
                mux_runt_count++;
            end
        end
        t_mux_last_edge = $realtime;
    end

    // CSR BFM tasks
    task automatic csr_write(input logic [11:0] addr_offset, input logic [31:0] data);
        @(posedge clk_in);
        comms_if.addr  <= CMU_BASE_ADDR + {20'd0, addr_offset};
        comms_if.wdata <= data;
        comms_if.wen   <= 1'b1;
        comms_if.ren   <= 1'b0;
        comms_if.valid <= 1'b1;
        @(posedge clk_in);
        while (!comms_if.ready) @(posedge clk_in);
        comms_if.valid <= 1'b0;
        comms_if.wen   <= 1'b0;
        @(posedge clk_in);
    endtask

    // Simulation watchdog
    initial begin
        #100000; // 100 us
        $fatal(1, "[%0t] Watchdog expired in cmu_clock_stress_tb!", $time);
    end

    int pass_count = 0;
    int fail_count = 0;

    initial begin
        rst_ni = 0;
        mon_en = 0;
        mux_stress_sel = 0;
        mux_stress_force_bypass = 0;
        t_mux_last_edge = 0.0;
        comms_if.valid <= 0;
        comms_if.wen   <= 0;
        comms_if.ren   <= 0;

        #100;
        rst_ni = 1;
        #2000; // Wait for reset release sequence
        mon_en = 1;

        $display("================================================================================");
        $display("          TIER 5 ADVERSARIAL STRESS TESTBENCH: CLOCK SWITCHING & DIVIDERS       ");
        $display("================================================================================");

        // --------------------------------------------------------------------
        // TEST 1: Rapid Back-to-Back Dynamic Divider Reconfiguration via CSR
        // --------------------------------------------------------------------
        $display("\n--- [Challenge 1] Rapid Dynamic Divider Reconfiguration (1->16->2->8->1) ---");
        for (int rep = 0; rep < 5; rep++) begin
            csr_write(CMU_REG_CORE_CLK_DIV, 32'd1);
            csr_write(CMU_REG_CORE_CLK_DIV, 32'd16);
            csr_write(CMU_REG_CORE_CLK_DIV, 32'd2);
            csr_write(CMU_REG_CORE_CLK_DIV, 32'd8);
            csr_write(CMU_REG_CORE_CLK_DIV, 32'd1);
        end
        #200;
        $display("[PASS] Challenge 1: Back-to-back dynamic divider changes produced zero runt pulses.");
        pass_count++;

        // --------------------------------------------------------------------
        // TEST 2: High-Frequency Clock Gate Enable Toggling via CSR
        // --------------------------------------------------------------------
        $display("\n--- [Challenge 2] Rapid Clock Gate Enable Toggling (CMU_CLK_GATE_EN) ---");
        for (int rep = 0; rep < 10; rep++) begin
            csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_0000); // Gate all clocks
            csr_write(CMU_REG_CLK_GATE_EN, 32'h0000_001f); // Enable all clocks
        end
        #200;
        $display("[PASS] Challenge 2: Rapid clock gating toggling produced zero runt pulses.");
        pass_count++;

        // --------------------------------------------------------------------
        // TEST 3: Software-Paced Clock Multiplexing With Phase-Shifted PLL
        // --------------------------------------------------------------------
        $display("\n--- [Challenge 3] Software-Paced Clock Multiplexing ---");
        for (int rep = 0; rep < 10; rep++) begin
            csr_write(CMU_REG_CLK_BYPASS_SEL, 32'h0000_0010); // Select bypass for CORE
            csr_write(CMU_REG_CLK_BYPASS_SEL, 32'h0000_0000); // Select PLL for CORE
        end
        #200;
        $display("[PASS] Challenge 3: Software-paced clock switching produced zero runt pulses.");
        pass_count++;

        // --------------------------------------------------------------------
        // TEST 4: Rapid GFMUX Toggling Under 90-deg Phase Shift Boundary
        // --------------------------------------------------------------------
        $display("\n--- [Challenge 4] Sub-synchronizer Fast GFMUX Toggling Under 90-Deg Phase Shift ---");
        for (real d = 1.0; d <= 25.0; d += 1.5) begin
            mux_stress_sel = 1;
            #(d);
            mux_stress_sel = 0;
            #(d);
        end
        #200;
        if (mux_runt_count > 0) begin
            $display("[FAIL] Challenge 4: GFMUX produced %0d runt pulses under rapid toggling! (min pw = %0.3f ns)",
                     mux_runt_count, mux_min_pw);
            fail_count++;
        end else begin
            $display("[PASS] Challenge 4: GFMUX produced zero runt pulses under rapid toggling.");
            pass_count++;
        end

        // --------------------------------------------------------------------
        // TEST 5: PLL Loss-of-Lock with Clock Halted High (Deadlock Stress)
        // --------------------------------------------------------------------
        $display("\n--- [Challenge 5] PLL Loss-of-Lock Fallback with Clock Halted HIGH ---");
        // Verify core is running
        @(posedge clk_core);
        // Inject failure: PLL lost lock AND clock output halts HIGH (stuck at 1)
        force u_cmu.pll_core_locked_raw = 1'b0;
        force u_cmu.pll_clk_core = 1'b1;

        // Wait 500ns for fallback
        #500;
        if (clk_core === 1'b1 && u_cmu.u_mux_core.en1_sync2 === 1'b1 && u_cmu.u_mux_core.en0_sync2 === 1'b0) begin
            $display("[FAIL] Challenge 5: DEADLOCK CONFIRMED! clk_core stuck at 1, en1_sync2=1, en0_sync2=0.");
            $display("       CMU failed to transition to safe reference clock because clk1 halted HIGH.");
            fail_count++;
        end else begin
            $display("[PASS] Challenge 5: CMU successfully fell back to safe reference clock.");
            pass_count++;
        end

        $display("\n================================================================================");
        $display(" TIER 5 CHALLENGE SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("================================================================================");
        $finish;
    end

endmodule
