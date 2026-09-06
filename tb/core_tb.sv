`timescale 1ns/1ps

// ==============================================================================
// S-256 Dual-Core E2E Verification Testbench (tb/core_tb.sv)
//
// Features Verified:
//   - Instantiates BOTH big_core (P-core) and little_core (E-core)
//   - Continuous cycle-by-cycle lockstep parity co-simulation
//   - Harvard memory architecture (64KB imem, 64KB dmem per core)
//   - Strict S-256 active-low reset discipline (rst_ni)
//   - Tier 1: 16/16 ISA instructions (>=5 tests per feature) on 64-bit data
//   - Tier 2: Boundary & corner cases (overflow, underflow, shift mask, r0, sign-ext)
//   - Tier 3: Cross-feature combinations (RAW hazards, call/ret, branch over store)
//   - Tier 4: Real-world scenarios (Fibonacci loop, Factorial subroutine, stack calls)
// ==============================================================================

import soc_pkg::*;

module core_tb;

    // --------------------------------------------------------------------------
    // Clock and Reset Signals
    // --------------------------------------------------------------------------
    logic clk;
    logic rst_ni;

    // --------------------------------------------------------------------------
    // P-Core (big_core) Memory Bus Interface
    // --------------------------------------------------------------------------
    logic [63:0] imem_addr_big;
    logic [31:0] imem_rdata_big;
    logic [63:0] dmem_addr_big;
    logic [63:0] dmem_wdata_big;
    logic [7:0]  dmem_wstrb_big;
    logic        dmem_wen_big;
    logic        dmem_ren_big;
    logic [63:0] dmem_rdata_big;

    // --------------------------------------------------------------------------
    // E-Core (little_core) Memory Bus Interface
    // --------------------------------------------------------------------------
    logic [63:0] imem_addr_lit;
    logic [31:0] imem_rdata_lit;
    logic [63:0] dmem_addr_lit;
    logic [63:0] dmem_wdata_lit;
    logic [7:0]  dmem_wstrb_lit;
    logic        dmem_wen_lit;
    logic        dmem_ren_lit;
    logic [63:0] dmem_rdata_lit;

    // --------------------------------------------------------------------------
    // Harvard Memory Models
    // --------------------------------------------------------------------------
    // Instruction Memory: 64 KB (16,384 x 32-bit words) shared between cores
    logic [31:0] imem_mem [0:16383];

    // Data Memory: 64 KB (8,192 x 64-bit words) dedicated per core
    logic [63:0] dmem_big [0:8191];
    logic [63:0] dmem_lit [0:8191];

    // Combinational Instruction Memory Fetch
    // Word address: imem_addr[15:2]
    assign imem_rdata_big = (imem_addr_big < 64'h10000) ? imem_mem[imem_addr_big[15:2]] : 32'h0;
    assign imem_rdata_lit = (imem_addr_lit < 64'h10000) ? imem_mem[imem_addr_lit[15:2]] : 32'h0;

    // Combinational Data Memory Read
    // Doubleword address: dmem_addr[15:3]
    assign dmem_rdata_big = (dmem_addr_big < 64'h10000) ? dmem_big[dmem_addr_big[15:3]] : 64'h0;
    assign dmem_rdata_lit = (dmem_addr_lit < 64'h10000) ? dmem_lit[dmem_addr_lit[15:3]] : 64'h0;

    // Synchronous Data Memory Write (with byte strobes)
    integer b;
    always_ff @(posedge clk) begin
        if (dmem_wen_big && (dmem_addr_big < 64'h10000)) begin
            for (b = 0; b < 8; b = b + 1) begin
                if (dmem_wstrb_big[b]) begin
                    dmem_big[dmem_addr_big[15:3]][b*8 +: 8] <= dmem_wdata_big[b*8 +: 8];
                end
            end
        end
        if (dmem_wen_lit && (dmem_addr_lit < 64'h10000)) begin
            for (b = 0; b < 8; b = b + 1) begin
                if (dmem_wstrb_lit[b]) begin
                    dmem_lit[dmem_addr_lit[15:3]][b*8 +: 8] <= dmem_wdata_lit[b*8 +: 8];
                end
            end
        end
    end

    // --------------------------------------------------------------------------
    // Dual-Core Device Under Test (DUT) Instantiation
    // --------------------------------------------------------------------------
    big_core u_big_core (
        .clk        (clk),
        .rst_ni     (rst_ni),
        .imem_addr  (imem_addr_big),
        .imem_rdata (imem_rdata_big),
        .dmem_addr  (dmem_addr_big),
        .dmem_wdata (dmem_wdata_big),
        .dmem_wstrb (dmem_wstrb_big),
        .dmem_wen   (dmem_wen_big),
        .dmem_ren   (dmem_ren_big),
        .dmem_rdata (dmem_rdata_big)
    );

    little_core u_little_core (
        .clk        (clk),
        .rst_ni     (rst_ni),
        .imem_addr  (imem_addr_lit),
        .imem_rdata (imem_rdata_lit),
        .dmem_addr  (dmem_addr_lit),
        .dmem_wdata (dmem_wdata_lit),
        .dmem_wstrb (dmem_wstrb_lit),
        .dmem_wen   (dmem_wen_lit),
        .dmem_ren   (dmem_ren_lit),
        .dmem_rdata (dmem_rdata_lit)
    );

    // --------------------------------------------------------------------------
    // Testbench Statistics & Bookkeeping
    // --------------------------------------------------------------------------
    int pass_count       = 0;
    int fail_count       = 0;
    int check_id         = 0;
    int parity_err_count = 0;

    // --------------------------------------------------------------------------
    // Clock Generation (100 MHz, 10 ns period)
    // --------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --------------------------------------------------------------------------
    // Continuous Dual-Core Parity Verification (All cycles including reset)
    always @(posedge clk) begin
        if (imem_addr_big !== imem_addr_lit) begin
            $display("  [FAIL] PARITY ERROR: imem_addr mismatch! Big=0x%016h, Lit=0x%016h at %0t (rst_ni=%b)",
                     imem_addr_big, imem_addr_lit, $time, rst_ni);
            fail_count++;
            parity_err_count++;
        end
        if (dmem_wen_big !== dmem_wen_lit) begin
            $display("  [FAIL] PARITY ERROR: dmem_wen mismatch! Big=%b, Lit=%b at %0t (rst_ni=%b)",
                     dmem_wen_big, dmem_wen_lit, $time, rst_ni);
            fail_count++;
            parity_err_count++;
        end
        if (dmem_ren_big !== dmem_ren_lit) begin
            $display("  [FAIL] PARITY ERROR: dmem_ren mismatch! Big=%b, Lit=%b at %0t (rst_ni=%b)",
                     dmem_ren_big, dmem_ren_lit, $time, rst_ni);
            fail_count++;
            parity_err_count++;
        end
        if (dmem_wen_big && (dmem_addr_big !== dmem_addr_lit || dmem_wdata_big !== dmem_wdata_lit)) begin
            $display("  [FAIL] PARITY ERROR: dmem write mismatch! Big=[0x%016h]=0x%016h, Lit=[0x%016h]=0x%016h at %0t (rst_ni=%b)",
                     dmem_addr_big, dmem_wdata_big, dmem_addr_lit, dmem_wdata_lit, $time, rst_ni);
            fail_count++;
            parity_err_count++;
        end
    end

    // --------------------------------------------------------------------------
    // Instruction Synthesis Helpers
    // --------------------------------------------------------------------------
    function automatic logic [31:0] encode_raw(
        input logic [3:0]  op,
        input logic [4:0]  d,
        input logic [4:0]  s1,
        input logic [4:0]  s2,
        input logic [12:0] imm
    );
        encode_raw = {op, d, s1, s2, imm};
    endfunction

    function automatic logic [31:0] inst_add(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2);
        return encode_raw(soc_pkg::OP_ADD, rd, rs1, rs2, 13'd0);
    endfunction

    function automatic logic [31:0] inst_sub(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2);
        return encode_raw(soc_pkg::OP_SUB, rd, rs1, rs2, 13'd0);
    endfunction

    function automatic logic [31:0] inst_shl(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2);
        return encode_raw(soc_pkg::OP_SHL, rd, rs1, rs2, 13'd0);
    endfunction

    function automatic logic [31:0] inst_shr(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2);
        return encode_raw(soc_pkg::OP_SHR, rd, rs1, rs2, 13'd0);
    endfunction

    function automatic logic [31:0] inst_and(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2);
        return encode_raw(soc_pkg::OP_AND, rd, rs1, rs2, 13'd0);
    endfunction

    function automatic logic [31:0] inst_or(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2);
        return encode_raw(soc_pkg::OP_OR, rd, rs1, rs2, 13'd0);
    endfunction

    function automatic logic [31:0] inst_xor(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2);
        return encode_raw(soc_pkg::OP_XOR, rd, rs1, rs2, 13'd0);
    endfunction

    function automatic logic [31:0] inst_not(input logic [4:0] rd, input logic [4:0] rs1);
        return encode_raw(soc_pkg::OP_NOT, rd, rs1, 5'd0, 13'd0);
    endfunction

    function automatic logic [31:0] inst_load(input logic [4:0] rd, input logic [4:0] rs1, input logic [12:0] imm);
        return encode_raw(soc_pkg::OP_LOAD, rd, rs1, 5'd0, imm);
    endfunction

    function automatic logic [31:0] inst_store(input logic [4:0] rs2, input logic [4:0] rs1, input logic [12:0] imm);
        return encode_raw(soc_pkg::OP_STORE, 5'd0, rs1, rs2, imm);
    endfunction

    function automatic logic [31:0] inst_mov(input logic [4:0] rd, input logic [4:0] rs1);
        return encode_raw(soc_pkg::OP_MOV, rd, rs1, 5'd0, 13'd0);
    endfunction

    function automatic logic [31:0] inst_ldi(input logic [4:0] rd, input logic [12:0] imm);
        return encode_raw(soc_pkg::OP_LDI, rd, 5'd0, 5'd0, imm);
    endfunction

    function automatic logic [31:0] inst_beq(input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:0] imm);
        return encode_raw(soc_pkg::OP_BEQ, 5'd0, rs1, rs2, imm);
    endfunction

    function automatic logic [31:0] inst_bne(input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:0] imm);
        return encode_raw(soc_pkg::OP_BNE, 5'd0, rs1, rs2, imm);
    endfunction

    function automatic logic [31:0] inst_call(input logic [4:0] rd, input logic [12:0] imm);
        return encode_raw(soc_pkg::OP_CALL, rd, 5'd0, 5'd0, imm);
    endfunction

    function automatic logic [31:0] inst_jmp(input logic [4:0] rs1, input logic [12:0] imm);
        return encode_raw(soc_pkg::OP_JMP, 5'd0, rs1, 5'd0, imm);
    endfunction

    // --------------------------------------------------------------------------
    // Test Harness Control Tasks
    // --------------------------------------------------------------------------
    task automatic reset_cores();
        rst_ni = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_ni = 1'b1;
        @(posedge clk);
    endtask

    task automatic clear_mem();
        integer m;
        for (m = 0; m < 16384; m = m + 1) begin
            imem_mem[m] = 32'h0;
        end
        for (m = 0; m < 8192; m = m + 1) begin
            dmem_big[m] = 64'h0;
            dmem_lit[m] = 64'h0;
        end
    endtask

    task automatic step_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task automatic check_dmem(input string desc, input int word_idx, input logic [63:0] expected);
        check_id++;
        if (dmem_big[word_idx] === expected && dmem_lit[word_idx] === expected) begin
            $display("  [PASS #%0d] %s (dmem[%0d]=0x%016h)", check_id, desc, word_idx, expected);
            pass_count++;
        end else begin
            $display("  [FAIL #%0d] %s: Expected 0x%016h, Got Big=0x%016h, Lit=0x%016h",
                     check_id, desc, expected, dmem_big[word_idx], dmem_lit[word_idx]);
            fail_count++;
        end
    endtask

    task automatic check_value(input string desc, input logic [63:0] actual, input logic [63:0] expected);
        check_id++;
        if (actual === expected) begin
            $display("  [PASS #%0d] %s: 0x%016h", check_id, desc, actual);
            pass_count++;
        end else begin
            $display("  [FAIL #%0d] %s: Expected 0x%016h, Got 0x%016h", check_id, desc, expected, actual);
            fail_count++;
        end
    endtask

    // --------------------------------------------------------------------------
    // TIER 1: Feature Coverage (All 16 Instructions >=5 Tests Each)
    // --------------------------------------------------------------------------

    // --- 1.1 ADD Tests ---
    task automatic test_tier1_add();
        $display("\n--- [Tier 1.1] ADD Instruction Verification (5 Tests) ---");
        clear_mem();
        // Setup initial operands in dmem:
        dmem_big[0] = 64'd5;                   dmem_lit[0] = 64'd5;
        dmem_big[1] = 64'd10;                  dmem_lit[1] = 64'd10;
        dmem_big[2] = 64'h0000_0000_1234_5678; dmem_lit[2] = 64'h0000_0000_1234_5678;
        dmem_big[3] = 64'h0000_0000_0000_0001; dmem_lit[3] = 64'h0000_0000_0000_0001;
        dmem_big[4] = 64'h1000_0000_0000_0000; dmem_lit[4] = 64'h1000_0000_0000_0000;
        dmem_big[5] = 64'h2000_0000_0000_0000; dmem_lit[5] = 64'h2000_0000_0000_0000;
        dmem_big[6] = 64'd50;                  dmem_lit[6] = 64'd50;
        dmem_big[7] = -64'd50;                 dmem_lit[7] = -64'd50;

        // Assembly program:
        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 5
        imem_mem[1]  = inst_load(5'd2, 5'd0, 13'd8);       // r2 = 10
        imem_mem[2]  = inst_add(5'd3, 5'd1, 5'd2);         // r3 = 5 + 10 = 15
        imem_mem[3]  = inst_store(5'd3, 5'd0, 13'd80);     // dmem[10] = 15

        imem_mem[4]  = inst_load(5'd4, 5'd0, 13'd16);      // r4 = 0x1234_5678
        imem_mem[5]  = inst_load(5'd5, 5'd0, 13'd24);      // r5 = 1
        imem_mem[6]  = inst_add(5'd6, 5'd4, 5'd5);         // r6 = 0x1234_5679
        imem_mem[7]  = inst_store(5'd6, 5'd0, 13'd88);     // dmem[11] = 0x1234_5679

        imem_mem[8]  = inst_load(5'd7, 5'd0, 13'd32);      // r7 = 0x1000...
        imem_mem[9]  = inst_load(5'd8, 5'd0, 13'd40);      // r8 = 0x2000...
        imem_mem[10] = inst_add(5'd9, 5'd7, 5'd8);         // r9 = 0x3000...
        imem_mem[11] = inst_store(5'd9, 5'd0, 13'd96);     // dmem[12] = 0x3000...

        imem_mem[12] = inst_load(5'd10, 5'd0, 13'd48);     // r10 = 50
        imem_mem[13] = inst_load(5'd11, 5'd0, 13'd56);     // r11 = -50
        imem_mem[14] = inst_add(5'd12, 5'd10, 5'd11);      // r12 = 50 + (-50) = 0
        imem_mem[15] = inst_store(5'd12, 5'd0, 13'd104);   // dmem[13] = 0

        imem_mem[16] = inst_add(5'd13, 5'd1, 5'd1);        // r13 = r1 + r1 = 10
        imem_mem[17] = inst_store(5'd13, 5'd0, 13'd112);   // dmem[14] = 10
        imem_mem[18] = inst_beq(5'd0, 5'd0, 13'd0);        // loop halt

        reset_cores();
        step_cycles(25);

        check_dmem("ADD small positive: 5 + 10", 10, 64'd15);
        check_dmem("ADD 32-bit boundary: 0x12345678 + 1", 11, 64'h0000_0000_1234_5679);
        check_dmem("ADD 64-bit high: 0x1000... + 0x2000...", 12, 64'h3000_0000_0000_0000);
        check_dmem("ADD pos + neg cancel: 50 + (-50)", 13, 64'd0);
        check_dmem("ADD self-addition: r1 + r1", 14, 64'd10);
    endtask

    // --- 1.2 SUB Tests ---
    task automatic test_tier1_sub();
        $display("\n--- [Tier 1.2] SUB Instruction Verification (5 Tests) ---");
        clear_mem();
        dmem_big[0] = 64'd20;                  dmem_lit[0] = 64'd20;
        dmem_big[1] = 64'd7;                   dmem_lit[1] = 64'd7;
        dmem_big[2] = 64'hDEAD_BEEF_CAFE_1234; dmem_lit[2] = 64'hDEAD_BEEF_CAFE_1234;
        dmem_big[3] = 64'd10;                  dmem_lit[3] = 64'd10;
        dmem_big[4] = 64'd25;                  dmem_lit[4] = 64'd25;
        dmem_big[5] = 64'd100;                 dmem_lit[5] = 64'd100;
        dmem_big[6] = -64'd50;                 dmem_lit[6] = -64'd50;
        dmem_big[7] = 64'h5555_5555_5555_5555; dmem_lit[7] = 64'h5555_5555_5555_5555;
        dmem_big[8] = 64'h1111_1111_1111_1111; dmem_lit[8] = 64'h1111_1111_1111_1111;

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 20
        imem_mem[1]  = inst_load(5'd2, 5'd0, 13'd8);       // r2 = 7
        imem_mem[2]  = inst_sub(5'd3, 5'd1, 5'd2);         // r3 = 20 - 7 = 13
        imem_mem[3]  = inst_store(5'd3, 5'd0, 13'd80);     // dmem[10] = 13

        imem_mem[4]  = inst_load(5'd4, 5'd0, 13'd16);      // r4 = 0xDEAD...
        imem_mem[5]  = inst_sub(5'd5, 5'd4, 5'd4);         // r5 = r4 - r4 = 0
        imem_mem[6]  = inst_store(5'd5, 5'd0, 13'd88);     // dmem[11] = 0

        imem_mem[7]  = inst_load(5'd6, 5'd0, 13'd24);      // r6 = 10
        imem_mem[8]  = inst_load(5'd7, 5'd0, 13'd32);      // r7 = 25
        imem_mem[9]  = inst_sub(5'd8, 5'd6, 5'd7);         // r8 = 10 - 25 = -15
        imem_mem[10] = inst_store(5'd8, 5'd0, 13'd96);     // dmem[12] = -15

        imem_mem[11] = inst_load(5'd9, 5'd0, 13'd40);      // r9 = 100
        imem_mem[12] = inst_load(5'd10, 5'd0, 13'd48);     // r10 = -50
        imem_mem[13] = inst_sub(5'd11, 5'd9, 5'd10);       // r11 = 100 - (-50) = 150
        imem_mem[14] = inst_store(5'd11, 5'd0, 13'd104);   // dmem[13] = 150

        imem_mem[15] = inst_load(5'd12, 5'd0, 13'd56);     // r12 = 0x5555...
        imem_mem[16] = inst_load(5'd13, 5'd0, 13'd64);     // r13 = 0x1111...
        imem_mem[17] = inst_sub(5'd14, 5'd12, 5'd13);      // r14 = 0x4444...
        imem_mem[18] = inst_store(5'd14, 5'd0, 13'd112);   // dmem[14] = 0x4444...
        imem_mem[19] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(25);

        check_dmem("SUB small positive: 20 - 7", 10, 64'd13);
        check_dmem("SUB self-cancel: X - X", 11, 64'd0);
        check_dmem("SUB yielding negative: 10 - 25", 12, 64'hFFFF_FFFF_FFFF_FFF1);
        check_dmem("SUB negative: 100 - (-50)", 13, 64'd150);
        check_dmem("SUB 64-bit pattern: 0x5555... - 0x1111...", 14, 64'h4444_4444_4444_4444);
    endtask

    // --- 1.3 SHL Tests ---
    task automatic test_tier1_shl();
        $display("\n--- [Tier 1.3] SHL Instruction Verification (5 Tests) ---");
        clear_mem();
        dmem_big[0] = 64'd1;                   dmem_lit[0] = 64'd1;
        dmem_big[1] = 64'h0000_0000_0000_00FF; dmem_lit[1] = 64'h0000_0000_0000_00FF;
        dmem_big[2] = 64'h0000_0000_FFFF_FFFF; dmem_lit[2] = 64'h0000_0000_FFFF_FFFF;
        dmem_big[3] = 64'h5555_5555_5555_5555; dmem_lit[3] = 64'h5555_5555_5555_5555;

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 1
        imem_mem[1]  = inst_ldi(5'd2, 13'd1);              // r2 = 1 (shamt)
        imem_mem[2]  = inst_shl(5'd3, 5'd1, 5'd2);         // r3 = 1 << 1 = 2
        imem_mem[3]  = inst_store(5'd3, 5'd0, 13'd80);     // dmem[10]

        imem_mem[4]  = inst_load(5'd4, 5'd0, 13'd8);       // r4 = 0xFF
        imem_mem[5]  = inst_ldi(5'd5, 13'd8);              // r5 = 8
        imem_mem[6]  = inst_shl(5'd6, 5'd4, 5'd5);         // r6 = 0xFF00
        imem_mem[7]  = inst_store(5'd6, 5'd0, 13'd88);     // dmem[11]

        imem_mem[8]  = inst_load(5'd7, 5'd0, 13'd16);      // r7 = 0xFFFF_FFFF
        imem_mem[9]  = inst_ldi(5'd8, 13'd32);             // r8 = 32
        imem_mem[10] = inst_shl(5'd9, 5'd7, 5'd8);         // r9 = 0xFFFF_FFFF_0000_0000
        imem_mem[11] = inst_store(5'd9, 5'd0, 13'd96);     // dmem[12]

        imem_mem[12] = inst_ldi(5'd10, 13'd60);            // r10 = 60
        imem_mem[13] = inst_shl(5'd11, 5'd1, 5'd10);       // r11 = 1 << 60 = 0x1000_0000_0000_0000
        imem_mem[14] = inst_store(5'd11, 5'd0, 13'd104);   // dmem[13]

        imem_mem[15] = inst_load(5'd12, 5'd0, 13'd24);     // r12 = 0x5555...
        imem_mem[16] = inst_ldi(5'd13, 13'd2);             // r13 = 2
        imem_mem[17] = inst_shl(5'd14, 5'd12, 5'd13);      // r14 = 0x5555...5554
        imem_mem[18] = inst_store(5'd14, 5'd0, 13'd112);   // dmem[14]
        imem_mem[19] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(25);

        check_dmem("SHL 1 bit: 1 << 1", 10, 64'd2);
        check_dmem("SHL 8 bits: 0xFF << 8", 11, 64'hFF00);
        check_dmem("SHL 32 bits: 0xFFFF_FFFF << 32", 12, 64'hFFFF_FFFF_0000_0000);
        check_dmem("SHL 60 bits: 1 << 60", 13, 64'h1000_0000_0000_0000);
        check_dmem("SHL pattern: 0x5555... << 2", 14, 64'h5555_5555_5555_5554);
    endtask

    // --- 1.4 SHR Tests ---
    task automatic test_tier1_shr();
        $display("\n--- [Tier 1.4] SHR Instruction Verification (5 Tests) ---");
        clear_mem();
        dmem_big[0] = 64'd2;                   dmem_lit[0] = 64'd2;
        dmem_big[1] = 64'hFF00;                dmem_lit[1] = 64'hFF00;
        dmem_big[2] = 64'hFFFF_FFFF_0000_0000; dmem_lit[2] = 64'hFFFF_FFFF_0000_0000;
        dmem_big[3] = 64'h8000_0000_0000_0000; dmem_lit[3] = 64'h8000_0000_0000_0000;

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 2
        imem_mem[1]  = inst_ldi(5'd2, 13'd1);              // r2 = 1
        imem_mem[2]  = inst_shr(5'd3, 5'd1, 5'd2);         // r3 = 2 >> 1 = 1
        imem_mem[3]  = inst_store(5'd3, 5'd0, 13'd80);     // dmem[10]

        imem_mem[4]  = inst_load(5'd4, 5'd0, 13'd8);       // r4 = 0xFF00
        imem_mem[5]  = inst_ldi(5'd5, 13'd8);              // r5 = 8
        imem_mem[6]  = inst_shr(5'd6, 5'd4, 5'd5);         // r6 = 0x00FF
        imem_mem[7]  = inst_store(5'd6, 5'd0, 13'd88);     // dmem[11]

        imem_mem[8]  = inst_load(5'd7, 5'd0, 13'd16);      // r7 = 0xFFFF_FFFF_0000_0000
        imem_mem[9]  = inst_ldi(5'd8, 13'd32);             // r8 = 32
        imem_mem[10] = inst_shr(5'd9, 5'd7, 5'd8);         // r9 = 0x0000_0000_FFFF_FFFF
        imem_mem[11] = inst_store(5'd9, 5'd0, 13'd96);     // dmem[12]

        imem_mem[12] = inst_load(5'd10, 5'd0, 13'd24);     // r10 = 0x8000_0000_0000_0000
        imem_mem[13] = inst_ldi(5'd11, 13'd60);            // r11 = 60
        imem_mem[14] = inst_shr(5'd12, 5'd10, 5'd11);      // r12 = 8
        imem_mem[15] = inst_store(5'd12, 5'd0, 13'd104);   // dmem[13]

        imem_mem[16] = inst_ldi(5'd13, 13'd1);             // r13 = 1
        imem_mem[17] = inst_shr(5'd14, 5'd10, 5'd13);      // r14 = 0x4000_0000_0000_0000 (zero-fill)
        imem_mem[18] = inst_store(5'd14, 5'd0, 13'd112);   // dmem[14]
        imem_mem[19] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(25);

        check_dmem("SHR 1 bit: 2 >> 1", 10, 64'd1);
        check_dmem("SHR 8 bits: 0xFF00 >> 8", 11, 64'hFF);
        check_dmem("SHR 32 bits: 0xFFFF_FFFF_0000_0000 >> 32", 12, 64'hFFFF_FFFF);
        check_dmem("SHR 60 bits: 0x8000... >> 60", 13, 64'd8);
        check_dmem("SHR logical zero-fill: 0x8000... >> 1", 14, 64'h4000_0000_0000_0000);
    endtask

    // --- 1.5 AND Tests ---
    task automatic test_tier1_and();
        $display("\n--- [Tier 1.5] AND Instruction Verification (5 Tests) ---");
        clear_mem();
        dmem_big[0] = 64'hFFFF_0000_FFFF_0000; dmem_lit[0] = 64'hFFFF_0000_FFFF_0000;
        dmem_big[1] = 64'h0000_FFFF_0000_FFFF; dmem_lit[1] = 64'h0000_FFFF_0000_FFFF;
        dmem_big[2] = 64'hDEAD_BEEF_CAFE_BABE; dmem_lit[2] = 64'hDEAD_BEEF_CAFE_BABE;
        dmem_big[3] = 64'hFFFF_FFFF_FFFF_FFFF; dmem_lit[3] = 64'hFFFF_FFFF_FFFF_FFFF;
        dmem_big[4] = 64'hAAAA_AAAA_AAAA_AAAA; dmem_lit[4] = 64'hAAAA_AAAA_AAAA_AAAA;
        dmem_big[5] = 64'h5555_5555_5555_5555; dmem_lit[5] = 64'h5555_5555_5555_5555;

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 0xFFFF_0000_FFFF_0000
        imem_mem[1]  = inst_load(5'd2, 5'd0, 13'd8);       // r2 = 0x0000_FFFF_0000_FFFF
        imem_mem[2]  = inst_and(5'd3, 5'd1, 5'd2);         // r3 = 0
        imem_mem[3]  = inst_store(5'd3, 5'd0, 13'd80);     // dmem[10] = 0

        imem_mem[4]  = inst_load(5'd4, 5'd0, 13'd16);      // r4 = 0xDEAD...
        imem_mem[5]  = inst_load(5'd5, 5'd0, 13'd24);      // r5 = ~0
        imem_mem[6]  = inst_and(5'd6, 5'd4, 5'd5);         // r6 = 0xDEAD... (identity)
        imem_mem[7]  = inst_store(5'd6, 5'd0, 13'd88);     // dmem[11]

        imem_mem[8]  = inst_and(5'd7, 5'd4, 5'd0);         // r7 = r4 & r0 = 0
        imem_mem[9]  = inst_store(5'd7, 5'd0, 13'd96);     // dmem[12] = 0

        imem_mem[10] = inst_load(5'd8, 5'd0, 13'd32);      // r8 = 0xAAAA...
        imem_mem[11] = inst_load(5'd9, 5'd0, 13'd40);      // r9 = 0x5555...
        imem_mem[12] = inst_and(5'd10, 5'd8, 5'd9);        // r10 = 0
        imem_mem[13] = inst_store(5'd10, 5'd0, 13'd104);   // dmem[13] = 0

        imem_mem[14] = inst_and(5'd11, 5'd4, 5'd4);        // r11 = r4 & r4 = r4
        imem_mem[15] = inst_store(5'd11, 5'd0, 13'd112);   // dmem[14] = 0xDEAD...
        imem_mem[16] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(25);

        check_dmem("AND disjoint masks: 0", 10, 64'd0);
        check_dmem("AND all-ones identity", 11, 64'hDEAD_BEEF_CAFE_BABE);
        check_dmem("AND with r0 zero", 12, 64'd0);
        check_dmem("AND alternating patterns: 0", 13, 64'd0);
        check_dmem("AND self-identity", 14, 64'hDEAD_BEEF_CAFE_BABE);
    endtask

    // --- 1.6 OR Tests ---
    task automatic test_tier1_or();
        $display("\n--- [Tier 1.6] OR Instruction Verification (5 Tests) ---");
        clear_mem();
        dmem_big[0] = 64'hFFFF_0000_0000_0000; dmem_lit[0] = 64'hFFFF_0000_0000_0000;
        dmem_big[1] = 64'h0000_0000_0000_FFFF; dmem_lit[1] = 64'h0000_0000_0000_FFFF;
        dmem_big[2] = 64'h1234_5678_9ABC_DEF0; dmem_lit[2] = 64'h1234_5678_9ABC_DEF0;
        dmem_big[3] = 64'hFFFF_FFFF_FFFF_FFFF; dmem_lit[3] = 64'hFFFF_FFFF_FFFF_FFFF;
        dmem_big[4] = 64'hAAAA_AAAA_AAAA_AAAA; dmem_lit[4] = 64'hAAAA_AAAA_AAAA_AAAA;
        dmem_big[5] = 64'h5555_5555_5555_5555; dmem_lit[5] = 64'h5555_5555_5555_5555;

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 0xFFFF...
        imem_mem[1]  = inst_load(5'd2, 5'd0, 13'd8);       // r2 = 0x...FFFF
        imem_mem[2]  = inst_or(5'd3, 5'd1, 5'd2);          // r3 = 0xFFFF_0000_0000_FFFF
        imem_mem[3]  = inst_store(5'd3, 5'd0, 13'd80);     // dmem[10]

        imem_mem[4]  = inst_load(5'd4, 5'd0, 13'd16);      // r4 = 0x1234...
        imem_mem[5]  = inst_or(5'd5, 5'd4, 5'd0);          // r5 = r4 | r0 = r4
        imem_mem[6]  = inst_store(5'd5, 5'd0, 13'd88);     // dmem[11]

        imem_mem[7]  = inst_load(5'd6, 5'd0, 13'd24);      // r6 = ~0
        imem_mem[8]  = inst_or(5'd7, 5'd4, 5'd6);          // r7 = ~0
        imem_mem[9]  = inst_store(5'd7, 5'd0, 13'd96);     // dmem[12]

        imem_mem[10] = inst_load(5'd8, 5'd0, 13'd32);      // r8 = 0xAAAA...
        imem_mem[11] = inst_load(5'd9, 5'd0, 13'd40);      // r9 = 0x5555...
        imem_mem[12] = inst_or(5'd10, 5'd8, 5'd9);         // r10 = ~0
        imem_mem[13] = inst_store(5'd10, 5'd0, 13'd104);   // dmem[13]

        imem_mem[14] = inst_or(5'd11, 5'd4, 5'd4);         // r11 = r4 | r4 = r4
        imem_mem[15] = inst_store(5'd11, 5'd0, 13'd112);   // dmem[14]
        imem_mem[16] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(25);

        check_dmem("OR disjoint fields", 10, 64'hFFFF_0000_0000_FFFF);
        check_dmem("OR with r0 identity", 11, 64'h1234_5678_9ABC_DEF0);
        check_dmem("OR with all-ones saturation", 12, 64'hFFFF_FFFF_FFFF_FFFF);
        check_dmem("OR alternating patterns: ~0", 13, 64'hFFFF_FFFF_FFFF_FFFF);
        check_dmem("OR self-identity", 14, 64'h1234_5678_9ABC_DEF0);
    endtask

    // --- 1.7 XOR Tests ---
    task automatic test_tier1_xor();
        $display("\n--- [Tier 1.7] XOR Instruction Verification (5 Tests) ---");
        clear_mem();
        dmem_big[0] = 64'h1234_5678_9ABC_DEF0; dmem_lit[0] = 64'h1234_5678_9ABC_DEF0;
        dmem_big[1] = 64'h0F0F_0F0F_0F0F_0F0F; dmem_lit[1] = 64'h0F0F_0F0F_0F0F_0F0F;
        dmem_big[2] = 64'hFFFF_FFFF_FFFF_FFFF; dmem_lit[2] = 64'hFFFF_FFFF_FFFF_FFFF;
        dmem_big[3] = 64'hAAAA_AAAA_AAAA_AAAA; dmem_lit[3] = 64'hAAAA_AAAA_AAAA_AAAA;
        dmem_big[4] = 64'h5555_5555_5555_5555; dmem_lit[4] = 64'h5555_5555_5555_5555;

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 0x1234...
        imem_mem[1]  = inst_xor(5'd2, 5'd1, 5'd1);         // r2 = r1 ^ r1 = 0
        imem_mem[2]  = inst_store(5'd2, 5'd0, 13'd80);     // dmem[10] = 0

        imem_mem[3]  = inst_load(5'd3, 5'd0, 13'd8);       // r3 = 0x0F0F...
        imem_mem[4]  = inst_load(5'd4, 5'd0, 13'd16);      // r4 = ~0
        imem_mem[5]  = inst_xor(5'd5, 5'd3, 5'd4);         // r5 = 0xF0F0...
        imem_mem[6]  = inst_store(5'd5, 5'd0, 13'd88);     // dmem[11]

        imem_mem[7]  = inst_xor(5'd6, 5'd1, 5'd0);         // r6 = r1 ^ 0 = r1
        imem_mem[8]  = inst_store(5'd6, 5'd0, 13'd96);     // dmem[12]

        imem_mem[9]  = inst_load(5'd7, 5'd0, 13'd24);      // r7 = 0xAAAA...
        imem_mem[10] = inst_load(5'd8, 5'd0, 13'd32);      // r8 = 0x5555...
        imem_mem[11] = inst_xor(5'd9, 5'd7, 5'd8);         // r9 = ~0
        imem_mem[12] = inst_store(5'd9, 5'd0, 13'd104);    // dmem[13]

        imem_mem[13] = inst_xor(5'd10, 5'd9, 5'd8);        // r10 = (~0) ^ 0x5555... = 0xAAAA... (reversibility)
        imem_mem[14] = inst_store(5'd10, 5'd0, 13'd112);   // dmem[14]
        imem_mem[15] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(25);

        check_dmem("XOR self-annihilation: 0", 10, 64'd0);
        check_dmem("XOR bit invert mask", 11, 64'hF0F0_F0F0_F0F0_F0F0);
        check_dmem("XOR with r0 identity", 12, 64'h1234_5678_9ABC_DEF0);
        check_dmem("XOR alternating patterns: ~0", 13, 64'hFFFF_FFFF_FFFF_FFFF);
        check_dmem("XOR reversibility (A^B)^B = A", 14, 64'hAAAA_AAAA_AAAA_AAAA);
    endtask

    // --- 1.8 NOT Tests ---
    task automatic test_tier1_not();
        $display("\n--- [Tier 1.8] NOT Instruction Verification (5 Tests) ---");
        clear_mem();
        dmem_big[0] = 64'h0000_0000_0000_0000; dmem_lit[0] = 64'h0000_0000_0000_0000;
        dmem_big[1] = 64'hFFFF_FFFF_FFFF_FFFF; dmem_lit[1] = 64'hFFFF_FFFF_FFFF_FFFF;
        dmem_big[2] = 64'hAAAA_AAAA_AAAA_AAAA; dmem_lit[2] = 64'hAAAA_AAAA_AAAA_AAAA;
        dmem_big[3] = 64'h0000_0000_0000_0001; dmem_lit[3] = 64'h0000_0000_0000_0001;
        dmem_big[4] = 64'hCAFE_BABE_DEAD_BEEF; dmem_lit[4] = 64'hCAFE_BABE_DEAD_BEEF;

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 0
        imem_mem[1]  = inst_not(5'd2, 5'd1);               // r2 = ~0 = 0xFFFF_FFFF_FFFF_FFFF
        imem_mem[2]  = inst_store(5'd2, 5'd0, 13'd80);     // dmem[10]

        imem_mem[3]  = inst_load(5'd3, 5'd0, 13'd8);       // r3 = ~0
        imem_mem[4]  = inst_not(5'd4, 5'd3);               // r4 = 0
        imem_mem[5]  = inst_store(5'd4, 5'd0, 13'd88);     // dmem[11]

        imem_mem[6]  = inst_load(5'd5, 5'd0, 13'd16);      // r5 = 0xAAAA...
        imem_mem[7]  = inst_not(5'd6, 5'd5);               // r6 = 0x5555...
        imem_mem[8]  = inst_store(5'd6, 5'd0, 13'd96);     // dmem[12]

        imem_mem[9]  = inst_load(5'd7, 5'd0, 13'd24);      // r7 = 1
        imem_mem[10] = inst_not(5'd8, 5'd7);               // r8 = ~1 = 0xFFFF_FFFF_FFFF_FFFE
        imem_mem[11] = inst_store(5'd8, 5'd0, 13'd104);    // dmem[13]

        imem_mem[12] = inst_load(5'd9, 5'd0, 13'd32);      // r9 = 0xCAFE...
        imem_mem[13] = inst_not(5'd10, 5'd9);              // r10 = ~r9
        imem_mem[14] = inst_not(5'd11, 5'd10);             // r11 = ~(~r9) = r9
        imem_mem[15] = inst_store(5'd11, 5'd0, 13'd112);   // dmem[14]
        imem_mem[16] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(25);

        check_dmem("NOT zero: ~0", 10, 64'hFFFF_FFFF_FFFF_FFFF);
        check_dmem("NOT all-ones: 0", 11, 64'd0);
        check_dmem("NOT alternating pattern", 12, 64'h5555_5555_5555_5555);
        check_dmem("NOT 1: ~1", 13, 64'hFFFF_FFFF_FFFF_FFFE);
        check_dmem("Double NOT restoration", 14, 64'hCAFE_BABE_DEAD_BEEF);
    endtask

    // --- 1.9 & 1.10 LOAD & STORE Tests ---
    task automatic test_tier1_load_store();
        $display("\n--- [Tier 1.9 & 1.10] LOAD & STORE Verification (5 Tests) ---");
        clear_mem();
        dmem_big[0] = 64'h1111_2222_3333_4444; dmem_lit[0] = 64'h1111_2222_3333_4444;
        dmem_big[1] = 64'h5555_6666_7777_8888; dmem_lit[1] = 64'h5555_6666_7777_8888;
        dmem_big[2] = 64'h9999_AAAA_BBBB_CCCC; dmem_lit[2] = 64'h9999_AAAA_BBBB_CCCC;

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = dmem[0]
        imem_mem[1]  = inst_store(5'd1, 5'd0, 13'd80);     // dmem[10] = r1 (offset 0 test)

        imem_mem[2]  = inst_load(5'd2, 5'd0, 13'd8);       // r2 = dmem[1] (pos offset +8)
        imem_mem[3]  = inst_store(5'd2, 5'd0, 13'd88);     // dmem[11] = r2

        imem_mem[4]  = inst_load(5'd3, 5'd0, 13'd16);      // r3 = dmem[2] (pos offset +16)
        imem_mem[5]  = inst_store(5'd3, 5'd0, 13'd96);     // dmem[12] = r3

        // Base register pointer test (using r4 as base pointer)
        imem_mem[6]  = inst_ldi(5'd4, 13'd64);             // r4 = 64 (byte addr of dmem[8])
        imem_mem[7]  = inst_store(5'd1, 5'd4, 13'd40);     // dmem[(64+40)/8] = dmem[13] = r1
        imem_mem[8]  = inst_load(5'd5, 5'd4, 13'd40);      // r5 = dmem[13]
        imem_mem[9]  = inst_store(5'd5, 5'd0, 13'd112);    // dmem[14] = r5

        imem_mem[10] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(20);

        check_dmem("LOAD/STORE offset 0", 10, 64'h1111_2222_3333_4444);
        check_dmem("LOAD/STORE offset +8", 11, 64'h5555_6666_7777_8888);
        check_dmem("LOAD/STORE offset +16", 12, 64'h9999_AAAA_BBBB_CCCC);
        check_dmem("LOAD/STORE base pointer r4", 13, 64'h1111_2222_3333_4444);
        check_dmem("LOAD/STORE reload consistency", 14, 64'h1111_2222_3333_4444);
    endtask

    // --- 1.11 MOV Tests ---
    task automatic test_tier1_mov();
        $display("\n--- [Tier 1.11] MOV Instruction Verification (5 Tests) ---");
        clear_mem();
        dmem_big[0] = 64'd12345;               dmem_lit[0] = 64'd12345;
        dmem_big[1] = -64'd98765;              dmem_lit[1] = -64'd98765;
        dmem_big[2] = 64'hA5A5_5A5A_A5A5_5A5A; dmem_lit[2] = 64'hA5A5_5A5A_A5A5_5A5A;

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 12345
        imem_mem[1]  = inst_mov(5'd2, 5'd1);               // r2 = r1
        imem_mem[2]  = inst_store(5'd2, 5'd0, 13'd80);     // dmem[10]

        imem_mem[3]  = inst_load(5'd3, 5'd0, 13'd8);       // r3 = -98765
        imem_mem[4]  = inst_mov(5'd4, 5'd3);               // r4 = r3
        imem_mem[5]  = inst_store(5'd4, 5'd0, 13'd88);     // dmem[11]

        imem_mem[6]  = inst_load(5'd5, 5'd0, 13'd16);      // r5 = 0xA5A5...
        imem_mem[7]  = inst_mov(5'd6, 5'd5);               // r6 = r5
        imem_mem[8]  = inst_store(5'd6, 5'd0, 13'd96);     // dmem[12]

        imem_mem[9]  = inst_mov(5'd7, 5'd0);               // r7 = r0 = 0
        imem_mem[10] = inst_store(5'd7, 5'd0, 13'd104);    // dmem[13]

        // Cascaded move: r1 -> r8 -> r9 -> r10
        imem_mem[11] = inst_mov(5'd8, 5'd1);               // r8 = r1
        imem_mem[12] = inst_mov(5'd9, 5'd8);               // r9 = r8
        imem_mem[13] = inst_mov(5'd10, 5'd9);              // r10 = r9
        imem_mem[14] = inst_store(5'd10, 5'd0, 13'd112);   // dmem[14]
        imem_mem[15] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(25);

        check_dmem("MOV positive integer", 10, 64'd12345);
        check_dmem("MOV negative integer", 11, -64'd98765);
        check_dmem("MOV full-width bit pattern", 12, 64'hA5A5_5A5A_A5A5_5A5A);
        check_dmem("MOV zero from r0", 13, 64'd0);
        check_dmem("MOV cascaded r1->r8->r9->r10", 14, 64'd12345);
    endtask

    // --- 1.12 LDI Tests ---
    task automatic test_tier1_ldi();
        $display("\n--- [Tier 1.12] LDI Instruction Verification (5 Tests) ---");
        clear_mem();

        imem_mem[0]  = inst_ldi(5'd1, 13'd0);              // r1 = 0
        imem_mem[1]  = inst_store(5'd1, 5'd0, 13'd80);     // dmem[10] = 0

        imem_mem[2]  = inst_ldi(5'd2, 13'd42);             // r2 = 42
        imem_mem[3]  = inst_store(5'd2, 5'd0, 13'd88);     // dmem[11] = 42

        imem_mem[4]  = inst_ldi(5'd3, 13'h07FF);           // r3 = 2047 (+2047)
        imem_mem[5]  = inst_store(5'd3, 5'd0, 13'd96);     // dmem[12] = 2047

        imem_mem[6]  = inst_ldi(5'd4, 13'h1FFF);           // r4 = -1
        imem_mem[7]  = inst_store(5'd4, 5'd0, 13'd104);    // dmem[13] = -1

        imem_mem[8]  = inst_ldi(5'd5, 13'h1F9C);           // r5 = -100
        imem_mem[9]  = inst_store(5'd5, 5'd0, 13'd112);    // dmem[14] = -100
        imem_mem[10] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(20);

        check_dmem("LDI zero", 10, 64'd0);
        check_dmem("LDI small positive: 42", 11, 64'd42);
        check_dmem("LDI bit 10 set: +2047", 12, 64'd2047);
        check_dmem("LDI minus one: -1", 13, 64'hFFFF_FFFF_FFFF_FFFF);
        check_dmem("LDI negative immediate: -100", 14, -64'd100);
    endtask

    // --- 1.13 BEQ Tests ---
    task automatic test_tier1_beq();
        $display("\n--- [Tier 1.13] BEQ Instruction Verification (5 Tests) ---");
        clear_mem();

        // Subtest 1: Equal -> Branch taken, skips marker
        imem_mem[0]  = inst_ldi(5'd1, 13'd10);
        imem_mem[1]  = inst_ldi(5'd2, 13'd10);
        imem_mem[2]  = inst_beq(5'd1, 5'd2, 13'd2);         // Jump over inst 3 (+2 words = PC+8)
        imem_mem[3]  = inst_ldi(5'd3, 13'd99);              // SHOULD BE SKIPPED
        imem_mem[4]  = inst_store(5'd3, 5'd0, 13'd80);      // dmem[10] should be 0

        // Subtest 2: Not equal -> Branch not taken, executes marker
        imem_mem[5]  = inst_ldi(5'd4, 13'd10);
        imem_mem[6]  = inst_ldi(5'd5, 13'd20);
        imem_mem[7]  = inst_beq(5'd4, 5'd5, 13'd2);         // NOT TAKEN
        imem_mem[8]  = inst_ldi(5'd6, 13'd77);              // EXECUTED
        imem_mem[9]  = inst_store(5'd6, 5'd0, 13'd88);      // dmem[11] should be 77

        // Subtest 3: BEQ r0, r0 unconditional forward jump
        imem_mem[10] = inst_beq(5'd0, 5'd0, 13'd2);         // Jump over inst 11
        imem_mem[11] = inst_ldi(5'd7, 13'd88);              // SKIPPED
        imem_mem[12] = inst_ldi(5'd7, 13'd55);              // EXECUTED
        imem_mem[13] = inst_store(5'd7, 5'd0, 13'd96);      // dmem[12] should be 55

        // Subtest 4: Forward branch skipping multiple instructions
        imem_mem[14] = inst_beq(5'd1, 5'd2, 13'd4);         // Jump over 3 instructions
        imem_mem[15] = inst_ldi(5'd8, 13'd1);
        imem_mem[16] = inst_ldi(5'd8, 13'd2);
        imem_mem[17] = inst_ldi(5'd8, 13'd3);
        imem_mem[18] = inst_store(5'd8, 5'd0, 13'd104);     // dmem[13] should be 0

        // Subtest 5: Backward branch loop (decrement counter r9 from 3 to 0)
        imem_mem[19] = inst_ldi(5'd9, 13'd3);               // r9 = 3
        imem_mem[20] = inst_ldi(5'd10, 13'd1);              // r10 = 1 (step)
        // Loop head (inst 21):
        imem_mem[21] = inst_sub(5'd9, 5'd9, 5'd10);         // r9 = r9 - 1
        imem_mem[22] = inst_beq(5'd9, 5'd0, 13'd2);         // if r9 == 0 jump to done (+2)
        imem_mem[23] = inst_beq(5'd0, 5'd0, -13'd2);        // backward jump to inst 21 (-2 words)
        // Loop done (inst 24):
        imem_mem[24] = inst_store(5'd9, 5'd0, 13'd112);     // dmem[14] should be 0
        imem_mem[25] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(40);

        check_dmem("BEQ equal (taken, skip store)", 10, 64'd0);
        check_dmem("BEQ not-equal (not taken)", 11, 64'd77);
        check_dmem("BEQ r0, r0 unconditional", 12, 64'd55);
        check_dmem("BEQ forward multicycle skip", 13, 64'd0);
        check_dmem("BEQ backward loop termination", 14, 64'd0);
    endtask

    // --- 1.14 BNE Tests ---
    task automatic test_tier1_bne();
        $display("\n--- [Tier 1.14] BNE Instruction Verification (5 Tests) ---");
        clear_mem();

        // Subtest 1: Not equal -> Taken, skips marker
        imem_mem[0]  = inst_ldi(5'd1, 13'd10);
        imem_mem[1]  = inst_ldi(5'd2, 13'd20);
        imem_mem[2]  = inst_bne(5'd1, 5'd2, 13'd2);         // TAKEN: jump over inst 3
        imem_mem[3]  = inst_ldi(5'd3, 13'd99);              // SKIPPED
        imem_mem[4]  = inst_store(5'd3, 5'd0, 13'd80);      // dmem[10] should be 0

        // Subtest 2: Equal -> Not taken, executes marker
        imem_mem[5]  = inst_ldi(5'd4, 13'd10);
        imem_mem[6]  = inst_ldi(5'd5, 13'd10);
        imem_mem[7]  = inst_bne(5'd4, 5'd5, 13'd2);         // NOT TAKEN
        imem_mem[8]  = inst_ldi(5'd6, 13'd77);              // EXECUTED
        imem_mem[9]  = inst_store(5'd6, 5'd0, 13'd88);      // dmem[11] should be 77

        // Subtest 3: BNE against r0 (r1 != 0)
        imem_mem[10] = inst_bne(5'd1, 5'd0, 13'd2);         // TAKEN
        imem_mem[11] = inst_ldi(5'd7, 13'd11);              // SKIPPED
        imem_mem[12] = inst_ldi(5'd7, 13'd33);              // EXECUTED
        imem_mem[13] = inst_store(5'd7, 5'd0, 13'd96);      // dmem[12] should be 33

        // Subtest 4: Forward branch skipping error code
        imem_mem[14] = inst_bne(5'd1, 5'd2, 13'd3);         // TAKEN
        imem_mem[15] = inst_ldi(5'd8, 13'd99);              // SKIPPED
        imem_mem[16] = inst_store(5'd8, 5'd0, 13'd104);     // SKIPPED
        imem_mem[17] = inst_ldi(5'd8, 13'd123);             // EXECUTED
        imem_mem[18] = inst_store(5'd8, 5'd0, 13'd104);     // dmem[13] should be 123

        // Subtest 5: Backward loop counter using BNE
        imem_mem[19] = inst_ldi(5'd9, 13'd4);               // count = 4
        imem_mem[20] = inst_ldi(5'd10, 13'd1);              // step = 1
        imem_mem[21] = inst_ldi(5'd11, 13'd0);              // accum = 0
        // Loop head (inst 22):
        imem_mem[22] = inst_add(5'd11, 5'd11, 5'd9);        // accum += count (4+3+2+1 = 10)
        imem_mem[23] = inst_sub(5'd9, 5'd9, 5'd10);         // count -= 1
        imem_mem[24] = inst_bne(5'd9, 5'd0, -13'd2);        // if count != 0 goto loop (-2)
        imem_mem[25] = inst_store(5'd11, 5'd0, 13'd112);    // dmem[14] should be 10
        imem_mem[26] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(50);

        check_dmem("BNE not-equal (taken, skip store)", 10, 64'd0);
        check_dmem("BNE equal (not taken)", 11, 64'd77);
        check_dmem("BNE against r0 taken", 12, 64'd33);
        check_dmem("BNE forward skip", 13, 64'd123);
        check_dmem("BNE backward loop accumulator (sum=10)", 14, 64'd10);
    endtask

    // --- 1.15 & 1.16 CALL & JMP Tests ---
    task automatic test_tier1_call_jmp();
        $display("\n--- [Tier 1.15 & 1.16] CALL & JMP Verification (5 Tests) ---");
        clear_mem();

        // Subtest 1 & 2 & 4: Subroutine Call + Return via JMP r31, 0
        // Inst 0: CALL subroutine at offset +3 (inst 3 = PC 0x0C). r31 should be 0x04.
        imem_mem[0]  = inst_call(5'd0, 13'd3);              // PC -> 0x0C, r31 = 0x04
        // Inst 1 (return point from subroutine):
        imem_mem[1]  = inst_store(5'd31, 5'd0, 13'd80);     // dmem[10] = r31 (should be 0x04)
        imem_mem[2]  = inst_jmp(5'd0, 13'd4);               // JMP forward to subtest 3 (inst 6 = PC 0x18)

        // Subroutine at inst 3 (PC 0x0C):
        imem_mem[3]  = inst_ldi(5'd1, 13'd42);              // r1 = 42
        imem_mem[4]  = inst_store(5'd1, 5'd0, 13'd88);      // dmem[11] = 42
        imem_mem[5]  = inst_jmp(5'd31, 13'd0);              // Return to caller (r31 = 0x04)

        // Subtest 3: CALL with explicit link register rd = r30
        // Inst 6 (PC 0x18):
        imem_mem[6]  = inst_call(5'd30, 13'd3);             // PC -> 0x24 (inst 9), r30 = 0x1C
        // Inst 7:
        imem_mem[7]  = inst_store(5'd30, 5'd0, 13'd96);     // dmem[12] = r30 (should be 0x1C)
        imem_mem[8]  = inst_jmp(5'd0, 13'd4);               // JMP forward to subtest 5 (inst 12)

        // Subroutine 2 at inst 9 (PC 0x24):
        imem_mem[9]  = inst_ldi(5'd2, 13'd84);              // r2 = 84
        imem_mem[10] = inst_store(5'd2, 5'd0, 13'd104);    // dmem[13] = 84
        imem_mem[11] = inst_jmp(5'd30, 13'd0);             // Return via r30

        // Subtest 5: Register-indirect computed jump via general register (JMP rs1, offset)
        // Inst 12 (PC 0x30):
        imem_mem[12] = inst_ldi(5'd3, 13'd64);             // r3 = 64 (0x40)
        imem_mem[13] = inst_jmp(5'd3, 13'd0);              // Jump directly to address in r3 (0x40 = inst 16)
        imem_mem[14] = inst_ldi(5'd4, 13'd99);             // SKIPPED
        imem_mem[15] = inst_store(5'd4, 5'd0, 13'd112);    // SKIPPED

        // Target of indirect jump at inst 16 (PC 0x40):
        imem_mem[16] = inst_ldi(5'd5, 13'd77);             // EXECUTED
        imem_mem[17] = inst_store(5'd5, 5'd0, 13'd112);    // dmem[14] = 77
        imem_mem[18] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(35);

        check_dmem("CALL r31 link register (PC+4 = 0x04)", 10, 64'h0000_0000_0000_0004);
        check_dmem("Subroutine body executed (r1=42)", 11, 64'd42);
        check_dmem("CALL explicit link reg r30 (PC+4 = 0x1C)", 12, 64'h0000_0000_0000_001C);
        check_dmem("Subroutine 2 body executed (r2=84)", 13, 64'd84);
        check_dmem("JMP register-indirect computed jump", 14, 64'd77);
    endtask

    // --------------------------------------------------------------------------
    // TIER 2: Boundary & Corner Cases (>=5 Tests Per Feature)
    // --------------------------------------------------------------------------
    task automatic test_tier2_boundaries();
        $display("\n--- [Tier 2] Boundary & Corner Case Verification ---");
        clear_mem();

        // 1. Arithmetic Overflow & Extremes
        dmem_big[0] = 64'h7FFF_FFFF_FFFF_FFFF; dmem_lit[0] = 64'h7FFF_FFFF_FFFF_FFFF; // Max signed pos
        dmem_big[1] = 64'd1;                   dmem_lit[1] = 64'd1;
        dmem_big[2] = 64'hFFFF_FFFF_FFFF_FFFF; dmem_lit[2] = 64'hFFFF_FFFF_FFFF_FFFF; // Max unsigned
        dmem_big[3] = 64'h8000_0000_0000_0000; dmem_lit[3] = 64'h8000_0000_0000_0000; // Min signed neg

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 0x7FFF...
        imem_mem[1]  = inst_load(5'd2, 5'd0, 13'd8);       // r2 = 1
        imem_mem[2]  = inst_add(5'd3, 5'd1, 5'd2);         // r3 = 0x8000... (signed overflow)
        imem_mem[3]  = inst_store(5'd3, 5'd0, 13'd80);     // dmem[10] = 0x8000_0000_0000_0000

        imem_mem[4]  = inst_load(5'd4, 5'd0, 13'd16);      // r4 = 0xFFFF...
        imem_mem[5]  = inst_add(5'd5, 5'd4, 5'd2);         // r5 = 0x0 (unsigned carry/wrap)
        imem_mem[6]  = inst_store(5'd5, 5'd0, 13'd88);     // dmem[11] = 0

        imem_mem[7]  = inst_load(5'd6, 5'd0, 13'd24);      // r6 = 0x8000...
        imem_mem[8]  = inst_sub(5'd7, 5'd6, 5'd2);         // r7 = 0x7FFF... (signed underflow)
        imem_mem[9]  = inst_store(5'd7, 5'd0, 13'd96);     // dmem[12] = 0x7FFF_FFFF_FFFF_FFFF

        imem_mem[10] = inst_sub(5'd8, 5'd0, 5'd2);         // r8 = 0 - 1 = 0xFFFF... (unsigned borrow)
        imem_mem[11] = inst_store(5'd8, 5'd0, 13'd104);    // dmem[13] = ~0

        // 2. Shift Count Masking (rs2[5:0])
        imem_mem[12] = inst_ldi(5'd9, 13'd64);             // r9 = 64 (count[5:0] == 0)
        imem_mem[13] = inst_shl(5'd10, 5'd2, 5'd9);        // r10 = 1 << 0 = 1
        imem_mem[14] = inst_store(5'd10, 5'd0, 13'd112);   // dmem[14] = 1

        imem_mem[15] = inst_ldi(5'd11, 13'd65);            // r11 = 65 (count[5:0] == 1)
        imem_mem[16] = inst_shl(5'd12, 5'd2, 5'd11);       // r12 = 1 << 1 = 2
        imem_mem[17] = inst_store(5'd12, 5'd0, 13'd120);   // dmem[15] = 2

        imem_mem[18] = inst_ldi(5'd13, 13'd67);            // r13 = 67 (count[5:0] == 3)
        imem_mem[19] = inst_shr(5'd14, 5'd6, 5'd13);       // r14 = 0x8000... >> 3 = 0x1000...
        imem_mem[20] = inst_store(5'd14, 5'd0, 13'd128);   // dmem[16] = 0x1000_0000_0000_0000

        // 3. Register r0 Hardwiring Invariant
        imem_mem[21] = inst_ldi(5'd0, 13'd123);            // Attempt LDI into r0
        imem_mem[22] = inst_store(5'd0, 5'd0, 13'd136);    // dmem[17] should be 0
        imem_mem[23] = inst_add(5'd0, 5'd1, 5'd2);         // Attempt ADD into r0
        imem_mem[24] = inst_store(5'd0, 5'd0, 13'd144);    // dmem[18] should be 0

        // 4. Immediate Sign Extension Boundaries (13-bit: [-4096, +4095])
        imem_mem[25] = inst_ldi(5'd15, 13'h0FFF);          // +4095 (max pos 13-bit)
        imem_mem[26] = inst_store(5'd15, 5'd0, 13'd152);   // dmem[19] = 0x0FFF
        imem_mem[27] = inst_ldi(5'd16, 13'h1000);          // -4096 (min neg 13-bit)
        imem_mem[28] = inst_store(5'd16, 5'd0, 13'd160);   // dmem[20] = 0xFFFF_FFFF_FFFF_F000

        imem_mem[29] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(40);

        check_dmem("ADD signed overflow: 0x7FFF... + 1", 10, 64'h8000_0000_0000_0000);
        check_dmem("ADD unsigned carry wrap: ~0 + 1", 11, 64'd0);
        check_dmem("SUB signed underflow: 0x8000... - 1", 12, 64'h7FFF_FFFF_FFFF_FFFF);
        check_dmem("SUB unsigned borrow: 0 - 1", 13, 64'hFFFF_FFFF_FFFF_FFFF);
        check_dmem("SHL count >= 64 masked: 1 << 64 = 1", 14, 64'd1);
        check_dmem("SHL count >= 64 masked: 1 << 65 = 2", 15, 64'd2);
        check_dmem("SHR count >= 64 masked: 0x8000... >> 67", 16, 64'h1000_0000_0000_0000);
        check_dmem("r0 hardwiring LDI discard", 17, 64'd0);
        check_dmem("r0 hardwiring ADD discard", 18, 64'd0);
        check_dmem("LDI sign-ext max positive (+4095)", 19, 64'h0000_0000_0000_0FFF);
        check_dmem("LDI sign-ext min negative (-4096)", 20, 64'hFFFF_FFFF_FFFF_F000);
    endtask

    // --------------------------------------------------------------------------
    // TIER 3: Cross-Feature Combinations (Pairwise Interactions)
    // --------------------------------------------------------------------------
    task automatic test_tier3_combinations();
        $display("\n--- [Tier 3] Cross-Feature Combinations Verification ---");
        clear_mem();

        // Scenario 3.1: RAW Hazard: Arithmetic -> Logic
        // r1 = 10; r2 = r1 + 5 = 15; r3 = r2 & 1 = 1 (back-to-back dependency)
        imem_mem[0]  = inst_ldi(5'd1, 13'd10);
        imem_mem[1]  = inst_ldi(5'd4, 13'd5);
        imem_mem[2]  = inst_add(5'd2, 5'd1, 5'd4);         // r2 = 15
        imem_mem[3]  = inst_ldi(5'd5, 13'd1);
        imem_mem[4]  = inst_and(5'd3, 5'd2, 5'd5);         // r3 = 15 & 1 = 1
        imem_mem[5]  = inst_store(5'd3, 5'd0, 13'd80);     // dmem[10] = 1

        // Scenario 3.2: Store -> Load RAW Memory Hazard
        // Store 0xBEEF to dmem[1], then immediately load it back
        imem_mem[6]  = inst_ldi(5'd6, 13'h0EEF);           // r6 = 0x0EEF
        imem_mem[7]  = inst_store(5'd6, 5'd0, 13'd8);      // dmem[1] = 0x0EEF
        imem_mem[8]  = inst_load(5'd7, 5'd0, 13'd8);       // r7 = dmem[1]
        imem_mem[9]  = inst_store(5'd7, 5'd0, 13'd88);     // dmem[11] = 0x0EEF

        // Scenario 3.3: Immediate -> Pointer Arithmetic -> Memory Access
        imem_mem[10] = inst_ldi(5'd8, 13'd16);             // r8 = 16
        imem_mem[11] = inst_add(5'd9, 5'd0, 5'd8);         // r9 = 16 (pointer)
        imem_mem[12] = inst_store(5'd6, 5'd9, 13'd80);     // dmem[(16+80)/8] = dmem[12] = 0x0EEF

        // Scenario 3.5: Conditional Branch Skipping Destructive Store
        imem_mem[13] = inst_ldi(5'd10, 13'd42);
        imem_mem[14] = inst_beq(5'd10, 5'd10, 13'd2);      // Skip destructive store
        imem_mem[15] = inst_store(5'd0, 5'd0, 13'd80);     // Destructive store (SKIPPED)
        imem_mem[16] = inst_ldi(5'd11, 13'd99);            // Resume
        imem_mem[17] = inst_store(5'd11, 5'd0, 13'd104);   // dmem[13] = 99

        // Scenario 3.6: Shift and Logic Pipeline: SHL -> OR -> SHR -> XOR
        // r12 = 1; r12 = (1 << 8) | 0xFF = 0x01FF; r12 = (0x01FF >> 4) ^ 0x000F = 0x001F ^ 0x000F = 0x0010 = 16
        imem_mem[18] = inst_ldi(5'd12, 13'd1);
        imem_mem[19] = inst_ldi(5'd13, 13'd8);
        imem_mem[20] = inst_shl(5'd12, 5'd12, 5'd13);      // r12 = 0x0100
        imem_mem[21] = inst_ldi(5'd14, 13'h00FF);
        imem_mem[22] = inst_or(5'd12, 5'd12, 5'd14);       // r12 = 0x01FF
        imem_mem[23] = inst_ldi(5'd15, 13'd4);
        imem_mem[24] = inst_shr(5'd12, 5'd12, 5'd15);      // r12 = 0x001F
        imem_mem[25] = inst_ldi(5'd16, 13'h000F);
        imem_mem[26] = inst_xor(5'd12, 5'd12, 5'd16);      // r12 = 0x0010 = 16
        imem_mem[27] = inst_store(5'd12, 5'd0, 13'd112);   // dmem[14] = 16

        imem_mem[28] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(40);

        check_dmem("Scenario 3.1: RAW Arith->Logic hazard", 10, 64'd1);
        check_dmem("Scenario 3.2: Store->Load RAW memory hazard", 11, 64'h0EEF);
        check_dmem("Scenario 3.3: Pointer arithmetic store", 12, 64'h0EEF);
        check_dmem("Scenario 3.5: Branch skips destructive store", 13, 64'd99);
        check_dmem("Scenario 3.6: Shift/Logic pipeline", 14, 64'd16);
    endtask

    // --------------------------------------------------------------------------
    // TIER 4: Real-World Application Scenarios
    // --------------------------------------------------------------------------

    // --- Scenario 4.1: Iterative Fibonacci Sequence ---
    task automatic test_tier4_fibonacci();
        $display("\n--- [Tier 4.1] Real-World Scenario: Fibonacci Sequence Generation ---");
        clear_mem();

        // Computes 8 terms: F(0)=0, F(1)=1, F(2)=1, F(3)=2, F(4)=3, F(5)=5, F(6)=8, F(7)=13
        // Stored sequentially in dmem[0..7]
        imem_mem[0]  = inst_ldi(5'd1, 13'd0);              // r1: F(n-2) = 0
        imem_mem[1]  = inst_ldi(5'd2, 13'd1);              // r2: F(n-1) = 1
        imem_mem[2]  = inst_ldi(5'd3, 13'd6);              // r3: loop count = 6 remaining
        imem_mem[3]  = inst_ldi(5'd4, 13'd0);              // r4: pointer offset = 0
        imem_mem[4]  = inst_ldi(5'd5, 13'd8);              // r5: stride = 8 bytes
        imem_mem[5]  = inst_ldi(5'd6, 13'd1);              // r6: step = 1

        imem_mem[6]  = inst_store(5'd1, 5'd4, 13'd0);      // dmem[0] = F(0) = 0
        imem_mem[7]  = inst_add(5'd4, 5'd4, 5'd5);         // offset += 8
        imem_mem[8]  = inst_store(5'd2, 5'd4, 13'd0);      // dmem[1] = F(1) = 1
        imem_mem[9]  = inst_add(5'd4, 5'd4, 5'd5);         // offset += 8

        // Loop Head (inst 10):
        imem_mem[10] = inst_add(5'd7, 5'd1, 5'd2);         // r7: F(n) = F(n-2) + F(n-1)
        imem_mem[11] = inst_store(5'd7, 5'd4, 13'd0);      // store F(n)
        imem_mem[12] = inst_add(5'd4, 5'd4, 5'd5);         // offset += 8
        imem_mem[13] = inst_mov(5'd1, 5'd2);               // F(n-2) = F(n-1)
        imem_mem[14] = inst_mov(5'd2, 5'd7);               // F(n-1) = F(n)
        imem_mem[15] = inst_sub(5'd3, 5'd3, 5'd6);         // count -= 1
        imem_mem[16] = inst_bne(5'd3, 5'd0, -13'd6);       // if count != 0 goto inst 10 (-6 words)

        imem_mem[17] = inst_beq(5'd0, 5'd0, 13'd0);        // halt

        reset_cores();
        step_cycles(60);

        check_dmem("Fibonacci F(0)", 0, 64'd0);
        check_dmem("Fibonacci F(1)", 1, 64'd1);
        check_dmem("Fibonacci F(2)", 2, 64'd1);
        check_dmem("Fibonacci F(3)", 3, 64'd2);
        check_dmem("Fibonacci F(4)", 4, 64'd3);
        check_dmem("Fibonacci F(5)", 5, 64'd5);
        check_dmem("Fibonacci F(6)", 6, 64'd8);
        check_dmem("Fibonacci F(7)", 7, 64'd13);
    endtask

    // --- Scenario 4.2: Subroutine Triangular Sum / Loop ---
    task automatic test_tier4_subroutine_loop();
        $display("\n--- [Tier 4.2] Real-World Scenario: Subroutine Triangular Accumulator ---");
        clear_mem();

        // Main calls subroutine triangular_sum(N=10) = 1 + 2 + ... + 10 = 55
        // Main program:
        imem_mem[0]  = inst_ldi(5'd1, 13'd10);             // r1: argument N = 10
        imem_mem[1]  = inst_call(5'd0, 13'd3);             // Call subroutine at inst 4 (PC 0x10)
        imem_mem[2]  = inst_store(5'd2, 5'd0, 13'd80);     // dmem[10] = return value r2 (55)
        imem_mem[3]  = inst_beq(5'd0, 5'd0, 13'd0);        // halt

        // Subroutine triangular_sum at inst 4 (PC 0x10):
        imem_mem[4]  = inst_ldi(5'd2, 13'd0);              // r2: sum = 0
        imem_mem[5]  = inst_ldi(5'd3, 13'd1);              // r3: step = 1
        // Loop head (inst 6):
        imem_mem[6]  = inst_add(5'd2, 5'd2, 5'd1);         // sum += N
        imem_mem[7]  = inst_sub(5'd1, 5'd1, 5'd3);         // N -= 1
        imem_mem[8]  = inst_bne(5'd1, 5'd0, -13'd2);       // if N != 0 goto inst 6 (-2 words)
        imem_mem[9]  = inst_jmp(5'd31, 13'd0);             // Return to caller via r31

        reset_cores();
        step_cycles(50);

        check_dmem("Subroutine triangular sum(10) = 55", 10, 64'd55);
    endtask

    // --- Scenario 4.3: Memory Block Copy & Checksum ---
    task automatic test_tier4_memcpy_checksum();
        $display("\n--- [Tier 4.3] Real-World Scenario: Block Copy & Checksum ---");
        clear_mem();

        // Source buffer at dmem[0..3]
        dmem_big[0] = 64'hAAAA_1111_2222_3333; dmem_lit[0] = 64'hAAAA_1111_2222_3333;
        dmem_big[1] = 64'hBBBB_4444_5555_6666; dmem_lit[1] = 64'hBBBB_4444_5555_6666;
        dmem_big[2] = 64'hCCCC_7777_8888_9999; dmem_lit[2] = 64'hCCCC_7777_8888_9999;
        dmem_big[3] = 64'hDDDD_AAAA_BBBB_CCCC; dmem_lit[3] = 64'hDDDD_AAAA_BBBB_CCCC;

        // Copy 4 elements from 0 to destination offset 64 (dmem[8..11]) and compute XOR checksum in r5
        imem_mem[0]  = inst_ldi(5'd1, 13'd4);              // count = 4
        imem_mem[1]  = inst_ldi(5'd2, 13'd0);              // src_ptr = 0
        imem_mem[2]  = inst_ldi(5'd3, 13'd64);             // dst_ptr = 64
        imem_mem[3]  = inst_ldi(5'd4, 13'd8);              // stride = 8
        imem_mem[4]  = inst_ldi(5'd5, 13'd0);              // checksum = 0
        imem_mem[5]  = inst_ldi(5'd6, 13'd1);              // step = 1

        // Loop head (inst 6):
        imem_mem[6]  = inst_load(5'd7, 5'd2, 13'd0);       // r7 = *src_ptr
        imem_mem[7]  = inst_store(5'd7, 5'd3, 13'd0);      // *dst_ptr = r7
        imem_mem[8]  = inst_xor(5'd5, 5'd5, 5'd7);         // checksum ^= r7
        imem_mem[9]  = inst_add(5'd2, 5'd2, 5'd4);         // src_ptr += 8
        imem_mem[10] = inst_add(5'd3, 5'd3, 5'd4);         // dst_ptr += 8
        imem_mem[11] = inst_sub(5'd1, 5'd1, 5'd6);         // count -= 1
        imem_mem[12] = inst_bne(5'd1, 5'd0, -13'd6);       // loop to inst 6

        imem_mem[13] = inst_store(5'd5, 5'd0, 13'd128);    // dmem[16] = checksum
        imem_mem[14] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        step_cycles(50);

        check_dmem("Memcpy copied word 0", 8,  64'hAAAA_1111_2222_3333);
        check_dmem("Memcpy copied word 1", 9,  64'hBBBB_4444_5555_6666);
        check_dmem("Memcpy copied word 2", 10, 64'hCCCC_7777_8888_9999);
        check_dmem("Memcpy copied word 3", 11, 64'hDDDD_AAAA_BBBB_CCCC);
        check_dmem("Memcpy XOR checksum", 16,
                   64'hAAAA_1111_2222_3333 ^ 64'hBBBB_4444_5555_6666 ^
                   64'hCCCC_7777_8888_9999 ^ 64'hDDDD_AAAA_BBBB_CCCC);
    endtask

    // --- Scenario 4.4: Nested Function Calls with Simulated Stack ---
    task automatic test_tier4_nested_calls();
        $display("\n--- [Tier 4.4] Real-World Scenario: Nested Subroutine Calls & Stack Frame ---");
        clear_mem();

        // Main calls func_outer, func_outer calls func_inner
        // Stack pointer in r29, initialized to 0x100 (dmem[32])
        imem_mem[0]  = inst_ldi(5'd29, 13'd256);           // sp = 256
        imem_mem[1]  = inst_call(5'd0, 13'd3);             // call func_outer (inst 4)
        imem_mem[2]  = inst_store(5'd1, 5'd0, 13'd80);     // dmem[10] = final result r1 (100)
        imem_mem[3]  = inst_beq(5'd0, 5'd0, 13'd0);        // halt

        // func_outer (inst 4 = PC 0x10):
        imem_mem[4]  = inst_store(5'd31, 5'd29, 13'd0);    // push r31 to stack
        imem_mem[5]  = inst_call(5'd0, 13'd4);             // call func_inner (inst 9 = PC 0x24)
        // returned from func_inner:
        imem_mem[6]  = inst_add(5'd1, 5'd1, 5'd1);         // r1 = 50 + 50 = 100
        imem_mem[7]  = inst_load(5'd31, 5'd29, 13'd0);     // pop r31 from stack
        imem_mem[8]  = inst_jmp(5'd31, 13'd0);             // return to main

        // func_inner (inst 9 = PC 0x24):
        imem_mem[9]  = inst_ldi(5'd1, 13'd50);             // r1 = 50
        imem_mem[10] = inst_jmp(5'd31, 13'd0);             // return to func_outer

        reset_cores();
        step_cycles(30);

        check_dmem("Nested calls result (r1=100)", 10, 64'd100);
    endtask

    // --------------------------------------------------------------------------
    // Main Verification Process
    // --------------------------------------------------------------------------
    initial begin
        $display("================================================================================");
        $display("          Starting S-256 Dual-Core (big_core & little_core) E2E Testsuite       ");
        $display("================================================================================");

        // Tier 1 Tests
        test_tier1_add();
        test_tier1_sub();
        test_tier1_shl();
        test_tier1_shr();
        test_tier1_and();
        test_tier1_or();
        test_tier1_xor();
        test_tier1_not();
        test_tier1_load_store();
        test_tier1_mov();
        test_tier1_ldi();
        test_tier1_beq();
        test_tier1_bne();
        test_tier1_call_jmp();

        // Tier 2 Tests
        test_tier2_boundaries();

        // Tier 3 Tests
        test_tier3_combinations();

        // Tier 4 Tests
        test_tier4_fibonacci();
        test_tier4_subroutine_loop();
        test_tier4_memcpy_checksum();
        test_tier4_nested_calls();

        // Parity Verification Check
        $display("\n--- Dual-Core Lockstep Parity Summary ---");
        check_value("Dual-Core Parity Errors", parity_err_count, 0);

        // Final Verification Verdict
        $display("\n================================================================================");
        $display("                      S-256 CORE VERIFICATION SUITE COMPLETE                     ");
        $display("================================================================================");
        $display(" TOTAL CHECKS PASSED : %0d", pass_count);
        $display(" TOTAL CHECKS FAILED : %0d", fail_count);
        $display(" PARITY ERRORS       : %0d", parity_err_count);
        $display("================================================================================");

        if (fail_count == 0 && parity_err_count == 0) begin
            $display(" TEST PASSED: All 16 Instructions, Boundaries, Hazards & Scenarios Verified!");
            $display("================================================================================\n");
            $finish(0);
        end else begin
            $display(" *** TEST FAILED with %0d errors! ***", fail_count);
            $display("================================================================================\n");
            $fatal(1, "*** SIMULATION FAILED: Architectural or Parity Violations Detected ***");
        end
    end

endmodule
