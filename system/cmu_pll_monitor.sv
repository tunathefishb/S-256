`timescale 1ns/1ps

module cmu_pll_monitor #(
    parameter int DEBOUNCE_CYCLES = 8
) (
    input  logic clk_sys,
    input  logic rst_sys_ni,
    input  logic pll_locked_raw,
    input  logic clear_sticky_err,   // Software write-1-to-clear strobe
    output logic pll_locked_sync,    // Filtered, synchronized live lock status
    output logic loss_of_lock_sticky,// Sticky error flag for CSR
    output logic force_bypass        // Safe bypass override signal to clock mux
);

    // =========================================================================
    // 1. 2-Stage Metastability Synchronizer for Raw Lock Signal
    // =========================================================================
    logic lock_s0, lock_s1;
    always_ff @(posedge clk_sys or negedge rst_sys_ni) begin
        if (!rst_sys_ni) begin
            lock_s0 <= 1'b0;
            lock_s1 <= 1'b0;
        end else begin
            lock_s0 <= pll_locked_raw;
            lock_s1 <= lock_s0;
        end
    end

    // =========================================================================
    // 2. Debounce Counter & Instantaneous Loss Detection
    // =========================================================================
    logic [$clog2(DEBOUNCE_CYCLES+1):0] count;
    logic lock_filtered;

    always_ff @(posedge clk_sys or negedge rst_sys_ni) begin
        if (!rst_sys_ni) begin
            count         <= '0;
            lock_filtered <= 1'b0;
        end else begin
            if (lock_s1) begin
                if (count < DEBOUNCE_CYCLES) begin
                    count <= count + 1'b1;
                end else begin
                    lock_filtered <= 1'b1;
                end
            end else begin
                count         <= '0;
                lock_filtered <= 1'b0;
            end
        end
    end

    assign pll_locked_sync = lock_filtered;

    // Detect falling edge of lock_filtered (runtime loss of lock)
    logic lock_filtered_d;
    always_ff @(posedge clk_sys or negedge rst_sys_ni) begin
        if (!rst_sys_ni) begin
            lock_filtered_d <= 1'b0;
        end else begin
            lock_filtered_d <= lock_filtered;
        end
    end

    wire loss_detected = lock_filtered_d & ~lock_filtered;

    // =========================================================================
    // 3. W1C Sticky Error Flag Register
    // =========================================================================
    always_ff @(posedge clk_sys or negedge rst_sys_ni) begin
        if (!rst_sys_ni) begin
            loss_of_lock_sticky <= 1'b0;
        end else begin
            if (loss_detected) begin
                loss_of_lock_sticky <= 1'b1;
            end else if (clear_sticky_err) begin
                // Only allow clear if PLL has regained lock; otherwise retain error
                loss_of_lock_sticky <= ~lock_filtered;
            end
        end
    end

    // Force safe bypass if PLL is unlocked or has an un-cleared loss of lock
    assign force_bypass = ~lock_filtered | loss_of_lock_sticky;

endmodule
