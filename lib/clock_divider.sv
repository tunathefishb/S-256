`timescale 1ns/1ps

module clock_divider #(
    parameter int MAX_DIV = 64
) (
    input  logic        clk_in,
    input  logic        rst_ni,
    input  logic [7:0]  div_val,   // Division ratio: 1 (bypass), 2, 4, 8, etc.
    output logic        clk_out
);

    logic [7:0] active_div;
    logic [7:0] count;
    logic       clk_divided;

    wire [7:0] target_div = (div_val == 8'd0) ? 8'd1 : div_val;
    wire [7:0] eff_div    = (active_div < 8'd2) ? 8'd2 : active_div;

    // In low phase when count has passed the high half-cycle
    wire in_low_phase = (count >= (eff_div >> 1));

    // Terminal count is reached on last cycle of period or early during low phase if divider changed
    wire div_changed    = (target_div != active_div);
    wire terminal_count = (count >= eff_div - 1) || (div_changed && in_low_phase);

    always_ff @(posedge clk_in or negedge rst_ni) begin
        if (!rst_ni) begin
            active_div  <= target_div;
            count       <= 8'd0;
            clk_divided <= 1'b0;
        end else begin
            if (terminal_count) begin
                count       <= 8'd0;
                active_div  <= target_div;
                clk_divided <= (target_div > 8'd1);
            end else begin
                count <= count + 1'b1;
                // 50% duty cycle for even dividers
                clk_divided <= (count + 1'b1 < (eff_div >> 1));
            end
        end
    end

    // Synchronous glitch-free bypass multiplexer clocked on negedge clk_in
    // Both clk_in and clk_divided are derived from clk_in, so switching enables
    // on negedge clk_in when clk_divided is low ensures zero runt pulses.
    logic en_bypass;
    logic en_divided;
    wire  sel_divided = (active_div > 8'd1);

    always_ff @(negedge clk_in or negedge rst_ni) begin
        if (!rst_ni) begin
            en_bypass  <= 1'b1;
            en_divided <= 1'b0;
        end else begin
            if (sel_divided) begin
                if (!en_divided && !clk_divided) begin
                    en_bypass  <= 1'b0;
                    en_divided <= 1'b1;
                end
            end else begin
                if (!en_bypass && !clk_divided) begin
                    en_divided <= 1'b0;
                    en_bypass  <= 1'b1;
                end
            end
        end
    end

    wire gated_in  = clk_in & en_bypass;
    wire gated_div = clk_divided & en_divided;
    assign clk_out = gated_in | gated_div;

endmodule
