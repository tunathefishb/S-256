`timescale 1ns/1ps

import soc_pkg::*;

module regfile #(
    parameter bit FORWARDING = 1'b1
) (
    input  logic        clk,
    input  logic        rst_ni,
    input  logic [4:0]  raddr1,
    output logic [63:0] rdata1,
    input  logic [4:0]  raddr2,
    output logic [63:0] rdata2,
    input  logic        wen,
    input  logic [4:0]  waddr,
    input  logic [63:0] wdata
);

    // 32-entry x 64-bit general-purpose register array (r0..r31)
    logic [63:0] rf_mem [0:31];
    integer i;

    // Synchronous write port with asynchronous active-low reset
    // r0 write suppression: writes to r0 (waddr == 5'd0) are unconditionally ignored
    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            for (i = 0; i < 32; i = i + 1) begin
                rf_mem[i] <= 64'd0;
            end
        end else if (wen && (waddr != 5'd0)) begin
            rf_mem[waddr] <= wdata;
        end
    end

    // Dual asynchronous read ports with configurable internal write-through forwarding
    // r0 read clamping: reads of r0 unconditionally return 64'd0
    // If FORWARDING is enabled: wen && (waddr == raddr) && (waddr != 5'd0) -> wdata
    // If FORWARDING is disabled (standard single-cycle datapath): reads array directly to prevent combinational feedback loops
    generate
        if (FORWARDING) begin : gen_forwarding
            assign rdata1 = (raddr1 == 5'd0) ? 64'd0 :
                            ((wen && (waddr == raddr1)) ? wdata : rf_mem[raddr1]);
            assign rdata2 = (raddr2 == 5'd0) ? 64'd0 :
                            ((wen && (waddr == raddr2)) ? wdata : rf_mem[raddr2]);
        end else begin : gen_no_forwarding
            assign rdata1 = (raddr1 == 5'd0) ? 64'd0 : rf_mem[raddr1];
            assign rdata2 = (raddr2 == 5'd0) ? 64'd0 : rf_mem[raddr2];
        end
    endgenerate

endmodule

