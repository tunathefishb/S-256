`timescale 1ns/1ps

import soc_pkg::*;

module alu (
    input  logic [3:0]        alu_op,
    input  logic [63:0]       op_a,
    input  logic [63:0]       op_b,
    output logic [63:0]       alu_res,
    output alu_flags_t        alu_flags
);

    // Pre-sliced subfields to prevent Icarus Verilog constant select warnings
    wire [5:0]  shamt       = op_b[5:0];
    wire        op_a_msb    = op_a[63];
    wire        op_b_msb    = op_b[63];

    // Arithmetic extended results for carry and overflow calculations
    wire [64:0] add_ext     = {1'b0, op_a} + {1'b0, op_b};
    wire [64:0] sub_ext     = {1'b0, op_a} - {1'b0, op_b};
    wire        add_cout    = add_ext[64];
    wire        sub_borrow  = sub_ext[64];

    wire [63:0] add_res     = op_a + op_b;
    wire [63:0] sub_res     = op_a - op_b;
    wire        add_res_msb = add_res[63];
    wire        sub_res_msb = sub_res[63];

    // 64-bit signed overflow detection
    // ADD: (~(op_a[63] ^ op_b[63])) & (op_a[63] ^ alu_res[63])
    // SUB: (op_a[63] ^ op_b[63]) & (op_a[63] ^ alu_res[63])
    wire add_ovf = (~(op_a_msb ^ op_b_msb)) & (op_a_msb ^ add_res_msb);
    wire sub_ovf = (op_a_msb ^ op_b_msb) & (op_a_msb ^ sub_res_msb);

    // 64-bit ALU Datapath Operation
    always_comb begin
        case (alu_op)
            ALU_ADD:   alu_res = add_res;
            ALU_SUB:   alu_res = sub_res;
            ALU_SHL:   alu_res = op_a << shamt;
            ALU_SHR:   alu_res = op_a >> shamt;
            ALU_AND:   alu_res = op_a & op_b;
            ALU_OR:    alu_res = op_a | op_b;
            ALU_XOR:   alu_res = op_a ^ op_b;
            ALU_NOT:   alu_res = ~op_a;
            ALU_PASSA: alu_res = op_a;
            ALU_PASSB: alu_res = op_b;
            default:   alu_res = 64'd0;
        endcase
    end

    // Pre-sliced result MSB for negative flag
    wire alu_res_msb = alu_res[63];

    // Carry and Overflow determination based on operation
    logic flag_c;
    logic flag_v;

    always_comb begin
        case (alu_op)
            ALU_ADD: begin
                flag_c = add_cout;
                flag_v = add_ovf;
            end
            ALU_SUB: begin
                flag_c = sub_borrow;
                flag_v = sub_ovf;
            end
            default: begin
                flag_c = 1'b0;
                flag_v = 1'b0;
            end
        endcase
    end

    // Output condition flags
    assign alu_flags.zero     = (alu_res == 64'd0);
    assign alu_flags.negative = alu_res_msb;
    assign alu_flags.carry    = flag_c;
    assign alu_flags.overflow = flag_v;

endmodule
