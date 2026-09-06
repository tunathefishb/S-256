`timescale 1ns/1ps

import soc_pkg::*;

module execution_primitives_tb;

    // Clock and Reset Signals
    logic clk;
    logic rst_ni;

    // Test Tracking Variables
    integer total_checks  = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;

    // Clock Generation (100 MHz, 10ns period)
    always #5 clk = ~clk;

    // Helper task for assertions
    task check(input logic condition, input string test_name);
        total_checks = total_checks + 1;
        if (condition) begin
            passed_checks = passed_checks + 1;
            $display("  [PASS] %s", test_name);
        end else begin
            failed_checks = failed_checks + 1;
            $display("  [FAIL] %s", test_name);
        end
    endtask

    // ========================================================================
    // 1. ALU Test Signals and Instance
    // ========================================================================
    logic [3:0]  alu_op;
    logic [63:0] alu_a;
    logic [63:0] alu_b;
    wire  [63:0] alu_res;
    wire  alu_flags_t alu_flags;

    alu u_alu (
        .alu_op    (alu_op),
        .op_a      (alu_a),
        .op_b      (alu_b),
        .alu_res   (alu_res),
        .alu_flags (alu_flags)
    );

    // ========================================================================
    // 2. Regfile Test Signals and Instance
    // ========================================================================
    logic [4:0]  rf_raddr1;
    wire  [63:0] rf_rdata1;
    logic [4:0]  rf_raddr2;
    wire  [63:0] rf_rdata2;
    logic        rf_wen;
    logic [4:0]  rf_waddr;
    logic [63:0] rf_wdata;

    regfile u_regfile (
        .clk    (clk),
        .rst_ni (rst_ni),
        .raddr1 (rf_raddr1),
        .rdata1 (rf_rdata1),
        .raddr2 (rf_raddr2),
        .rdata2 (rf_rdata2),
        .wen    (rf_wen),
        .waddr  (rf_waddr),
        .wdata  (rf_wdata)
    );

    wire  [63:0] rf_nf_rdata1;
    wire  [63:0] rf_nf_rdata2;

    regfile #(
        .FORWARDING (1'b0)
    ) u_regfile_nofwd (
        .clk    (clk),
        .rst_ni (rst_ni),
        .raddr1 (rf_raddr1),
        .rdata1 (rf_nf_rdata1),
        .raddr2 (rf_raddr2),
        .rdata2 (rf_nf_rdata2),
        .wen    (rf_wen),
        .waddr  (rf_waddr),
        .wdata  (rf_wdata)
    );

    // ========================================================================
    // 3. Decoder Test Signals and Instance
    // ========================================================================
    logic [31:0] dec_inst;
    wire  [3:0]  dec_opcode;
    wire  [1:0]  dec_op_group;
    wire  [4:0]  dec_rd;
    wire  [4:0]  dec_rs1;
    wire  [4:0]  dec_rs2;
    wire  [12:0] dec_imm13;
    wire  [63:0] dec_imm64_sext;
    wire         dec_reg_write;
    wire         dec_mem_read;
    wire         dec_mem_write;
    wire         dec_is_branch;
    wire         dec_is_jump;
    wire         dec_is_call;
    wire         dec_alu_src_imm;
    wire         dec_illegal_inst;

    decoder u_decoder (
        .inst         (dec_inst),
        .opcode       (dec_opcode),
        .op_group     (dec_op_group),
        .rd           (dec_rd),
        .rs1          (dec_rs1),
        .rs2          (dec_rs2),
        .imm13        (dec_imm13),
        .imm64_sext   (dec_imm64_sext),
        .reg_write    (dec_reg_write),
        .mem_read     (dec_mem_read),
        .mem_write    (dec_mem_write),
        .is_branch    (dec_is_branch),
        .is_jump      (dec_is_jump),
        .is_call      (dec_is_call),
        .alu_src_imm  (dec_alu_src_imm),
        .illegal_inst (dec_illegal_inst)
    );

    // ========================================================================
    // Main Verification Process
    // ========================================================================
    integer k;

    initial begin
        // Setup waveform dump
        $dumpfile("execution_primitives_tb.vcd");
        $dumpvars(0, execution_primitives_tb);

        // Initialize signals
        clk       = 1'b0;
        rst_ni    = 1'b0;
        alu_op    = 4'd0;
        alu_a     = 64'd0;
        alu_b     = 64'd0;
        rf_raddr1 = 5'd0;
        rf_raddr2 = 5'd0;
        rf_wen    = 1'b0;
        rf_waddr  = 5'd0;
        rf_wdata  = 64'd0;
        dec_inst  = 32'd0;

        $display("================================================================================");
        $display(" S-256 Execution Primitives Comprehensive Verification Suite");
        $display("================================================================================");

        // --------------------------------------------------------------------
        // SECTION 1: 64-bit ALU Verification
        // --------------------------------------------------------------------
        $display("\n--- Section 1: 64-bit ALU Verification ---");

        // 1.1 ADD Tests
        alu_op = ALU_ADD;
        alu_a = 64'd15; alu_b = 64'd27; #1;
        check(alu_res === 64'd42 && alu_flags.zero === 1'b0 && alu_flags.negative === 1'b0 &&
              alu_flags.carry === 1'b0 && alu_flags.overflow === 1'b0,
              "ALU ADD: standard addition (15 + 27 = 42)");

        alu_a = 64'd0; alu_b = 64'd0; #1;
        check(alu_res === 64'd0 && alu_flags.zero === 1'b1 && alu_flags.negative === 1'b0 &&
              alu_flags.carry === 1'b0 && alu_flags.overflow === 1'b0,
              "ALU ADD: zero sum (0 + 0 = 0)");

        alu_a = -64'sd10; alu_b = 64'sd3; #1;
        check(alu_res === -64'sd7 && alu_flags.zero === 1'b0 && alu_flags.negative === 1'b1 &&
              alu_flags.carry === 1'b0 && alu_flags.overflow === 1'b0,
              "ALU ADD: negative result without overflow (-10 + 3 = -7)");

        alu_a = 64'hFFFF_FFFF_FFFF_FFFF; alu_b = 64'd1; #1;
        check(alu_res === 64'd0 && alu_flags.zero === 1'b1 && alu_flags.negative === 1'b0 &&
              alu_flags.carry === 1'b1 && alu_flags.overflow === 1'b0,
              "ALU ADD: unsigned carry-out wrap (0xFFFFFFFFFFFFFFFF + 1 = 0)");

        alu_a = 64'h7FFF_FFFF_FFFF_FFFF; alu_b = 64'd1; #1;
        check(alu_res === 64'h8000_0000_0000_0000 && alu_flags.zero === 1'b0 && alu_flags.negative === 1'b1 &&
              alu_flags.carry === 1'b0 && alu_flags.overflow === 1'b1,
              "ALU ADD: positive signed overflow (MAX_POS + 1 -> MIN_NEG)");

        alu_a = 64'h8000_0000_0000_0000; alu_b = 64'h8000_0000_0000_0000; #1;
        check(alu_res === 64'd0 && alu_flags.zero === 1'b1 && alu_flags.negative === 1'b0 &&
              alu_flags.carry === 1'b1 && alu_flags.overflow === 1'b1,
              "ALU ADD: negative signed overflow (MIN_NEG + MIN_NEG -> 0, C=1, V=1)");

        // 1.2 SUB Tests
        alu_op = ALU_SUB;
        alu_a = 64'd100; alu_b = 64'd42; #1;
        check(alu_res === 64'd58 && alu_flags.zero === 1'b0 && alu_flags.negative === 1'b0 &&
              alu_flags.carry === 1'b0 && alu_flags.overflow === 1'b0,
              "ALU SUB: standard subtraction (100 - 42 = 58)");

        alu_a = 64'hCAFE_BABE_1234_5678; alu_b = 64'hCAFE_BABE_1234_5678; #1;
        check(alu_res === 64'd0 && alu_flags.zero === 1'b1 && alu_flags.negative === 1'b0 &&
              alu_flags.carry === 1'b0 && alu_flags.overflow === 1'b0,
              "ALU SUB: self subtraction (A - A = 0)");

        alu_a = 64'd0; alu_b = 64'd1; #1;
        check(alu_res === 64'hFFFF_FFFF_FFFF_FFFF && alu_flags.zero === 1'b0 && alu_flags.negative === 1'b1 &&
              alu_flags.carry === 1'b1 && alu_flags.overflow === 1'b0,
              "ALU SUB: unsigned borrow (0 - 1 = -1, C=1, V=0)");

        alu_a = 64'h8000_0000_0000_0000; alu_b = 64'd1; #1;
        check(alu_res === 64'h7FFF_FFFF_FFFF_FFFF && alu_flags.zero === 1'b0 && alu_flags.negative === 1'b0 &&
              alu_flags.carry === 1'b0 && alu_flags.overflow === 1'b1,
              "ALU SUB: negative signed overflow (MIN_NEG - 1 -> MAX_POS, V=1)");

        alu_a = 64'h7FFF_FFFF_FFFF_FFFF; alu_b = 64'hFFFF_FFFF_FFFF_FFFF; #1;
        check(alu_res === 64'h8000_0000_0000_0000 && alu_flags.zero === 1'b0 && alu_flags.negative === 1'b1 &&
              alu_flags.carry === 1'b1 && alu_flags.overflow === 1'b1,
              "ALU SUB: positive - negative overflow (MAX_POS - (-1) -> MIN_NEG, V=1)");

        // 1.3 SHL Tests
        alu_op = ALU_SHL;
        alu_a = 64'hFEDC_BA98_7654_3210; alu_b = 64'd0; #1;
        check(alu_res === 64'hFEDC_BA98_7654_3210 && alu_flags.negative === 1'b1,
              "ALU SHL: shift by 0 maintains operand");

        alu_a = 64'd1; alu_b = 64'd1; #1;
        check(alu_res === 64'd2,
              "ALU SHL: shift by 1 (1 << 1 = 2)");

        alu_a = 64'h0000_0000_1234_5678; alu_b = 64'd32; #1;
        check(alu_res === 64'h1234_5678_0000_0000,
              "ALU SHL: shift by 32 positions");

        alu_a = 64'd1; alu_b = 64'd63; #1;
        check(alu_res === 64'h8000_0000_0000_0000 && alu_flags.negative === 1'b1,
              "ALU SHL: shift by 63 sets MSB (negative=1)");

        alu_a = 64'd1; alu_b = 64'd64; #1;
        check(alu_res === 64'd1,
              "ALU SHL: shift amount masking (64 & 63 = 0, shift by 0)");

        alu_a = 64'd1; alu_b = 64'd65; #1;
        check(alu_res === 64'd2,
              "ALU SHL: shift amount masking (65 & 63 = 1, shift by 1)");

        // 1.4 SHR Tests (Logical)
        alu_op = ALU_SHR;
        alu_a = 64'h8000_0000_0000_0000; alu_b = 64'd0; #1;
        check(alu_res === 64'h8000_0000_0000_0000 && alu_flags.negative === 1'b1,
              "ALU SHR: shift by 0 maintains MSB");

        alu_a = 64'h8000_0000_0000_0000; alu_b = 64'd1; #1;
        check(alu_res === 64'h4000_0000_0000_0000 && alu_flags.negative === 1'b0,
              "ALU SHR: logical zero-fill shift by 1");

        alu_a = 64'h8000_0000_0000_0000; alu_b = 64'd63; #1;
        check(alu_res === 64'd1 && alu_flags.negative === 1'b0 && alu_flags.zero === 1'b0,
              "ALU SHR: shift by 63 yields 1");

        alu_a = 64'd16; alu_b = 64'd66; #1;
        check(alu_res === 64'd4,
              "ALU SHR: shift amount masking (66 & 63 = 2, 16 >> 2 = 4)");

        // 1.5 Bitwise Logic Tests
        alu_op = ALU_AND;
        alu_a = 64'hF0F0_AAAA_5555_00FF; alu_b = 64'h0F0F_FFFF_5555_0000; #1;
        check(alu_res === 64'h0000_AAAA_5555_0000,
              "ALU AND: bitwise AND mask");

        alu_a = 64'hFFFF_0000_FFFF_0000; alu_b = 64'd0; #1;
        check(alu_res === 64'd0 && alu_flags.zero === 1'b1,
              "ALU AND: AND with 0 asserts zero flag");

        alu_op = ALU_OR;
        alu_a = 64'hF0F0_0000_1234_0000; alu_b = 64'h0F0F_0000_0000_5678; #1;
        check(alu_res === 64'hFFFF_0000_1234_5678,
              "ALU OR: bitwise OR bit combination");

        alu_op = ALU_XOR;
        alu_a = 64'hAAAA_BBBB_CCCC_DDDD; alu_b = 64'hAAAA_BBBB_CCCC_DDDD; #1;
        check(alu_res === 64'd0 && alu_flags.zero === 1'b1,
              "ALU XOR: self-cancellation yields zero");

        alu_a = 64'hFFFF_FFFF_0000_0000; alu_b = 64'h0000_FFFF_FFFF_0000; #1;
        check(alu_res === 64'hFFFF_0000_FFFF_0000,
              "ALU XOR: bitwise XOR toggle");

        alu_op = ALU_NOT;
        alu_a = 64'd0; alu_b = 64'hDEAD_BEEF; #1;
        check(alu_res === 64'hFFFF_FFFF_FFFF_FFFF && alu_flags.negative === 1'b1 && alu_flags.zero === 1'b0,
              "ALU NOT: bitwise NOT of zero yields all-ones (op_b ignored)");

        alu_a = 64'hFFFF_FFFF_FFFF_FFFF; #1;
        check(alu_res === 64'd0 && alu_flags.zero === 1'b1,
              "ALU NOT: bitwise NOT of all-ones yields zero");

        // 1.6 Pass-through Modes
        alu_op = ALU_PASSA;
        alu_a = 64'h1122_3344_5566_7788; alu_b = 64'h99AA_BBCC_DDEE_FF00; #1;
        check(alu_res === 64'h1122_3344_5566_7788,
              "ALU PASSA: passes op_a intact, ignores op_b");

        alu_op = ALU_PASSB;
        alu_a = 64'h1122_3344_5566_7788; alu_b = 64'h99AA_BBCC_DDEE_FF00; #1;
        check(alu_res === 64'h99AA_BBCC_DDEE_FF00,
              "ALU PASSB: passes op_b intact, ignores op_a");

        alu_op = 4'd12; alu_a = 64'hFFFF; alu_b = 64'hFFFF; #1;
        check(alu_res === 64'd0,
              "ALU Default: unmapped opcode returns 64'd0");

        // --------------------------------------------------------------------
        // SECTION 2: 32x64-bit Register File Verification
        // --------------------------------------------------------------------
        $display("\n--- Section 2: 32x64-bit Register File Verification ---");

        // 2.1 Reset Behavior
        rst_ni = 1'b0;
        #15;
        @(posedge clk); #1;
        rst_ni = 1'b1;
        #10;

        // Verify all registers reset to 0
        for (k = 0; k < 32; k = k + 1) begin
            rf_raddr1 = k[4:0];
            rf_raddr2 = k[4:0];
            #1;
            check(rf_rdata1 === 64'd0 && rf_rdata2 === 64'd0,
                  $sformatf("REGFILE Reset: r%0d is initialized to 64'd0", k));
        end

        // 2.2 Hardwired r0 Invariant
        // Attempt to write non-zero to r0
        @(posedge clk); #1;
        rf_wen   = 1'b1;
        rf_waddr = 5'd0;
        rf_wdata = 64'hDEAD_BEEF_CAFE_BABE;
        rf_raddr1 = 5'd0;
        rf_raddr2 = 5'd0;
        #1;
        check(rf_rdata1 === 64'd0 && rf_rdata2 === 64'd0,
              "REGFILE r0 Invariant: write-through forwarding to r0 is clamped to 0");

        @(posedge clk); #1;
        rf_wen = 1'b0;
        check(rf_rdata1 === 64'd0 && rf_rdata2 === 64'd0,
              "REGFILE r0 Invariant: stored state of r0 remains 64'd0 post-clock");

        // 2.3 Write and Readback across all registers r1..r31
        for (k = 1; k < 32; k = k + 1) begin
            @(posedge clk); #1;
            rf_wen   = 1'b1;
            rf_waddr = k[4:0];
            rf_wdata = 64'hA000_0000_0000_0000 | (64'(k) << 32) | 64'(k);
        end
        @(posedge clk); #1;
        rf_wen = 1'b0;

        // Readback and verify all 31 registers
        for (k = 1; k < 32; k = k + 1) begin
            rf_raddr1 = k[4:0];
            rf_raddr2 = (k == 31) ? 5'd1 : (k[4:0] + 5'd1);
            #1;
            check(rf_rdata1 === (64'hA000_0000_0000_0000 | (64'(k) << 32) | 64'(k)),
                  $sformatf("REGFILE Persistence: r%0d holds correct written value", k));
        end

        // 2.4 Internal Write-Through Forwarding (RAW bypass in same cycle)
        for (k = 1; k <= 5; k = k + 1) begin
            @(posedge clk); #1;
            rf_wen   = 1'b1;
            rf_waddr = k[4:0];
            rf_wdata = 64'h5555_0000_0000_0000 | 64'(k);
            rf_raddr1 = k[4:0];
            rf_raddr2 = (k == 5) ? 5'd10 : 5'd20; // different register
            #1;
            // Before clock edge: verify rdata1 immediately forwards new wdata
            check(rf_rdata1 === (64'h5555_0000_0000_0000 | 64'(k)),
                  $sformatf("REGFILE Bypass: r%0d same-cycle forwarding returns wdata before clk", k));
            // Verify rdata2 reads unwritten register from array
            check(rf_rdata2 !== rf_wdata,
                  $sformatf("REGFILE Bypass: unwritten register on port 2 not corrupted (%0d)", k));
        end
        @(posedge clk); #1;
        rf_wen = 1'b0;

        // Verify write disable does not forward
        rf_wen   = 1'b0;
        rf_waddr = 5'd1;
        rf_wdata = 64'hFFFF_FFFF_FFFF_FFFF;
        rf_raddr1 = 5'd1;
        #1;
        check(rf_rdata1 !== 64'hFFFF_FFFF_FFFF_FFFF,
              "REGFILE Bypass: wen=0 disables forwarding, returns stored register value");

        // 2.5 Non-Forwarding Mode Verification (FORWARDING = 0 for single-cycle datapaths)
        // Verify that u_regfile_nofwd does NOT forward wdata combinational loop
        @(posedge clk); #1;
        rf_wen   = 1'b1;
        rf_waddr = 5'd6;
        rf_wdata = 64'h9999_8888_7777_6666;
        rf_raddr1 = 5'd6;
        #1;
        // Before clock edge: forwarding instance forwards wdata, but non-forwarding instance does NOT
        check(rf_rdata1 === 64'h9999_8888_7777_6666,
              "REGFILE Param: FORWARDING=1 instance forwards wdata before clock");
        check(rf_nf_rdata1 !== 64'h9999_8888_7777_6666,
              "REGFILE Param: FORWARDING=0 instance suppresses same-cycle forwarding (breaks combinational loops)");

        @(posedge clk); #1;
        rf_wen = 1'b0;
        #1;
        check(rf_nf_rdata1 === 64'h9999_8888_7777_6666,
              "REGFILE Param: FORWARDING=0 instance commits write synchronously at clock edge");

        // --------------------------------------------------------------------
        // SECTION 3: 32-bit Instruction Decoder Verification
        // --------------------------------------------------------------------
        $display("\n--- Section 3: 32-bit Instruction Decoder Verification ---");

        // 3.1 Field Extraction Verification
        // inst: opcode=0x8 (LOAD), rd=29, rs1=14, rs2=3, imm13=0x0123
        dec_inst = {4'h8, 5'd29, 5'd14, 5'd3, 13'h0123}; #1;
        check(dec_opcode === 4'h8 && dec_op_group === OP_GROUP_MEM &&
              dec_rd === 5'd29 && dec_rs1 === 5'd14 && dec_rs2 === 5'd3 &&
              dec_imm13 === 13'h0123 && dec_imm64_sext === 64'h0000_0000_0000_0123,
              "DECODER Fields: positive immediate instruction correctly sliced");

        // 3.2 Immediate Sign Extension Verification
        dec_inst = {4'hB, 5'd1, 5'd0, 5'd0, 13'h0FFF}; #1; // +4095
        check(dec_imm64_sext === 64'h0000_0000_0000_0FFF,
              "DECODER SignExt: max positive immediate (+4095) zero-extends high 51 bits");

        dec_inst = {4'hB, 5'd1, 5'd0, 5'd0, 13'h0000}; #1; // 0
        check(dec_imm64_sext === 64'h0000_0000_0000_0000,
              "DECODER SignExt: zero immediate extends to 64'd0");

        dec_inst = {4'hB, 5'd1, 5'd0, 5'd0, 13'h1FFF}; #1; // -1
        check(dec_imm64_sext === 64'hFFFF_FFFF_FFFF_FFFF,
              "DECODER SignExt: minus one (-1) sign-extends to all 64 bits set");

        dec_inst = {4'hB, 5'd1, 5'd0, 5'd0, 13'h1000}; #1; // -4096
        check(dec_imm64_sext === 64'hFFFF_FFFF_FFFF_F000,
              "DECODER SignExt: min negative immediate (-4096) sign-extends properly");

        dec_inst = {4'hB, 5'd1, 5'd0, 5'd0, 13'h1A5A}; #1; // Arbitrary negative
        check(dec_imm64_sext === 64'hFFFF_FFFF_FFFF_FA5A,
              "DECODER SignExt: arbitrary negative 13'h1A5A sign-extends properly");

        // 3.3 Control Signal Matrix for all 16 Instructions
        // OP_ADD
        dec_inst = {OP_ADD, 5'd1, 5'd2, 5'd3, 13'd0}; #1;
        check(dec_opcode === OP_ADD && dec_op_group === OP_GROUP_ARITH &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_ADD control flags correct");

        // OP_SUB
        dec_inst = {OP_SUB, 5'd1, 5'd2, 5'd3, 13'd0}; #1;
        check(dec_opcode === OP_SUB && dec_op_group === OP_GROUP_ARITH &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_SUB control flags correct");

        // OP_SHL
        dec_inst = {OP_SHL, 5'd1, 5'd2, 5'd3, 13'd0}; #1;
        check(dec_opcode === OP_SHL && dec_op_group === OP_GROUP_ARITH &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_SHL control flags correct");

        // OP_SHR
        dec_inst = {OP_SHR, 5'd1, 5'd2, 5'd3, 13'd0}; #1;
        check(dec_opcode === OP_SHR && dec_op_group === OP_GROUP_ARITH &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_SHR control flags correct");

        // OP_AND
        dec_inst = {OP_AND, 5'd1, 5'd2, 5'd3, 13'd0}; #1;
        check(dec_opcode === OP_AND && dec_op_group === OP_GROUP_LOGIC &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_AND control flags correct");

        // OP_OR
        dec_inst = {OP_OR, 5'd1, 5'd2, 5'd3, 13'd0}; #1;
        check(dec_opcode === OP_OR && dec_op_group === OP_GROUP_LOGIC &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_OR control flags correct");

        // OP_XOR
        dec_inst = {OP_XOR, 5'd1, 5'd2, 5'd3, 13'd0}; #1;
        check(dec_opcode === OP_XOR && dec_op_group === OP_GROUP_LOGIC &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_XOR control flags correct");

        // OP_NOT
        dec_inst = {OP_NOT, 5'd1, 5'd2, 5'd0, 13'd0}; #1;
        check(dec_opcode === OP_NOT && dec_op_group === OP_GROUP_LOGIC &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_NOT control flags correct");

        // OP_LOAD
        dec_inst = {OP_LOAD, 5'd1, 5'd2, 5'd0, 13'h0020}; #1;
        check(dec_opcode === OP_LOAD && dec_op_group === OP_GROUP_MEM &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b1 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b1 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_LOAD control flags correct (reg_write=1, mem_read=1, alu_src_imm=1)");

        // OP_STORE
        dec_inst = {OP_STORE, 5'd0, 5'd2, 5'd3, 13'h0020}; #1;
        check(dec_opcode === OP_STORE && dec_op_group === OP_GROUP_MEM &&
              dec_reg_write === 1'b0 && dec_mem_read === 1'b0 && dec_mem_write === 1'b1 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b1 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_STORE control flags correct (reg_write=0, mem_write=1, alu_src_imm=1)");

        // OP_MOV
        dec_inst = {OP_MOV, 5'd1, 5'd2, 5'd0, 13'd0}; #1;
        check(dec_opcode === OP_MOV && dec_op_group === OP_GROUP_MEM &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_MOV control flags correct (reg_write=1, mem_read=0)");

        // OP_LDI
        dec_inst = {OP_LDI, 5'd1, 5'd0, 5'd0, 13'h1FFF}; #1;
        check(dec_opcode === OP_LDI && dec_op_group === OP_GROUP_MEM &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b1 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_LDI control flags correct (reg_write=1, alu_src_imm=1)");

        // OP_BEQ
        dec_inst = {OP_BEQ, 5'd0, 5'd2, 5'd3, 13'h0008}; #1;
        check(dec_opcode === OP_BEQ && dec_op_group === OP_GROUP_CTRL &&
              dec_reg_write === 1'b0 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b1 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_BEQ control flags correct (is_branch=1, reg_write=0)");

        // OP_BNE
        dec_inst = {OP_BNE, 5'd0, 5'd2, 5'd3, 13'h1FF8}; #1;
        check(dec_opcode === OP_BNE && dec_op_group === OP_GROUP_CTRL &&
              dec_reg_write === 1'b0 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b1 && dec_is_jump === 1'b0 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_BNE control flags correct (is_branch=1, reg_write=0)");

        // OP_CALL
        dec_inst = {OP_CALL, 5'd31, 5'd0, 5'd0, 13'h0040}; #1;
        check(dec_opcode === OP_CALL && dec_op_group === OP_GROUP_CTRL &&
              dec_reg_write === 1'b1 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b0 && dec_is_call === 1'b1 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_CALL control flags correct (reg_write=1, is_call=1, is_jump=0)");

        // OP_JMP
        dec_inst = {OP_JMP, 5'd0, 5'd0, 5'd0, 13'h0020}; #1;
        check(dec_opcode === OP_JMP && dec_op_group === OP_GROUP_CTRL &&
              dec_reg_write === 1'b0 && dec_mem_read === 1'b0 && dec_mem_write === 1'b0 &&
              dec_is_branch === 1'b0 && dec_is_jump === 1'b1 && dec_is_call === 1'b0 &&
              dec_alu_src_imm === 1'b0 && dec_illegal_inst === 1'b0,
              "DECODER Controls: OP_JMP control flags correct (is_jump=1, reg_write=0, is_call=0)");

        // --------------------------------------------------------------------
        // FINAL SUMMARY
        // --------------------------------------------------------------------
        $display("\n================================================================================");
        $display(" VERIFICATION SUMMARY");
        $display("================================================================================");
        $display(" TOTAL CHECKS : %0d", total_checks);
        $display(" PASSED       : %0d", passed_checks);
        $display(" FAILED       : %0d", failed_checks);

        if (failed_checks == 0) begin
            $display("\n *** TEST PASSED: ALL EXECUTION PRIMITIVES CHECKS PASSED ***\n");
            $finish(0);
        end else begin
            $display("\n *** TEST FAILED: %0d CHECKS FAILED ***\n", failed_checks);
            $fatal(1, "Testbench failed assertions.");
        end
    end

endmodule
