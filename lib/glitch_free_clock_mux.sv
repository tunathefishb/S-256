`timescale 1ns/1ps

module glitch_free_clock_mux (
    input  logic clk0,             // Safe reference/bypass clock (e.g. clk_in)
    input  logic rst_clk0_ni,      // Active-low reset synchronized to clk0
    input  logic clk1,             // Target PLL clock
    input  logic rst_clk1_ni,      // Active-low reset synchronized to clk1
    input  logic sel,              // 0: select clk0, 1: select clk1
    input  logic force_bypass,     // 1: asynchronous override to force clk0 (loss of lock)
    output logic clk_out           // Glitch-free switched clock output
);

    // =========================================================================
    // Declarations
    // =========================================================================
    logic en0_sync1, en0_sync2;
    logic en1_sync1, en1_sync2;
    logic dead_clk_override;
    logic [2:0] dead_clk_cnt;

    // =========================================================================
    // Dual-Stage Interlocked Targets
    // Interlocking both stage-1 and stage-2 synchronizer flops prevents runt
    // pulses during rapid mux toggling across arbitrary phase-shifted clocks.
    // =========================================================================
    wire en0_target = (~sel | force_bypass) & (~en1_sync1) & (~en1_sync2);
    wire en1_target = (sel & ~force_bypass) & (~en0_sync1) & (~en0_sync2);

    // =========================================================================
    // Domain 0 Handshake Flops (Clocked on negedge clk0)
    // =========================================================================
    always_ff @(negedge clk0 or negedge rst_clk0_ni) begin
        if (!rst_clk0_ni) begin
            en0_sync1 <= 1'b1; // Default to safe bypass clock out of reset
            en0_sync2 <= 1'b1;
        end else begin
            en0_sync1 <= en0_target;
            en0_sync2 <= en0_sync1;
        end
    end

    // =========================================================================
    // Dead-Clock Override Counter (Clocked on negedge clk0)
    // If clk1 halts (dead) while force_bypass is asserted, clk1 produces no
    // negative edges to clear en1_sync1/2.
    // While force_bypass is asserted and en1 is still active, after 3 cycles
    // of clk0 without clk1 deasserting, dead_clk_override asserts to
    // asynchronously clear en1_sync1/2, breaking the deadlock and allowing
    // clk0 to cleanly take over.
    // =========================================================================
    always_ff @(negedge clk0 or negedge rst_clk0_ni) begin
        if (!rst_clk0_ni) begin
            dead_clk_cnt      <= 3'd0;
            dead_clk_override <= 1'b0;
        end else if (force_bypass && (en1_sync1 || en1_sync2)) begin
            if (dead_clk_cnt >= 3'd3) begin
                dead_clk_override <= 1'b1;
            end else begin
                dead_clk_cnt <= dead_clk_cnt + 3'd1;
            end
        end else begin
            dead_clk_cnt      <= 3'd0;
            dead_clk_override <= 1'b0;
        end
    end

    // =========================================================================
    // Domain 1 Handshake Flops (Clocked on negedge clk1)
    // Incorporates asynchronous clear on dead_clk_override to eliminate
    // deadlock when clk1 halts high or dead.
    // =========================================================================
    wire rst_clk1_effective_n = rst_clk1_ni & ~dead_clk_override;

    always_ff @(negedge clk1 or negedge rst_clk1_effective_n) begin
        if (!rst_clk1_effective_n) begin
            en1_sync1 <= 1'b0;
            en1_sync2 <= 1'b0;
        end else begin
            en1_sync1 <= en1_target;
            en1_sync2 <= en1_sync1;
        end
    end

    // =========================================================================
    // Clock Gating and Output OR
    // =========================================================================
    wire gated_clk0 = clk0 & en0_sync2;
    wire gated_clk1 = clk1 & en1_sync2;

    assign clk_out = gated_clk0 | gated_clk1;

endmodule
