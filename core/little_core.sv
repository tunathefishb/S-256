`timescale 1ns/1ps

import soc_pkg::*;

module little_core (
    input  logic        clk,
    input  logic        rst_ni,
    // Instruction memory interface
    output logic [63:0] imem_addr,
    input  logic [31:0] imem_rdata,
    // Data memory interface
    output logic [63:0] dmem_addr,
    output logic [63:0] dmem_wdata,
    output logic [7:0]  dmem_wstrb,
    output logic        dmem_wen,
    output logic        dmem_ren,
    input  logic [63:0] dmem_rdata
);

    // Architectural Program Counter
    logic [63:0] pc;
    logic [63:0] next_pc;

    // Instruction Decoder signals
    logic [3:0]  opcode;
    logic [1:0]  op_group;
    logic [4:0]  dec_rd;
    logic [4:0]  dec_rs1;
    logic [4:0]  dec_rs2;
    logic [12:0] dec_imm13;
    logic [63:0] imm64_sext;
    logic        reg_write;
    logic        mem_read;
    logic        mem_write;
    logic        is_branch;
    logic        is_jump;
    logic        is_call;
    logic        alu_src_imm;
    logic        illegal_inst;

    // Register File interface signals
    logic [63:0] rdata1;
    logic [63:0] rdata2;
    logic [4:0]  rf_waddr;
    logic [63:0] rf_wdata;
    logic        rf_wen;

    // ALU signals
    logic [63:0] alu_op_a;
    logic [63:0] alu_op_b;
    logic [63:0] alu_res;
    alu_flags_t  alu_flags;

    // -------------------------------------------------------------------------
    // Program Counter Logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            pc <= 64'd0;
        end else begin
            pc <= next_pc;
        end
    end

    // Instruction fetch address
    assign imem_addr = pc;

    // -------------------------------------------------------------------------
    // Instruction Decoder
    // -------------------------------------------------------------------------
    decoder u_decoder (
        .inst         (imem_rdata),
        .opcode       (opcode),
        .op_group     (op_group),
        .rd           (dec_rd),
        .rs1          (dec_rs1),
        .rs2          (dec_rs2),
        .imm13        (dec_imm13),
        .imm64_sext   (imm64_sext),
        .reg_write    (reg_write),
        .mem_read     (mem_read),
        .mem_write    (mem_write),
        .is_branch    (is_branch),
        .is_jump      (is_jump),
        .is_call      (is_call),
        .alu_src_imm  (alu_src_imm),
        .illegal_inst (illegal_inst)
    );

    // -------------------------------------------------------------------------
    // Register File Instance (Single-cycle datapath uses FORWARDING=0)
    // -------------------------------------------------------------------------
    // In CALL instruction: if rd != 0, write return address to rd, else to LINK_REG (r31)
    assign rf_waddr = is_call ? ((dec_rd != 5'd0) ? dec_rd : LINK_REG) : dec_rd;
    assign rf_wen   = reg_write;

    regfile #(
        .FORWARDING (1'b0)
    ) u_regfile (
        .clk    (clk),
        .rst_ni (rst_ni),
        .raddr1 (dec_rs1),
        .rdata1 (rdata1),
        .raddr2 (dec_rs2),
        .rdata2 (rdata2),
        .wen    (rf_wen),
        .waddr  (rf_waddr),
        .wdata  (rf_wdata)
    );

    // -------------------------------------------------------------------------
    // ALU Instance
    // -------------------------------------------------------------------------
    assign alu_op_a = rdata1;
    assign alu_op_b = alu_src_imm ? imm64_sext : rdata2;

    alu u_alu (
        .alu_op    (opcode),
        .op_a      (alu_op_a),
        .op_b      (alu_op_b),
        .alu_res   (alu_res),
        .alu_flags (alu_flags)
    );

    // -------------------------------------------------------------------------
    // Register Writeback Selection
    // -------------------------------------------------------------------------
    always_comb begin
        case (opcode)
            OP_CALL: rf_wdata = pc + 64'd4;
            OP_LOAD: rf_wdata = dmem_rdata;
            OP_LDI:  rf_wdata = imm64_sext;
            OP_MOV:  rf_wdata = rdata1;
            default: rf_wdata = alu_res;
        endcase
    end

    // -------------------------------------------------------------------------
    // Data Memory Interface (Strict reset gating to prevent bus writes during reset)
    // -------------------------------------------------------------------------
    assign dmem_addr  = rdata1 + imm64_sext;
    assign dmem_wdata = rdata2;
    assign dmem_wstrb = (rst_ni && mem_write) ? 8'hFF : 8'h00;
    assign dmem_wen   = rst_ni && mem_write;
    assign dmem_ren   = rst_ni && mem_read;

    // -------------------------------------------------------------------------
    // Next PC Calculation
    // -------------------------------------------------------------------------
    wire branch_taken = (opcode == OP_BEQ && rdata1 == rdata2) ||
                        (opcode == OP_BNE && rdata1 != rdata2);

    always_comb begin
        if (is_branch && branch_taken) begin
            next_pc = pc + (imm64_sext << 2);
        end else if (is_call) begin
            next_pc = pc + (imm64_sext << 2);
        end else if (is_jump) begin
            if (dec_rs1 != 5'd0) begin
                next_pc = rdata1 + imm64_sext;
            end else begin
                next_pc = pc + (imm64_sext << 2);
            end
        end else begin
            next_pc = pc + 64'd4;
        end
    end

endmodule
