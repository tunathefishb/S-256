`timescale 1ns/1ps

import soc_pkg::*;

module decoder (
    input  logic [31:0] inst,
    output logic [3:0]  opcode,
    output logic [1:0]  op_group,
    output logic [4:0]  rd,
    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [12:0] imm13,
    output logic [63:0] imm64_sext,
    output logic        reg_write,
    output logic        mem_read,
    output logic        mem_write,
    output logic        is_branch,
    output logic        is_jump,
    output logic        is_call,
    output logic        alu_src_imm,
    output logic        illegal_inst
);

    // Pre-sliced subfields via continuous assignments outside always_comb
    // to guarantee zero constant select warnings in Icarus Verilog 12.0
    wire [3:0]  op_w    = inst[31:28];
    wire [1:0]  group_w = inst[31:30];
    wire [4:0]  rd_w    = inst[27:23];
    wire [4:0]  rs1_w   = inst[22:18];
    wire [4:0]  rs2_w   = inst[17:13];
    wire [12:0] imm13_w = inst[12:0];
    wire        sign_w  = inst[12];

    assign opcode     = op_w;
    assign op_group   = group_w;
    assign rd         = rd_w;
    assign rs1        = rs1_w;
    assign rs2        = rs2_w;
    assign imm13      = imm13_w;
    assign imm64_sext = {{51{sign_w}}, imm13_w};

    // Combinational instruction decode and control generation
    always_comb begin
        // Safe default assignments
        reg_write    = 1'b0;
        mem_read     = 1'b0;
        mem_write    = 1'b0;
        is_branch    = 1'b0;
        is_jump      = 1'b0;
        is_call      = 1'b0;
        alu_src_imm  = 1'b0;
        illegal_inst = 1'b0;

        case (op_w)
            OP_ADD: begin
                reg_write = 1'b1;
            end
            OP_SUB: begin
                reg_write = 1'b1;
            end
            OP_SHL: begin
                reg_write = 1'b1;
            end
            OP_SHR: begin
                reg_write = 1'b1;
            end
            OP_AND: begin
                reg_write = 1'b1;
            end
            OP_OR: begin
                reg_write = 1'b1;
            end
            OP_XOR: begin
                reg_write = 1'b1;
            end
            OP_NOT: begin
                reg_write = 1'b1;
            end
            OP_LOAD: begin
                reg_write   = 1'b1;
                mem_read    = 1'b1;
                alu_src_imm = 1'b1;
            end
            OP_STORE: begin
                mem_write   = 1'b1;
                alu_src_imm = 1'b1;
            end
            OP_MOV: begin
                reg_write = 1'b1;
            end
            OP_LDI: begin
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
            end
            OP_BEQ: begin
                is_branch = 1'b1;
            end
            OP_BNE: begin
                is_branch = 1'b1;
            end
            OP_CALL: begin
                reg_write = 1'b1;
                is_call   = 1'b1;
            end
            OP_JMP: begin
                is_jump = 1'b1;
            end
            default: begin
                illegal_inst = 1'b1;
            end
        endcase
    end

endmodule
