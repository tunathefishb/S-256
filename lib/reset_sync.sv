module reset_sync #(
    parameter int STAGES = 2
) (
    input  logic clk,
    input  logic rst_ni,
    output logic rst_sync_no
);

    logic [STAGES-1:0] sync_regs;

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            sync_regs <= {STAGES{1'b0}};
        end else begin
            sync_regs <= {sync_regs[STAGES-2:0], 1'b1};
        end
    end

    assign rst_sync_no = sync_regs[STAGES-1];

endmodule
