// 2-stage pipelined RISC-V processor for A4
//
// Pipeline stages (per course material):
//   Stage 1: IF + ID + EXE
//   Stage 2: MEM + WB
//
// This file keeps the same top-level I/O and internal arrays (mainMemory/registers)
// so the provided testbench can still preload memory and probe registers.
//
// Optional forwarding is supported via parameter FORWARDING.
//   FORWARDING = 0 : rely on software hazard avoidance (NOPs / scheduling)
//   FORWARDING = 1 : simple bypass from Stage 2 WB data -> Stage 1 operands

module processor #(
    WIDTH = 32,
    NUM_REGS = 32,
    DATA_WIDTH = 8,
    MEM_DEPTH = 2048,
    FORWARDING = 0
)(
    input  logic              clock, reset, memEn,
    input  logic [WIDTH-1:0]   memData,
    input  logic [WIDTH-1:0]   memAddr,
    output logic [WIDTH-1:0]   gp, a7, a0
);

    // Unified instruction/data memory (byte-addressable)
    logic [DATA_WIDTH-1:0] mainMemory [0:MEM_DEPTH-1];

    // Integer register file
    logic [WIDTH-1:0] registers [0:NUM_REGS-1];

    // -------------------------
    // Stage 1 (IF/ID/EXE) nets
    // -------------------------
    logic [WIDTH-1:0] pc;
    logic [WIDTH-1:0] ins_s1;
    logic [WIDTH-1:0] imm_s1;
    logic [WIDTH-1:0] data_1_s1, data_2_s1;
    logic [WIDTH-1:0] op1_s1, op2_s1;       // after optional forwarding
    logic [WIDTH-1:0] src1_s1, src2_s1;
    logic [WIDTH-1:0] aluOut_s1;
    logic [WIDTH-1:0] wb_pre_mem_s1;
    logic [WIDTH-1:0] memWrite_s1;

    logic [3:0] aluOp_s1;
    logic [4:0] rs1_s1, rs2_s1, rd_s1, opcode_s1;
    logic [2:0] funct3_s1;
    logic [6:0] funct7_s1;

    logic isArithmetic_s1, isImm_s1, isMemRead_s1, isLoadUI_s1, isMemWrite_s1;
    logic isBranch_s1, isJAL_s1, isJALR_s1, isMUL_s1, isAUIPC_s1;
    logic isBranchR_s1, isBranchC_s1;
    logic regWriteEn_s1;

    // -------------------------
    // Stage 2 (MEM/WB) pipeline registers
    // -------------------------
    logic [4:0]        rd_s2;
    logic [2:0]        funct3_s2;
    logic              regWriteEn_s2;
    logic              isMemRead_s2;
    logic              isMemWrite_s2;
    logic [WIDTH-1:0]  aluOut_s2;
    logic [WIDTH-1:0]  wb_pre_mem_s2;
    logic [WIDTH-1:0]  memWrite_s2;

    // Stage 2 combinational read + WB mux
    logic [WIDTH-1:0] memRead_s2;
    logic [WIDTH-1:0] wb_final_s2;

    // -------------------------
    // Program-loader write port (used by testbench)
    // -------------------------
    always_ff @(posedge clock) begin
        mainMemory[memAddr[13:0]] <= (memEn) ? memData[7:0] : mainMemory[memAddr[13:0]];
    end

    // -------------------------
    // Stage 1: instruction fetch
    // -------------------------
    assign ins_s1 = (~memEn) ? {mainMemory[pc+3], mainMemory[pc+2], mainMemory[pc+1], mainMemory[pc]} : 32'h00000013;

    // -------------------------
    // Stage 1: decode + immediate generation
    // -------------------------
    always_comb begin
        {funct7_s1, rs2_s1, rs1_s1, funct3_s1, rd_s1, opcode_s1} = ins_s1[31:2];

        isArithmetic_s1 = (opcode_s1 == 5'b01100) & (funct7_s1[0] == 1'b0);
        isMUL_s1        = (opcode_s1 == 5'b01100) & (funct7_s1[0] == 1'b1); // MUL/DIV
        isImm_s1        = (opcode_s1 == 5'b00100);
        isMemRead_s1    = (opcode_s1 == 5'b00000);
        isLoadUI_s1     = (opcode_s1 == 5'b01101);
        isMemWrite_s1   = (opcode_s1 == 5'b01000);
        isBranch_s1     = (opcode_s1 == 5'b11000);
        isJAL_s1        = (opcode_s1 == 5'b11011);
        isJALR_s1       = (opcode_s1 == 5'b11001);
        isAUIPC_s1      = (opcode_s1 == 5'b00101);

        // immediate generation
        if      (isImm_s1 | isMemRead_s1 | isJALR_s1) imm_s1 = WIDTH'($signed(ins_s1[31:20]));                                   // I-imm
        else if (isLoadUI_s1 | isAUIPC_s1)            imm_s1 = {ins_s1[31:12], 12'b0};                                            // U-imm
        else if (isMemWrite_s1)                       imm_s1 = WIDTH'($signed({ins_s1[31:25], ins_s1[11:7]}));                    // S-imm
        else if (isBranch_s1)                         imm_s1 = WIDTH'($signed({ins_s1[31], ins_s1[7], ins_s1[30:25], ins_s1[11:8], 1'b0})); // B-imm
        else if (isJAL_s1)                            imm_s1 = WIDTH'($signed({ins_s1[31], ins_s1[19:12], ins_s1[20], ins_s1[30:21], 1'b0})); // J-imm
        else                                          imm_s1 = 0;
    end

    // Stage 1: register reads (combinational)
    assign data_1_s1 = (rs1_s1 == 0) ? 0 : registers[rs1_s1];
    assign data_2_s1 = (rs2_s1 == 0) ? 0 : registers[rs2_s1];

    // -------------------------
    // Stage 2: data memory read (combinational)
    // -------------------------
    always_comb begin
        case (funct3_s2[1:0])
            2'b00: memRead_s2 = (!funct3_s2[2]) ? ({{24{mainMemory[aluOut_s2][7]}}, mainMemory[aluOut_s2]}) :
                                                  ({24'b0, mainMemory[aluOut_s2]});
            2'b01: memRead_s2 = (!funct3_s2[2]) ? ({{16{mainMemory[aluOut_s2+1][7]}}, {mainMemory[aluOut_s2+1], mainMemory[aluOut_s2]}}) :
                                                  ({16'b0, {mainMemory[aluOut_s2+1], mainMemory[aluOut_s2]}});
            2'b10: memRead_s2 = {mainMemory[aluOut_s2+3], mainMemory[aluOut_s2+2], mainMemory[aluOut_s2+1], mainMemory[aluOut_s2]};
            default: memRead_s2 = 32'b0;
        endcase
    end

    // Stage 2: WB mux
    assign wb_final_s2 = isMemRead_s2 ? memRead_s2 : wb_pre_mem_s2;

    // -------------------------
    // Stage 1 optional forwarding (Stage2 -> Stage1)
    // -------------------------
    always_comb begin
        op1_s1 = data_1_s1;
        op2_s1 = data_2_s1;

        if (FORWARDING) begin
            if (regWriteEn_s2 && (rd_s2 != 0) && (rd_s2 == rs1_s1))
                op1_s1 = wb_final_s2;
            if (regWriteEn_s2 && (rd_s2 != 0) && (rd_s2 == rs2_s1))
                op2_s1 = wb_final_s2;
        end
    end

    // -------------------------
    // Stage 1: ALU
    // -------------------------
    localparam [3:0] ADD=0, SLL=1, SLT=2, SLTU=3, XOR=4, SRL=5, OR=6, AND=7, SUB=8, MUL=9, DIV=10, SRA=13, PASS=15;

    always_comb begin
        // ALU op select
        if      (isMUL_s1)                                                aluOp_s1 = (funct3_s1[2] ? DIV : MUL);
        else if (isArithmetic_s1)                                         aluOp_s1 = {funct7_s1[5], funct3_s1};
        else if (isImm_s1)                                                aluOp_s1 = {funct7_s1[5] & (funct3_s1==3'b101), funct3_s1};
        else if (isAUIPC_s1 | isJAL_s1 | isJALR_s1 | isBranch_s1 | isMemRead_s1 | isMemWrite_s1) aluOp_s1 = ADD;
        else                                                              aluOp_s1 = PASS;

        // operand muxes (after forwarding)
        src1_s1 = (isJAL_s1 | isBranch_s1 | isAUIPC_s1) ? pc  : op1_s1;
        src2_s1 = (isImm_s1 | isMemRead_s1 | isLoadUI_s1 | isJAL_s1 | isJALR_s1 | isMemWrite_s1 | isBranch_s1 | isAUIPC_s1) ? imm_s1 : op2_s1;

        unique case (aluOp_s1)
            ADD  : aluOut_s1 = src1_s1 + src2_s1;
            SUB  : aluOut_s1 = src1_s1 - src2_s1;
            SLL  : aluOut_s1 = src1_s1 << src2_s1[4:0];
            SLT  : aluOut_s1 = WIDTH'($signed(src1_s1) < $signed(src2_s1));
            SLTU : aluOut_s1 = WIDTH'($unsigned(src1_s1) < $unsigned(src2_s1));
            XOR  : aluOut_s1 = src1_s1 ^ src2_s1;
            SRL  : aluOut_s1 = src1_s1 >> src2_s1[4:0];
            SRA  : aluOut_s1 = $signed(src1_s1) >>> src2_s1[4:0];
            OR   : aluOut_s1 = src1_s1 | src2_s1;
            AND  : aluOut_s1 = src1_s1 & src2_s1;
            MUL  : aluOut_s1 = src1_s1 * src2_s1;
            DIV  : aluOut_s1 = ($signed(src2_s1) == 0) ? 32'hFFFFFFFF :
                               (($signed(src1_s1) == 32'h80000000 && $signed(src2_s1) == -1) ? 32'h80000000 :
                                 WIDTH'($signed(src1_s1) / $signed(src2_s1)));
            PASS : aluOut_s1 = src2_s1;
            default: aluOut_s1 = 0;
        endcase
    end

    // -------------------------
    // Stage 1: branch decision (uses forwarded operands)
    // -------------------------
    always_comb begin
        case (funct3_s1[2:1])
            2'b00: isBranchC_s1 = (funct3_s1[0]) ^ (op1_s1 == op2_s1);                    // BNE/BEQ
            2'b10: isBranchC_s1 = (funct3_s1[0]) ^ ($signed(op1_s1) < $signed(op2_s1));   // BLT/BGE
            2'b11: isBranchC_s1 = (funct3_s1[0]) ^ (op1_s1 < op2_s1);                     // BLTU/BGEU
            default: isBranchC_s1 = 1'b0;
        endcase
        isBranchR_s1 = isBranchC_s1 & isBranch_s1;
    end

    // -------------------------
    // Stage 1: store data formatting (uses forwarded rs2 value)
    // -------------------------
    always_comb begin
        case (funct3_s1)
            3'b000: memWrite_s1 = {24'b0, op2_s1[7:0]};                                      // SB
            3'b001: memWrite_s1 = {16'b0, op2_s1[15:8], op2_s1[7:0]};                        // SH
            3'b010: memWrite_s1 = {op2_s1[31:24], op2_s1[23:16], op2_s1[15:8], op2_s1[7:0]}; // SW
            default: memWrite_s1 = 32'b0;
        endcase
    end

    // Stage 1: WB pre-mem value (ALU result or PC+4 for jal/jalr)
    assign wb_pre_mem_s1 = (isJAL_s1 | isJALR_s1) ? (pc + 4) : aluOut_s1;

    // Stage 1: register write enable
    assign regWriteEn_s1 = isArithmetic_s1 | isImm_s1 | isMemRead_s1 | isLoadUI_s1 | isJAL_s1 | isJALR_s1 | isAUIPC_s1 | isMUL_s1;

    // -------------------------
    // PC update (resolved in Stage 1)
    // -------------------------
    always_ff @(posedge clock) begin
        if (reset) pc <= 0;
        else       pc <= (isJAL_s1 | isJALR_s1 | isBranchR_s1) ? aluOut_s1 : (pc + 4);
    end

    // -------------------------
    // Pipeline register (Stage 1 -> Stage 2)
    // -------------------------
    always_ff @(posedge clock) begin
        if (reset) begin
            rd_s2         <= 0;
            funct3_s2     <= 0;
            regWriteEn_s2 <= 0;
            isMemRead_s2  <= 0;
            isMemWrite_s2 <= 0;
            aluOut_s2     <= 0;
            wb_pre_mem_s2 <= 0;
            memWrite_s2   <= 0;
        end else begin
            rd_s2         <= rd_s1;
            funct3_s2     <= funct3_s1;
            regWriteEn_s2 <= regWriteEn_s1;
            isMemRead_s2  <= isMemRead_s1;
            isMemWrite_s2 <= isMemWrite_s1;
            aluOut_s2     <= aluOut_s1;
            wb_pre_mem_s2 <= wb_pre_mem_s1;
            memWrite_s2   <= memWrite_s1;
        end
    end

    // -------------------------
    // Stage 2: data memory write
    // -------------------------
    always_ff @(posedge clock) begin
        if (isMemWrite_s2) begin
            case (funct3_s2)
                3'b000: mainMemory[aluOut_s2] <= memWrite_s2[7:0];
                3'b001: begin
                    mainMemory[aluOut_s2]   <= memWrite_s2[7:0];
                    mainMemory[aluOut_s2+1] <= memWrite_s2[15:8];
                end
                3'b010: begin
                    mainMemory[aluOut_s2]   <= memWrite_s2[7:0];
                    mainMemory[aluOut_s2+1] <= memWrite_s2[15:8];
                    mainMemory[aluOut_s2+2] <= memWrite_s2[23:16];
                    mainMemory[aluOut_s2+3] <= memWrite_s2[31:24];
                end
                default: ;
            endcase
        end
    end

    // -------------------------
    // Stage 2: register writeback
    // -------------------------
    always_ff @(posedge clock) begin
        if (regWriteEn_s2 && rd_s2 != 5'd0)
            registers[rd_s2] <= wb_final_s2;
    end

    // Verification outputs
    assign {gp, a7, a0} = {registers[3], registers[17], registers[10]};

endmodule
