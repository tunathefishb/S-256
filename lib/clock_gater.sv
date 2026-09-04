`timescale 1ns/1ps

module clock_gater (
    input  logic clk_in,
    input  logic rst_ni,
    input  logic enable,    // 1: clock enabled, 0: clock gated (stopped low)
    input  logic test_en,   // DFT scan test enable override (default 1'b0)
    output logic clk_out
);

    logic en_latched;
    wire  en_eff = enable | test_en;

    // Capture enable on negative edge: clk_in is 0 when en_latched transitions
    always_ff @(negedge clk_in or negedge rst_ni) begin
        if (!rst_ni) begin
            en_latched <= 1'b1; // Default enabled out of reset
        end else begin
            en_latched <= en_eff;
        end
    end

    // Gated clock output: changes only when clk_in is 0, guaranteeing zero runt pulses
    assign clk_out = clk_in & en_latched;

endmodule
