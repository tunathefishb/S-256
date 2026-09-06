`timescale 1ns/1ps

// ==============================================================================
// S-256 Dual-Core Adversarial Stress Testbench (tb/core_adversarial_tb.sv)
//
// Adversarial test battery challenging:
//   1. r0 write immunity across all write-capable instructions (ADD, SUB, AND,
//      OR, XOR, NOT, SHL, SHR, MOV, LDI, LOAD)
//   2. Extreme 64-bit arithmetic boundaries (overflow, underflow, wraps)
//   3. Shift amount masking (shamt = 64, 65, 96, 127, 128, 255, ~0)
//   4. Deep back-to-back RAW register dependency chains (30-cycle self-accum, 15-reg cascade)
//   5. Consecutive RAW memory hazards (STORE immediately followed by LOAD)
//   6. 100-iteration stress loop (triangular sum 1..100 = 5050)
//   7. Deep nested function calls (depth 8 stack push/pop and JMP r31 unwind)
//   8. Alternating conditional branches (BEQ/BNE taken vs fallthrough sequence)
//   9. Continuous cycle-by-cycle dual-core lockstep parity verification
// ==============================================================================

import soc_pkg::*;

module core_adversarial_tb;

    // Clock and Reset Signals
    logic clk;
    logic rst_ni;

    // big_core Memory Bus Interface
    logic [63:0] imem_addr_big;
    logic [31:0] imem_rdata_big;
    logic [63:0] dmem_addr_big;
    logic [63:0] dmem_wdata_big;
    logic [7:0]  dmem_wstrb_big;
    logic        dmem_wen_big;
    logic        dmem_ren_big;
    logic [63:0] dmem_rdata_big;

    // little_core Memory Bus Interface
    logic [63:0] imem_addr_lit;
    logic [31:0] imem_rdata_lit;
    logic [63:0] dmem_addr_lit;
    logic [63:0] dmem_wdata_lit;
    logic [7:0]  dmem_wstrb_lit;
    logic        dmem_wen_lit;
    logic        dmem_ren_lit;
    logic [63:0] dmem_rdata_lit;

    // Harvard Memory Models: 64 KB imem, 64 KB dmem per core
    logic [31:0] imem_mem [0:16383];
    logic [63:0] dmem_big [0:8191];
    logic [63:0] dmem_lit [0:8191];

    assign imem_rdata_big = (imem_addr_big < 64'h10000) ? imem_mem[imem_addr_big[15:2]] : 32'h0;
    assign imem_rdata_lit = (imem_addr_lit < 64'h10000) ? imem_mem[imem_addr_lit[15:2]] : 32'h0;

    assign dmem_rdata_big = (dmem_addr_big < 64'h10000) ? dmem_big[dmem_addr_big[15:3]] : 64'h0;
    assign dmem_rdata_lit = (dmem_addr_lit < 64'h10000) ? dmem_lit[dmem_addr_lit[15:3]] : 64'h0;

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

    // DUT Instantiations
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

    int pass_count       = 0;
    int fail_count       = 0;
    int check_id         = 0;
    int parity_err_count = 0;

    // Clock Generation (100 MHz, 10 ns)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Continuous Dual-Core Parity Verification (Checked across ALL cycles, including reset)
    always @(posedge clk) begin
        if (imem_addr_big !== imem_addr_lit) begin
            $display("  [FAIL] PARITY ERROR: imem_addr mismatch Big=0x%016h, Lit=0x%016h at %0t (rst_ni=%b)",
                     imem_addr_big, imem_addr_lit, $time, rst_ni);
            fail_count++;
            parity_err_count++;
        end
        if (dmem_wen_big !== dmem_wen_lit) begin
            $display("  [FAIL] PARITY ERROR: dmem_wen mismatch Big=%b, Lit=%b at %0t (rst_ni=%b)",
                     dmem_wen_big, dmem_wen_lit, $time, rst_ni);
            fail_count++;
            parity_err_count++;
        end
        if (dmem_ren_big !== dmem_ren_lit) begin
            $display("  [FAIL] PARITY ERROR: dmem_ren mismatch Big=%b, Lit=%b at %0t (rst_ni=%b)",
                     dmem_ren_big, dmem_ren_lit, $time, rst_ni);
            fail_count++;
            parity_err_count++;
        end
        if (dmem_wen_big && (dmem_addr_big !== dmem_addr_lit || dmem_wdata_big !== dmem_wdata_lit)) begin
            $display("  [FAIL] PARITY ERROR: dmem write mismatch Big=[0x%016h]=0x%016h, Lit=[0x%016h]=0x%016h at %0t (rst_ni=%b)",
                     dmem_addr_big, dmem_wdata_big, dmem_addr_lit, dmem_wdata_lit, $time, rst_ni);
            fail_count++;
            parity_err_count++;
        end
    end

    // Instruction Encoders
    function automatic logic [31:0] enc(input logic [3:0] op, input logic [4:0] d, input logic [4:0] s1, input logic [4:0] s2, input logic [12:0] imm);
        return {op, d, s1, s2, imm};
    endfunction

    function automatic logic [31:0] inst_add(input logic [4:0] d, input logic [4:0] s1, input logic [4:0] s2);
        return enc(OP_ADD, d, s1, s2, 13'd0);
    endfunction
    function automatic logic [31:0] inst_sub(input logic [4:0] d, input logic [4:0] s1, input logic [4:0] s2);
        return enc(OP_SUB, d, s1, s2, 13'd0);
    endfunction
    function automatic logic [31:0] inst_shl(input logic [4:0] d, input logic [4:0] s1, input logic [4:0] s2);
        return enc(OP_SHL, d, s1, s2, 13'd0);
    endfunction
    function automatic logic [31:0] inst_shr(input logic [4:0] d, input logic [4:0] s1, input logic [4:0] s2);
        return enc(OP_SHR, d, s1, s2, 13'd0);
    endfunction
    function automatic logic [31:0] inst_and(input logic [4:0] d, input logic [4:0] s1, input logic [4:0] s2);
        return enc(OP_AND, d, s1, s2, 13'd0);
    endfunction
    function automatic logic [31:0] inst_or(input logic [4:0] d, input logic [4:0] s1, input logic [4:0] s2);
        return enc(OP_OR, d, s1, s2, 13'd0);
    endfunction
    function automatic logic [31:0] inst_xor(input logic [4:0] d, input logic [4:0] s1, input logic [4:0] s2);
        return enc(OP_XOR, d, s1, s2, 13'd0);
    endfunction
    function automatic logic [31:0] inst_not(input logic [4:0] d, input logic [4:0] s1);
        return enc(OP_NOT, d, s1, 5'd0, 13'd0);
    endfunction
    function automatic logic [31:0] inst_load(input logic [4:0] d, input logic [4:0] s1, input logic [12:0] imm);
        return enc(OP_LOAD, d, s1, 5'd0, imm);
    endfunction
    function automatic logic [31:0] inst_store(input logic [4:0] s2, input logic [4:0] s1, input logic [12:0] imm);
        return enc(OP_STORE, 5'd0, s1, s2, imm);
    endfunction
    function automatic logic [31:0] inst_mov(input logic [4:0] d, input logic [4:0] s1);
        return enc(OP_MOV, d, s1, 5'd0, 13'd0);
    endfunction
    function automatic logic [31:0] inst_ldi(input logic [4:0] d, input logic [12:0] imm);
        return enc(OP_LDI, d, 5'd0, 5'd0, imm);
    endfunction
    function automatic logic [31:0] inst_beq(input logic [4:0] s1, input logic [4:0] s2, input logic [12:0] imm);
        return enc(OP_BEQ, 5'd0, s1, s2, imm);
    endfunction
    function automatic logic [31:0] inst_bne(input logic [4:0] s1, input logic [4:0] s2, input logic [12:0] imm);
        return enc(OP_BNE, 5'd0, s1, s2, imm);
    endfunction
    function automatic logic [31:0] inst_call(input logic [4:0] d, input logic [12:0] imm);
        return enc(OP_CALL, d, 5'd0, 5'd0, imm);
    endfunction
    function automatic logic [31:0] inst_jmp(input logic [4:0] s1, input logic [12:0] imm);
        return enc(OP_JMP, 5'd0, s1, 5'd0, imm);
    endfunction

    // Test Harness Control
    task automatic reset_cores();
        rst_ni = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_ni = 1'b1;
        @(posedge clk);
    endtask

    task automatic clear_mem();
        integer m;
        for (m = 0; m < 16384; m = m + 1) imem_mem[m] = 32'h0;
        for (m = 0; m < 8192; m = m + 1) begin
            dmem_big[m] = 64'h0;
            dmem_lit[m] = 64'h0;
        end
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

    // =========================================================================
    // 1. Adversarial Test: Complete r0 Write Immunity Across All Instructions
    // =========================================================================
    task automatic test_adv_r0_immunity();
        $display("\n--- [ADV 1] Register r0 Write Immunity Across ALL Instructions ---");
        clear_mem();
        dmem_big[0] = 64'hDEAD_BEEF_CAFE_BABE;
        dmem_lit[0] = 64'hDEAD_BEEF_CAFE_BABE;

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 0xDEAD_BEEF_CAFE_BABE
        imem_mem[1]  = inst_ldi(5'd2, 13'd7);              // r2 = 7
        // Attempt writes to r0 via all instructions:
        imem_mem[2]  = inst_ldi(5'd0, 13'h1FFF);           // LDI into r0 (-1)
        imem_mem[3]  = inst_store(5'd0, 5'd0, 13'd80);     // dmem[10] = r0 (expect 0)

        imem_mem[4]  = inst_add(5'd0, 5'd1, 5'd2);         // ADD into r0
        imem_mem[5]  = inst_store(5'd0, 5'd0, 13'd88);     // dmem[11] = r0 (expect 0)

        imem_mem[6]  = inst_sub(5'd0, 5'd1, 5'd2);         // SUB into r0
        imem_mem[7]  = inst_store(5'd0, 5'd0, 13'd96);     // dmem[12] = r0 (expect 0)

        imem_mem[8]  = inst_and(5'd0, 5'd1, 5'd1);         // AND into r0
        imem_mem[9]  = inst_store(5'd0, 5'd0, 13'd104);    // dmem[13] = r0 (expect 0)

        imem_mem[10] = inst_or(5'd0, 5'd1, 5'd2);          // OR into r0
        imem_mem[11] = inst_store(5'd0, 5'd0, 13'd112);    // dmem[14] = r0 (expect 0)

        imem_mem[12] = inst_xor(5'd0, 5'd1, 5'd2);         // XOR into r0
        imem_mem[13] = inst_store(5'd0, 5'd0, 13'd120);    // dmem[15] = r0 (expect 0)

        imem_mem[14] = inst_not(5'd0, 5'd1);               // NOT into r0
        imem_mem[15] = inst_store(5'd0, 5'd0, 13'd128);    // dmem[16] = r0 (expect 0)

        imem_mem[16] = inst_shl(5'd0, 5'd1, 5'd2);         // SHL into r0
        imem_mem[17] = inst_store(5'd0, 5'd0, 13'd136);    // dmem[17] = r0 (expect 0)

        imem_mem[18] = inst_shr(5'd0, 5'd1, 5'd2);         // SHR into r0
        imem_mem[19] = inst_store(5'd0, 5'd0, 13'd144);    // dmem[18] = r0 (expect 0)

        imem_mem[20] = inst_mov(5'd0, 5'd1);               // MOV into r0
        imem_mem[21] = inst_store(5'd0, 5'd0, 13'd152);    // dmem[19] = r0 (expect 0)

        imem_mem[22] = inst_load(5'd0, 5'd0, 13'd0);       // LOAD into r0
        imem_mem[23] = inst_store(5'd0, 5'd0, 13'd160);    // dmem[20] = r0 (expect 0)

        imem_mem[24] = inst_beq(5'd0, 5'd0, 13'd0);        // halt

        reset_cores();
        repeat (35) @(posedge clk);

        check_dmem("r0 immunity: LDI discard", 10, 64'd0);
        check_dmem("r0 immunity: ADD discard", 11, 64'd0);
        check_dmem("r0 immunity: SUB discard", 12, 64'd0);
        check_dmem("r0 immunity: AND discard", 13, 64'd0);
        check_dmem("r0 immunity: OR discard",  14, 64'd0);
        check_dmem("r0 immunity: XOR discard", 15, 64'd0);
        check_dmem("r0 immunity: NOT discard", 16, 64'd0);
        check_dmem("r0 immunity: SHL discard", 17, 64'd0);
        check_dmem("r0 immunity: SHR discard", 18, 64'd0);
        check_dmem("r0 immunity: MOV discard", 19, 64'd0);
        check_dmem("r0 immunity: LOAD discard",20, 64'd0);
    endtask

    // =========================================================================
    // 2. Adversarial Test: Extreme Shift Count Masking (shamt >= 64)
    // =========================================================================
    task automatic test_adv_shift_masking();
        $display("\n--- [ADV 2] Extreme Shift Count Masking (>= 64) ---");
        clear_mem();
        // Operands: r1 = 0x8000_0000_0000_0001
        dmem_big[0] = 64'h8000_0000_0000_0001;
        dmem_lit[0] = 64'h8000_0000_0000_0001;

        imem_mem[0]  = inst_load(5'd1, 5'd0, 13'd0);       // r1 = 0x8000...0001
        imem_mem[1]  = inst_ldi(5'd2, 13'd64);             // r2 = 64  (64 % 64 = 0)
        imem_mem[2]  = inst_ldi(5'd3, 13'd65);             // r3 = 65  (65 % 64 = 1)
        imem_mem[3]  = inst_ldi(5'd4, 13'd96);             // r4 = 96  (96 % 64 = 32)
        imem_mem[4]  = inst_ldi(5'd5, 13'd127);            // r5 = 127 (127 % 64 = 63)
        imem_mem[5]  = inst_ldi(5'd6, 13'd128);            // r6 = 128 (128 % 64 = 0)
        imem_mem[6]  = inst_ldi(5'd7, 13'd255);            // r7 = 255 (255 % 64 = 63)
        imem_mem[7]  = inst_ldi(5'd8, -13'd1);             // r8 = -1  (64'hFFFF...FFFF % 64 = 63)

        // SHL tests
        imem_mem[8]  = inst_shl(5'd10, 5'd1, 5'd2);        // r1 << 0
        imem_mem[9]  = inst_store(5'd10, 5'd0, 13'd80);    // dmem[10] = r1
        imem_mem[10] = inst_shl(5'd11, 5'd1, 5'd3);        // r1 << 1
        imem_mem[11] = inst_store(5'd11, 5'd0, 13'd88);    // dmem[11] = 0x0000_0000_0000_0002
        imem_mem[12] = inst_shl(5'd12, 5'd1, 5'd4);        // r1 << 32
        imem_mem[13] = inst_store(5'd12, 5'd0, 13'd96);    // dmem[12] = 0x0000_0001_0000_0000
        imem_mem[14] = inst_shl(5'd13, 5'd1, 5'd5);        // r1 << 63
        imem_mem[15] = inst_store(5'd13, 5'd0, 13'd104);   // dmem[13] = 0x8000_0000_0000_0000

        // SHR tests
        imem_mem[16] = inst_shr(5'd14, 5'd1, 5'd6);        // r1 >> 0
        imem_mem[17] = inst_store(5'd14, 5'd0, 13'd112);   // dmem[14] = r1
        imem_mem[18] = inst_shr(5'd15, 5'd1, 5'd7);        // r1 >> 63
        imem_mem[19] = inst_store(5'd15, 5'd0, 13'd120);   // dmem[15] = 1
        imem_mem[20] = inst_shr(5'd16, 5'd1, 5'd8);        // r1 >> (~0 % 64 = 63)
        imem_mem[21] = inst_store(5'd16, 5'd0, 13'd128);   // dmem[16] = 1

        imem_mem[22] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        repeat (35) @(posedge clk);

        check_dmem("SHL count 64 (mask to 0)", 10, 64'h8000_0000_0000_0001);
        check_dmem("SHL count 65 (mask to 1)", 11, 64'h0000_0000_0000_0002);
        check_dmem("SHL count 96 (mask to 32)", 12, 64'h0000_0001_0000_0000);
        check_dmem("SHL count 127 (mask to 63)", 13, 64'h8000_0000_0000_0000);
        check_dmem("SHR count 128 (mask to 0)", 14, 64'h8000_0000_0000_0001);
        check_dmem("SHR count 255 (mask to 63)", 15, 64'd1);
        check_dmem("SHR count ~0 (mask to 63)", 16, 64'd1);
    endtask

    // =========================================================================
    // 3. Adversarial Test: Deep RAW Register Dependency Chains
    // =========================================================================
    task automatic test_adv_raw_dependency_chains();
        $display("\n--- [ADV 3] Deep RAW Register Dependency Chains (30 Back-to-Back Cycles) ---");
        clear_mem();

        // 3.1 Self-Accumulation: r1 = 1, then r1 = r1 + r1 repeated 30 times (r1 = 2^30)
        imem_mem[0] = inst_ldi(5'd1, 13'd1);
        for (int i = 1; i <= 30; i++) begin
            imem_mem[i] = inst_add(5'd1, 5'd1, 5'd1);
        end
        imem_mem[31] = inst_store(5'd1, 5'd0, 13'd80);     // dmem[10] = 2^30 = 0x4000_0000

        // 3.2 Cascading Registers across 15 registers:
        // r2 = 10; r3 = r2 + 1; r4 = r3 + 1; ... r16 = r15 + 1 (r16 = 10 + 14 = 24)
        imem_mem[32] = inst_ldi(5'd2, 13'd10);
        imem_mem[33] = inst_ldi(5'd30, 13'd1); // increment constant
        for (int r = 3; r <= 16; r++) begin
            logic [4:0] curr_r = 5'(r);
            logic [4:0] prev_r = 5'(r - 1);
            imem_mem[34 + (r - 3)] = inst_add(curr_r, prev_r, 5'd30);
        end
        imem_mem[48] = inst_store(5'd16, 5'd0, 13'd88);    // dmem[11] = 24
        imem_mem[49] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        repeat (65) @(posedge clk);

        check_dmem("RAW 30-cycle self-accumulation (r1 = 2^30)", 10, 64'h0000_0000_4000_0000);
        check_dmem("RAW 14-register cascade (r16 = 10 + 14 = 24)", 11, 64'd24);
    endtask

    // =========================================================================
    // 4. Adversarial Test: Consecutive RAW Memory Hazards (Store -> Immediate Load)
    // =========================================================================
    task automatic test_adv_raw_memory_hazards();
        $display("\n--- [ADV 4] Consecutive Store -> Load Memory Hazards ---");
        clear_mem();

        // Repeated Store -> Load on identical address with varying patterns
        // Pattern 1:
        imem_mem[0]  = inst_ldi(5'd1, 13'h0ABC);
        imem_mem[1]  = inst_store(5'd1, 5'd0, 13'd0);      // dmem[0] = 0x0ABC
        imem_mem[2]  = inst_load(5'd2, 5'd0, 13'd0);       // r2 = dmem[0] (immediate load next cycle)
        imem_mem[3]  = inst_store(5'd2, 5'd0, 13'd80);     // dmem[10] = r2

        // Pattern 2: Overwriting same location and immediate load
        imem_mem[4]  = inst_ldi(5'd3, -13'd50);            // r3 = -50
        imem_mem[5]  = inst_store(5'd3, 5'd0, 13'd0);      // dmem[0] = -50
        imem_mem[6]  = inst_load(5'd4, 5'd0, 13'd0);       // r4 = dmem[0]
        imem_mem[7]  = inst_store(5'd4, 5'd0, 13'd88);     // dmem[11] = -50

        // Pattern 3: Back-to-back adjacent word stores and loads
        imem_mem[8]  = inst_ldi(5'd5, 13'd111);
        imem_mem[9]  = inst_ldi(5'd6, 13'd222);
        imem_mem[10] = inst_store(5'd5, 5'd0, 13'd8);      // dmem[1] = 111
        imem_mem[11] = inst_store(5'd6, 5'd0, 13'd16);     // dmem[2] = 222
        imem_mem[12] = inst_load(5'd7, 5'd0, 13'd8);       // r7 = dmem[1]
        imem_mem[13] = inst_load(5'd8, 5'd0, 13'd16);      // r8 = dmem[2]
        imem_mem[14] = inst_store(5'd7, 5'd0, 13'd96);     // dmem[12] = 111
        imem_mem[15] = inst_store(5'd8, 5'd0, 13'd104);    // dmem[13] = 222

        imem_mem[16] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        repeat (30) @(posedge clk);

        check_dmem("RAW mem hazard 1: immediate load after store", 10, 64'h0000_0000_0000_0ABC);
        check_dmem("RAW mem hazard 2: load after overwrite", 11, -64'sd50);
        check_dmem("RAW mem hazard 3: adjacent load 1", 12, 64'd111);
        check_dmem("RAW mem hazard 4: adjacent load 2", 13, 64'd222);
    endtask

    // =========================================================================
    // 5. Adversarial Test: 100-Iteration Loop Stress (Sum 1..100 = 5050)
    // =========================================================================
    task automatic test_adv_100_iteration_loop();
        $display("\n--- [ADV 5] 100-Iteration Loop Stress (Sum 1..100 = 5050) ---");
        clear_mem();

        // r1 = 100 (counter)
        // r2 = 0 (sum)
        // r3 = 1 (decrement)
        imem_mem[0] = inst_ldi(5'd1, 13'd100);
        imem_mem[1] = inst_ldi(5'd2, 13'd0);
        imem_mem[2] = inst_ldi(5'd3, 13'd1);

        // Loop body (inst 3):
        imem_mem[3] = inst_add(5'd2, 5'd2, 5'd1);         // sum += counter
        imem_mem[4] = inst_sub(5'd1, 5'd1, 5'd3);         // counter -= 1
        imem_mem[5] = inst_bne(5'd1, 5'd0, -13'd2);       // if counter != 0 goto inst 3 (-2 words)

        // Loop exit: store result
        imem_mem[6] = inst_store(5'd2, 5'd0, 13'd80);     // dmem[10] = 5050
        imem_mem[7] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        // 100 iterations * 3 instructions + setup/exit = ~310 cycles
        repeat (320) @(posedge clk);

        check_dmem("100-iteration loop sum(1..100) = 5050", 10, 64'd5050);
    endtask

    // =========================================================================
    // 6. Adversarial Test: Deep Nested Function Calls (Depth 8 Call/Ret)
    // =========================================================================
    task automatic test_adv_nested_calls_depth8();
        $display("\n--- [ADV 6] Deep Nested Subroutine Calls & Stack Unwind (Depth 8) ---");
        clear_mem();

        // Stack pointer r29 initialized to 0x400 (dmem[128])
        // Each function fn pushes r31 to [r29], calls fn+1, pops r31, adds n to r1, and returns via JMP r31.
        // Total accumulated in r1 = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 = 36.

        // Main (inst 0):
        imem_mem[0]  = inst_ldi(5'd29, 13'd1024);         // sp = 1024
        imem_mem[1]  = inst_ldi(5'd1,  13'd0);            // accum r1 = 0
        imem_mem[2]  = inst_ldi(5'd28, 13'd8);            // stack frame size = 8 bytes
        imem_mem[3]  = inst_call(5'd0, 13'd3);            // CALL f1 (inst 6 = PC 0x18)
        imem_mem[4]  = inst_store(5'd1, 5'd0, 13'd80);    // dmem[10] = r1 (should be 36)
        imem_mem[5]  = inst_beq(5'd0, 5'd0, 13'd0);       // halt

        // Subroutine generator helper for f1..f7:
        // inst_base:
        // [0] sub sp, sp, 8
        // [1] store r31, sp, 0
        // [2] call next_f
        // [3] load r31, sp, 0
        // [4] add sp, sp, 8
        // [5] ldi r2, n
        // [6] add r1, r1, r2
        // [7] jmp r31, 0
        for (int depth = 1; depth <= 7; depth++) begin
            int base = 6 + (depth - 1) * 8;
            imem_mem[base + 0] = inst_sub(5'd29, 5'd29, 5'd28);    // sp -= 8
            imem_mem[base + 1] = inst_store(5'd31, 5'd29, 13'd0);  // push r31
            imem_mem[base + 2] = inst_call(5'd0, 13'd6);           // call next_f (base + 8)
            imem_mem[base + 3] = inst_load(5'd31, 5'd29, 13'd0);   // pop r31
            imem_mem[base + 4] = inst_add(5'd29, 5'd29, 5'd28);    // sp += 8
            imem_mem[base + 5] = inst_ldi(5'd2, 13'(depth));      // r2 = depth
            imem_mem[base + 6] = inst_add(5'd1, 5'd1, 5'd2);       // r1 += depth
            imem_mem[base + 7] = inst_jmp(5'd31, 13'd0);           // return
        end

        // Leaf function f8 at inst 62 (base = 6 + 7*8 = 62):
        imem_mem[62] = inst_ldi(5'd2, 13'd8);             // r2 = 8
        imem_mem[63] = inst_add(5'd1, 5'd1, 5'd2);        // r1 += 8
        imem_mem[64] = inst_jmp(5'd31, 13'd0);            // leaf return to f7

        reset_cores();
        repeat (120) @(posedge clk);

        check_dmem("Nested calls depth 8 result (sum 1..8 = 36)", 10, 64'd36);
    endtask

    // =========================================================================
    // 7. Adversarial Test: Alternating Conditional Branches Stress
    // =========================================================================
    task automatic test_adv_alternating_branches();
        $display("\n--- [ADV 7] Alternating Conditional Branches (BEQ/BNE) Stress ---");
        clear_mem();

        imem_mem[0]  = inst_ldi(5'd1, 13'd10);
        imem_mem[1]  = inst_ldi(5'd2, 13'd10);
        imem_mem[2]  = inst_ldi(5'd3, 13'd20);
        imem_mem[3]  = inst_ldi(5'd4, 13'd0);             // accum flag = 0

        // 1. BEQ taken: r1 == r2 -> skip trap store
        imem_mem[4]  = inst_beq(5'd1, 5'd2, 13'd2);
        imem_mem[5]  = inst_ldi(5'd4, 13'd999);           // TRAP (should be skipped)
        // Resume at inst 6:
        imem_mem[6]  = inst_ldi(5'd5, 13'd1);
        imem_mem[7]  = inst_add(5'd4, 5'd4, 5'd5);         // accum += 1 (accum = 1)

        // 2. BEQ not taken: r1 == r3 (10 == 20 false) -> fall through
        imem_mem[8]  = inst_beq(5'd1, 5'd3, 13'd2);       // NOT taken
        imem_mem[9]  = inst_add(5'd4, 5'd4, 5'd5);         // EXECUTED: accum += 1 (accum = 2)

        // 3. BNE taken: r1 != r3 (10 != 20 true) -> skip trap
        imem_mem[10] = inst_bne(5'd1, 5'd3, 13'd2);
        imem_mem[11] = inst_ldi(5'd4, 13'd888);           // TRAP (should be skipped)
        // Resume at inst 12:
        imem_mem[12] = inst_add(5'd4, 5'd4, 5'd5);         // accum += 1 (accum = 3)

        // 4. BNE not taken: r1 != r2 (10 != 10 false) -> fall through
        imem_mem[13] = inst_bne(5'd1, 5'd2, 13'd2);       // NOT taken
        imem_mem[14] = inst_add(5'd4, 5'd4, 5'd5);         // EXECUTED: accum += 1 (accum = 4)

        imem_mem[15] = inst_store(5'd4, 5'd0, 13'd80);    // dmem[10] = 4
        imem_mem[16] = inst_beq(5'd0, 5'd0, 13'd0);

        reset_cores();
        repeat (30) @(posedge clk);

        check_dmem("Alternating BEQ/BNE sequence result (accum = 4)", 10, 64'd4);
    endtask

    // =========================================================================
    // 8. Adversarial Test: Reset Memory Isolation & Bus Quiescence Invariant
    // =========================================================================
    task automatic test_adv_reset_memory_isolation();
        $display("\n--- [ADV 8] Reset Memory Isolation & Bus Quiescence Invariant ---");
        clear_mem();

        // Place a STORE instruction at imem_mem[0] attempting to write to dmem[0]
        // If the core does NOT gate dmem_wen with rst_ni, clock edges during reset
        // will write 0 to dmem[0], destroying its contents.
        dmem_big[0] = 64'hCAFE_BABE_1234_5678;
        dmem_lit[0] = 64'hCAFE_BABE_1234_5678;

        imem_mem[0] = inst_store(5'd1, 5'd0, 13'd0); // Mem[0] = r1 (r1 is 0 during reset)
        imem_mem[1] = inst_load(5'd2, 5'd0, 13'd0);
        imem_mem[2] = inst_beq(5'd0, 5'd0, 13'd0);

        // Assert reset
        rst_ni = 1'b0;
        for (int c = 0; c < 5; c++) begin
            @(posedge clk); #1;
            // Verify bus signals during reset
            check_id++;
            if (dmem_wen_big === 1'b0 && dmem_wen_lit === 1'b0 &&
                dmem_ren_big === 1'b0 && dmem_ren_lit === 1'b0 &&
                dmem_wstrb_big === 8'h00 && dmem_wstrb_lit === 8'h00) begin
                $display("  [PASS #%0d] Reset cycle %0d: dmem control signals strictly deasserted (wen=0, ren=0, wstrb=0)", check_id, c);
                pass_count++;
            end else begin
                $display("  [FAIL #%0d] Reset cycle %0d: bus signals active during reset! Big: wen=%b, ren=%b, wstrb=%h; Lit: wen=%b, ren=%b, wstrb=%h",
                         check_id, c, dmem_wen_big, dmem_ren_big, dmem_wstrb_big, dmem_wen_lit, dmem_ren_lit, dmem_wstrb_lit);
                fail_count++;
            end
        end

        // Release reset
        @(negedge clk);
        rst_ni = 1'b1;
        @(posedge clk);

        // Verify dmem[0] remained untouched during the entire reset sequence
        check_dmem("Reset memory isolation (dmem[0] untouched during reset)", 0, 64'hCAFE_BABE_1234_5678);

        // Disarm imem[0] before releasing reset so subsequent tests start with clean bus state
        imem_mem[0] = inst_beq(5'd0, 5'd0, 13'd0);
        @(negedge clk);
        rst_ni = 1'b1;
        repeat (2) @(posedge clk);
    endtask

    // =========================================================================
    // 9. Adversarial Test: 64-bit Memory Address Overflow / Wrap
    // =========================================================================
    task automatic test_adv_memory_addr_wrap();
        $display("\n--- [ADV 9] 64-bit Memory Address Overflow / Wrap-Around ---");
        clear_mem();

        // Base register r1 = -8 (64'hFFFF_FFFF_FFFF_FFF8)
        // Immediate displacement = +16 (13'd16)
        // Effective address: 64'hFFFF_FFFF_FFFF_FFF8 + 16 = 64'd8 (dmem[1])
        dmem_big[0] = 64'hFFFF_FFFF_FFFF_FFF8;
        dmem_lit[0] = 64'hFFFF_FFFF_FFFF_FFF8;

        imem_mem[0] = inst_load(5'd1, 5'd0, 13'd0);        // r1 = 64'hFFFF_FFFF_FFFF_FFF8
        imem_mem[1] = inst_ldi(5'd2, 13'h0777);            // r2 = 0x0777
        imem_mem[2] = inst_store(5'd2, 5'd1, 13'd16);      // STORE to (r1 + 16 = byte 8 = dmem[1])
        imem_mem[3] = inst_load(5'd3, 5'd1, 13'd16);       // LOAD from (r1 + 16 = byte 8 = dmem[1])
        imem_mem[4] = inst_store(5'd3, 5'd0, 13'd80);      // dmem[10] = r3 (should be 0x0777)
        imem_mem[5] = inst_beq(5'd0, 5'd0, 13'd0);         // halt

        reset_cores();
        repeat (20) @(posedge clk);

        check_dmem("Memory address 64-bit wrap STORE target (dmem[1])", 1, 64'h0000_0000_0000_0777);
        check_dmem("Memory address 64-bit wrap LOAD reload (dmem[10])", 10, 64'h0000_0000_0000_0777);
    endtask

    // =========================================================================
    // Main Verification Process
    // =========================================================================
    initial begin
        $display("================================================================================");
        $display("       Starting S-256 Dual-Core ADVERSARIAL & STRESS Verification Suite         ");
        $display("================================================================================");

        test_adv_r0_immunity();
        test_adv_shift_masking();
        test_adv_raw_dependency_chains();
        test_adv_raw_memory_hazards();
        test_adv_100_iteration_loop();
        test_adv_nested_calls_depth8();
        test_adv_alternating_branches();
        test_adv_reset_memory_isolation();
        test_adv_memory_addr_wrap();

        $display("\n--- Dual-Core Adversarial Lockstep Parity Summary ---");
        check_id++;
        if (parity_err_count == 0) begin
            $display("  [PASS #%0d] Zero lockstep parity divergences across all stress tests!", check_id);
            pass_count++;
        end else begin
            $display("  [FAIL #%0d] Parity errors detected: %0d", check_id, parity_err_count);
            fail_count++;
        end

        $display("\n================================================================================");
        $display("                 S-256 ADVERSARIAL STRESS SUITE COMPLETE                        ");
        $display("================================================================================");
        $display(" TOTAL CHECKS PASSED : %0d", pass_count);
        $display(" TOTAL CHECKS FAILED : %0d", fail_count);
        $display(" PARITY ERRORS       : %0d", parity_err_count);
        $display("================================================================================");

        if (fail_count == 0 && parity_err_count == 0) begin
            $display(" ALL ADVERSARIAL & STRESS TESTS PASSED WITH 100%% INTEGRITY!\n");
            $finish(0);
        end else begin
            $display(" *** ADVERSARIAL TESTS DETECTED FAILURES! ***\n");
            $fatal(1, "*** Simulation failed: Adversarial or Parity failure ***");
        end
    end

endmodule
