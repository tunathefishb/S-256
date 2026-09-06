`timescale 1ns/1ps

module test_m1_tb;
    import soc_pkg::*;

    int errors;

    initial begin
        errors = 0;

        $display("================================================================================");
        $display("                      MILESTONE 1 VERIFICATION TESTBENCH                        ");
        $display("================================================================================");

        // 1. Architecture Parameters
        if (XLEN != 64) begin
            $display("[FAIL] XLEN expected 64, got %0d", XLEN);
            errors++;
        end else begin
            $display("[PASS] XLEN == 64");
        end

        if (ILEN != 32) begin
            $display("[FAIL] ILEN expected 32, got %0d", ILEN);
            errors++;
        end else begin
            $display("[PASS] ILEN == 32");
        end

        if (NUM_GPR != 32) begin
            $display("[FAIL] NUM_GPR expected 32, got %0d", NUM_GPR);
            errors++;
        end else begin
            $display("[PASS] NUM_GPR == 32");
        end

        if (REG_ADDR_WIDTH != 5) begin
            $display("[FAIL] REG_ADDR_WIDTH expected 5, got %0d", REG_ADDR_WIDTH);
            errors++;
        end else begin
            $display("[PASS] REG_ADDR_WIDTH == 5");
        end

        if (IMM_WIDTH != 13) begin
            $display("[FAIL] IMM_WIDTH expected 13, got %0d", IMM_WIDTH);
            errors++;
        end else begin
            $display("[PASS] IMM_WIDTH == 13");
        end

        if (LINK_REG != 5'd31) begin
            $display("[FAIL] LINK_REG expected 31, got %0d", LINK_REG);
            errors++;
        end else begin
            $display("[PASS] LINK_REG == 31");
        end

        // 2. Opcode Groups
        if (OP_GROUP_ARITH !== 2'b00) begin
            $display("[FAIL] OP_GROUP_ARITH expected 2'b00, got %b", OP_GROUP_ARITH);
            errors++;
        end else begin
            $display("[PASS] OP_GROUP_ARITH == 2'b00");
        end

        if (OP_GROUP_LOGIC !== 2'b01) begin
            $display("[FAIL] OP_GROUP_LOGIC expected 2'b01, got %b", OP_GROUP_LOGIC);
            errors++;
        end else begin
            $display("[PASS] OP_GROUP_LOGIC == 2'b01");
        end

        if (OP_GROUP_MEM !== 2'b10) begin
            $display("[FAIL] OP_GROUP_MEM expected 2'b10, got %b", OP_GROUP_MEM);
            errors++;
        end else begin
            $display("[PASS] OP_GROUP_MEM == 2'b10");
        end

        if (OP_GROUP_CTRL !== 2'b11) begin
            $display("[FAIL] OP_GROUP_CTRL expected 2'b11, got %b", OP_GROUP_CTRL);
            errors++;
        end else begin
            $display("[PASS] OP_GROUP_CTRL == 2'b11");
        end

        // 3. 16 Opcodes (both raw and OP_ aliases)
        if (ADD !== 4'b0000 || OP_ADD !== 4'b0000) begin
            $display("[FAIL] ADD/OP_ADD expected 4'b0000"); errors++;
        end else $display("[PASS] ADD / OP_ADD == 4'b0000");

        if (SUB !== 4'b0001 || OP_SUB !== 4'b0001) begin
            $display("[FAIL] SUB/OP_SUB expected 4'b0001"); errors++;
        end else $display("[PASS] SUB / OP_SUB == 4'b0001");

        if (SHL !== 4'b0010 || OP_SHL !== 4'b0010) begin
            $display("[FAIL] SHL/OP_SHL expected 4'b0010"); errors++;
        end else $display("[PASS] SHL / OP_SHL == 4'b0010");

        if (SHR !== 4'b0011 || OP_SHR !== 4'b0011) begin
            $display("[FAIL] SHR/OP_SHR expected 4'b0011"); errors++;
        end else $display("[PASS] SHR / OP_SHR == 4'b0011");

        if (AND !== 4'b0100 || OP_AND !== 4'b0100) begin
            $display("[FAIL] AND/OP_AND expected 4'b0100"); errors++;
        end else $display("[PASS] AND / OP_AND == 4'b0100");

        if (OR !== 4'b0101 || OP_OR !== 4'b0101) begin
            $display("[FAIL] OR/OP_OR expected 4'b0101"); errors++;
        end else $display("[PASS] OR / OP_OR == 4'b0101");

        if (XOR !== 4'b0110 || OP_XOR !== 4'b0110) begin
            $display("[FAIL] XOR/OP_XOR expected 4'b0110"); errors++;
        end else $display("[PASS] XOR / OP_XOR == 4'b0110");

        if (NOT !== 4'b0111 || OP_NOT !== 4'b0111) begin
            $display("[FAIL] NOT/OP_NOT expected 4'b0111"); errors++;
        end else $display("[PASS] NOT / OP_NOT == 4'b0111");

        if (LOAD !== 4'b1000 || OP_LOAD !== 4'b1000) begin
            $display("[FAIL] LOAD/OP_LOAD expected 4'b1000"); errors++;
        end else $display("[PASS] LOAD / OP_LOAD == 4'b1000");

        if (STORE !== 4'b1001 || OP_STORE !== 4'b1001) begin
            $display("[FAIL] STORE/OP_STORE expected 4'b1001"); errors++;
        end else $display("[PASS] STORE / OP_STORE == 4'b1001");

        if (MOV !== 4'b1010 || OP_MOV !== 4'b1010) begin
            $display("[FAIL] MOV/OP_MOV expected 4'b1010"); errors++;
        end else $display("[PASS] MOV / OP_MOV == 4'b1010");

        if (LDI !== 4'b1011 || OP_LDI !== 4'b1011) begin
            $display("[FAIL] LDI/OP_LDI expected 4'b1011"); errors++;
        end else $display("[PASS] LDI / OP_LDI == 4'b1011");

        if (BEQ !== 4'b1100 || OP_BEQ !== 4'b1100) begin
            $display("[FAIL] BEQ/OP_BEQ expected 4'b1100"); errors++;
        end else $display("[PASS] BEQ / OP_BEQ == 4'b1100");

        if (BNE !== 4'b1101 || OP_BNE !== 4'b1101) begin
            $display("[FAIL] BNE/OP_BNE expected 4'b1101"); errors++;
        end else $display("[PASS] BNE / OP_BNE == 4'b1101");

        if (CALL !== 4'b1110 || OP_CALL !== 4'b1110) begin
            $display("[FAIL] CALL/OP_CALL expected 4'b1110"); errors++;
        end else $display("[PASS] CALL / OP_CALL == 4'b1110");

        if (JMP !== 4'b1111 || OP_JMP !== 4'b1111) begin
            $display("[FAIL] JMP/OP_JMP expected 4'b1111"); errors++;
        end else $display("[PASS] JMP / OP_JMP == 4'b1111");

        // 4. inst_t structure layout and bit-slicing verification
        begin
            inst_t inst;
            inst = 32'h0;

            if ($bits(inst) != 32) begin
                $display("[FAIL] $bits(inst_t) expected 32, got %0d", $bits(inst));
                errors++;
            end else begin
                $display("[PASS] $bits(inst_t) == 32");
            end

            // Assign individual fields
            inst.opcode = 4'hA;     // [31:28]
            inst.rd     = 5'h15;    // [27:23]
            inst.rs1    = 5'h0A;    // [22:18]
            inst.rs2    = 5'h1F;    // [17:13]
            inst.imm13  = 13'h1555; // [12:0]

            // Verify raw packed bit positions
            // 4'hA  = 1010
            // 5'h15 = 10101
            // 5'h0A = 01010
            // 5'h1F = 11111
            // 13'h1555 = 1_0101_0101_0101
            // Total: 1010_1010_1010_1011_1111_0101_0101_0101 = 0xAAABF555
            if (inst !== 32'hAAABF555) begin
                $display("[FAIL] inst_t packed value expected 32'hAAABF555, got 32'h%08X", inst);
                errors++;
            end else begin
                $display("[PASS] inst_t packed bitfield alignment exactly verified (0xAAABF555)");
            end

            // Verify slices
            if (inst[31:28] !== 4'hA) begin
                $display("[FAIL] inst[31:28] opcode mismatch"); errors++;
            end
            if (inst[27:23] !== 5'h15) begin
                $display("[FAIL] inst[27:23] rd mismatch"); errors++;
            end
            if (inst[22:18] !== 5'h0A) begin
                $display("[FAIL] inst[22:18] rs1 mismatch"); errors++;
            end
            if (inst[17:13] !== 5'h1F) begin
                $display("[FAIL] inst[17:13] rs2 mismatch"); errors++;
            end
            if (inst[12:0] !== 13'h1555) begin
                $display("[FAIL] inst[12:0] imm13 mismatch"); errors++;
            end
        end

        // 5. alu_flags_t structure layout verification
        begin
            alu_flags_t flags;
            flags = 4'b0000;

            if ($bits(flags) != 4) begin
                $display("[FAIL] $bits(alu_flags_t) expected 4, got %0d", $bits(flags));
                errors++;
            end else begin
                $display("[PASS] $bits(alu_flags_t) == 4");
            end

            flags.zero     = 1'b1;
            flags.negative = 1'b0;
            flags.carry    = 1'b1;
            flags.overflow = 1'b0;

            // [3]=zero, [2]=negative, [1]=carry, [0]=overflow -> 4'b1010
            if (flags !== 4'b1010) begin
                $display("[FAIL] alu_flags_t packed value expected 4'b1010, got %b", flags);
                errors++;
            end else begin
                $display("[PASS] alu_flags_t field packing verified (zero=1, neg=0, carry=1, of=0 -> 4'b1010)");
            end
        end

        // 6. CMU definition preservation check
        if (CMU_BASE_ADDR !== 32'h1000_0000 || CMU_NUM_DOMAINS !== 5) begin
            $display("[FAIL] Existing CMU definitions corrupted!");
            errors++;
        end else begin
            $display("[PASS] Existing CMU definitions perfectly preserved");
        end

        $display("================================================================================");
        if (errors == 0) begin
            $display(" *** ALL MILESTONE 1 CHECKS PASSED SUCCESSFULLY *** ");
        end else begin
            $display(" [FAIL] %0d CHECKS FAILED!", errors);
            $fatal(1);
        end
        $display("================================================================================");
        $finish;
    end

endmodule
