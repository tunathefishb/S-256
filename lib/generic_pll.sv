module generic_pll #(
    parameter int MULTIPLIER = 1,
    parameter int DIVIDER = 1
) (
    input  logic clk_in,
    input  logic rst_ni,
    output logic clk_out,
    output logic locked
);

    // Stub implementation for simulation
    // In a real SoC, this would instantiate a hard macro PLL IP.

    logic clk_div;
    int counter;

    always_ff @(posedge clk_in or negedge rst_ni) begin
        if (!rst_ni) begin
            counter <= 0;
            clk_div <= 0;
        end else begin
            if (counter >= (DIVIDER - 1)) begin
                counter <= 0;
                clk_div <= ~clk_div;
            end else begin
                counter <= counter + 1;
            end
        end
    end

    // Simplistic clk_out generation for the stub
    assign clk_out = (DIVIDER == 1) ? clk_in : clk_div;

    // Simulate lock delay
    logic [3:0] lock_delay_cnt;
    always_ff @(posedge clk_in or negedge rst_ni) begin
        if (!rst_ni) begin
            lock_delay_cnt <= 0;
            locked <= 1'b0;
        end else begin
            if (lock_delay_cnt == 4'hF) begin
                locked <= 1'b1;
            end else begin
                lock_delay_cnt <= lock_delay_cnt + 1;
            end
        end
    end

endmodule
