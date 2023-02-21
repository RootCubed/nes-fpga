`include "defs.svh"
`include "cpu6502_enums.svh"
`include "cpu6502_opcodes.svh"
`include "alu_op.svh"

// Set out_o to in_i, set the zero and negative flags
// in status_i and output the result in output_o
task assign_and_nz(
    output [7:0] out_o,
    input  [7:0] in_i,
    input  [7:0] status_i,
    output [7:0] status_o
);
    out_o = in_i;
    status_o = status_i;
    status_o[PS_ZERO] = (in_i == '0);
    status_o[PS_NEGATIVE] = in_i[7];
endtask

module cpu6502_control (
    input cpu_state_e state_i,
    output cpu_state_e state_o,

    input  logic [15:0] bus_address_i,
    output logic [15:0] bus_address_o,
    input  logic  [7:0] bus_data_i,
    output logic  [7:0] bus_data_o,
    output logic        bus_rw_o,

    input  logic [15:0] pc_i,
    output logic [15:0] pc_o,
    input  logic  [7:0] curr_opcode_i,
    output logic  [7:0] curr_opcode_o,

    input  logic [15:0] tmp_store_i,
    output logic [15:0] tmp_store_o,
    input  logic eah_invalid_i,
    output logic eah_invalid_o,

    output logic [7:0] alu_a_o,
    output logic [7:0] alu_b_o,
    output alu_op_e    alu_op_o,
    output logic       alu_carry_o,
    input  logic [7:0] alu_res_i,
    input  logic       alu_overflow_i,
    input  logic       alu_carry_i,

    input  logic [7:0] reg_a_i,
    output logic [7:0] reg_a_o,
    input  logic [7:0] reg_x_i,
    output logic [7:0] reg_x_o,
    input  logic [7:0] reg_y_i,
    output logic [7:0] reg_y_o,
    input  logic [7:0] sp_i,
    output logic [7:0] sp_o,
    input  logic [7:0] status_i,
    output logic [7:0] status_o,

    input cpu_interrupt_type_e int_type
);

assign curr_opcode_o = (state_i == CpuReadOpcode) ? bus_data_i : curr_opcode_i;
wire cpu_addrmode_e addr_mode = get_addr_mode(curr_opcode_o);
wire cpu_instr_e curr_instr = get_instr(curr_opcode_o);
wire curr_is_branch = is_branch(curr_opcode_o);
wire curr_is_rmw = is_rmw(curr_opcode_o);

cpu_state_e next_state;
assign state_o = next_state;

logic [15:0] next_pc;
assign pc_o = next_pc;

logic [7:0] alu_a_opcalc, alu_b_opcalc, alu_a_eacalc, alu_b_eacalc;
alu_op_e alu_op_opcalc, alu_op_eacalc;
logic alu_carry_opcalc, alu_carry_eacalc;

logic eah_invalid;
assign eah_invalid_o = eah_invalid;

logic [7:0] op_result;

logic branch_taken;

always_comb begin : alu_logic
    // Actual operation of instruction

    // ALU input A
    case (curr_instr)
        CpuCPX:  alu_a_opcalc = reg_x_i;
        CpuCPY:  alu_a_opcalc = reg_y_i;
        default: alu_a_opcalc = (state_i == CpuRMW1) ? tmp_store_i[7:0] : reg_a_i;
    endcase
    // ALU input B
    case (curr_instr)
        CpuINC, CpuINX, CpuINY,
        CpuDEC, CpuDEX, CpuDEY: alu_b_opcalc = 'h1;
        default: alu_b_opcalc = bus_data_i;
    endcase
    // ALU operation
    case (curr_instr)
        CpuAND, CpuBIT: alu_op_opcalc = AluOpAnd;
        CpuEOR:         alu_op_opcalc = AluOpXor;
        CpuORA:         alu_op_opcalc = AluOpOr;
        CpuADC, CpuINC, CpuINX, CpuINY:         alu_op_opcalc = AluOpAdc;
        CpuSBC, CpuCMP, CpuCPX, CpuCPY, CpuDEC: alu_op_opcalc = AluOpSbc;
        CpuASL, CpuROL: alu_op_opcalc = AluOpShiftL;
        CpuLSR, CpuROR: alu_op_opcalc = AluOpShiftR;
        default:        alu_op_opcalc = AluOpAdc;
    endcase
    // ALU carry in
    case (curr_instr)
        CpuASL, CpuLSR, CpuINC, CpuINX, CpuINY:         alu_carry_opcalc = '0;
        CpuCMP, CpuCPX, CpuCPY, CpuDEC, CpuDEX, CpuDEY: alu_carry_opcalc = '1;
        default: alu_carry_opcalc = status_i[PS_CARRY];
    endcase

    // Effective address calculations

    // ALU input A
    case (state_i)
        CpuZeroPageIdx2,
        CpuIndirectX2, CpuIndirectX3,
        CpuIndirectY2,
        CpuJmpInd1: alu_a_eacalc = bus_address_i[7:0];

        CpuAbsoluteIdx1,
        CpuIndirectY3: alu_a_eacalc = tmp_store_i[7:0];

        CpuRelativeBrTaken: alu_a_eacalc = pc_i[7:0];
        CpuRelativeFixPCH: alu_a_eacalc = pc_i[15:8];

        CpuStackPush,
        CpuStackPop1,
        CpuJsr1, CpuJsr2,
        CpuRtsRti1, CpuRti2, CpuRtsRti3,
        CpuBrk2, CpuBrk3, CpuBrk4: alu_a_eacalc = sp_i;
        default: alu_a_eacalc = '0;
    endcase
    // ALU input B
    case (state_i)
        CpuZeroPageIdx2,
        CpuAbsoluteIdx1,
        CpuIndirectX2,
        CpuIndirectY3: alu_b_eacalc = is_y_indexed(curr_opcode_i) ? reg_y_i : reg_x_i;

        CpuIndirectX3,
        CpuIndirectY2,
        CpuRelativeFixPCH,
        CpuStackPush,
        CpuStackPop1,
        CpuJmpInd1,
        CpuJsr1, CpuJsr2,
        CpuRtsRti1, CpuRti2, CpuRtsRti3,
        CpuBrk2, CpuBrk3, CpuBrk4: alu_b_eacalc = 8'h1;

        CpuRelativeBrTaken: alu_b_eacalc = tmp_store_i[7:0];
        default: alu_b_eacalc = '0;
    endcase
    // ALU operation and carry
    case (state_i)
        CpuStackPush,
        CpuJsr1, CpuJsr2,
        CpuBrk2, CpuBrk3, CpuBrk4: begin
            alu_op_eacalc = AluOpSbc;
            alu_carry_eacalc = '1;
        end

        CpuRelativeFixPCH: begin
            alu_op_eacalc = tmp_store_i[7] ? AluOpSbc : AluOpAdc;
            alu_carry_eacalc = tmp_store_i[7] ? '1 : '0;
        end

        default: begin
            alu_op_eacalc = AluOpAdc;
            alu_carry_eacalc = '0;
        end
    endcase

    // Select ALU inputs to use
    case (state_i)
        CpuZeroPageIdx2,
        CpuAbsoluteIdx1,
        CpuIndirectX2, CpuIndirectX3,
        CpuIndirectY2, CpuIndirectY3,
        CpuRelative1, CpuRelativeBrTaken, CpuRelativeFixPCH,
        CpuStackPush,
        CpuStackPop1,
        CpuJmpInd1,
        CpuJsr1, CpuJsr2,
        CpuRtsRti1, CpuRti2, CpuRtsRti3,
        CpuBrk2, CpuBrk3, CpuBrk4: begin
            alu_a_o = alu_a_eacalc;
            alu_b_o = alu_b_eacalc;
            alu_op_o = alu_op_eacalc;
            alu_carry_o = alu_carry_eacalc;
        end
        default: begin
            if (
                (state_i == CpuAbsoluteIdx2 || state_i == CpuIndirectY4) &&
                (indexed_needs_extra(curr_opcode_i) || eah_invalid_i)
            ) begin
                alu_a_o = tmp_store_i[15:8];
                alu_b_o = {7'h0, eah_invalid_i};
                alu_op_o = AluOpAdc;
                alu_carry_o = '0;
            end else begin
                alu_a_o = alu_a_opcalc;
                alu_b_o = alu_b_opcalc;
                alu_op_o = alu_op_opcalc;
                alu_carry_o = alu_carry_opcalc;
            end
        end
    endcase
end

always_comb begin : tmp_storage_logic
    case (state_i) 
        CpuZeroPage2,
        CpuZeroPageIdx3,
        CpuAbsolute1, CpuAbsolute3,
        CpuAbsoluteIdx2,
        CpuIndirectX2, CpuIndirectX3, CpuIndirectX5,
        CpuIndirectY2, CpuIndirectY5,
        CpuRelative1,
        CpuRMW1: tmp_store_o = {8'h0, bus_data_i};

        CpuAbsolute2: tmp_store_o = {bus_data_i, tmp_store_i[7:0]};
        CpuAbsoluteIdx1, CpuIndirectY3: tmp_store_o = {bus_data_i, alu_res_i};

        CpuIndirectY4: tmp_store_o = {alu_res_i, tmp_store_i[7:0]};

        default: tmp_store_o = tmp_store_i;
    endcase
end

always_comb begin : invalid_eah_logic
    if (curr_is_branch) begin
        if (state_i == CpuRelativeBrTaken) begin
            eah_invalid = alu_carry_i != tmp_store_i[7];
        end else begin
            eah_invalid = eah_invalid_i;
        end
    end else case (addr_mode)
        AddrModeABX, AddrModeABY, AddrModeINY: begin
            if (state_i == CpuAbsoluteIdx1 || state_i == CpuIndirectY3) begin
                eah_invalid = alu_carry_i;
            end else begin
                eah_invalid = eah_invalid_i;
            end
        end
        default: eah_invalid = '0;
    endcase
end

always_comb begin : pc_logic
    // Next PC
    case (state_i)
        CpuInvalid: next_pc = '0;

        CpuReadOpcode,
        CpuImmediate,
        CpuZeroPage1,
        CpuAbsolute1,
        CpuAbsoluteIdx1,
        CpuIndirectX1,
        CpuIndirectY1,
        CpuRelative1,
        CpuRts6: next_pc = pc_i + 1;

        CpuImplied,
        CpuZeroPage2,
        CpuZeroPageIdx2, CpuZeroPageIdx3,
        CpuAbsolute3, CpuAbsoluteIdx1, CpuAbsoluteIdx2, CpuAbsoluteIdx3,
        CpuIndirectX2, CpuIndirectX3, CpuIndirectX4, CpuIndirectX5,
        CpuIndirectY2, CpuIndirectY3, CpuIndirectY4, CpuIndirectY5,
        CpuRMW1, CpuRMW2,
        CpuStackPush,
        CpuStackPop1, CpuStackPop2,
        CpuJsr1, CpuJsr2, CpuJsr3,
        CpuRtsRti1, CpuRti2, CpuRtsRti5,
        CpuBrk1, CpuBrk2, CpuBrk3, CpuBrk4, CpuBrk5: next_pc = pc_i;

        CpuAbsolute2: begin
            if (curr_instr == CpuJMP) begin
                if (is_jmp_indirect(curr_opcode_i)) begin
                    next_pc = pc_i;
                end else begin
                    next_pc = {bus_data_i, tmp_store_i[7:0]};
                end
            end else if (curr_instr == CpuJSR) begin
                next_pc = pc_i;
            end else begin
                next_pc = pc_i + 1;
            end
        end

        CpuJsr4: next_pc = {bus_data_i, tmp_store_i[7:0]};

        CpuJmpInd1, CpuRtsRti3, CpuBrk6: next_pc = {pc_i[15:8], bus_data_i};
        CpuJmpInd2, CpuRtsRti4, CpuBrk7: next_pc = {bus_data_i, pc_i[7:0]};

        CpuRelativeBrTaken: next_pc = {pc_i[15:8], alu_res_i};
        CpuRelativeFixPCH: next_pc = {alu_res_i, pc_i[7:0]};

        default: $error("State %s: Unhandled case for next_pc", state_i.name());
    endcase
    
    // Branching
    branch_taken = '0;
    if (curr_is_branch && state_i == CpuRelative1) begin
        case (curr_instr)
            CpuBCC: branch_taken = status_i[PS_CARRY] == 0;
            CpuBCS: branch_taken = status_i[PS_CARRY] == 1;
            CpuBNE: branch_taken = status_i[PS_ZERO] == 0;
            CpuBEQ: branch_taken = status_i[PS_ZERO] == 1;
            CpuBPL: branch_taken = status_i[PS_NEGATIVE] == 0;
            CpuBMI: branch_taken = status_i[PS_NEGATIVE] == 1;
            CpuBVC: branch_taken = status_i[PS_OVERFLOW] == 0;
            CpuBVS: branch_taken = status_i[PS_OVERFLOW] == 1;
        endcase
        if (branch_taken) begin
            tmp_store_o = {8'h0, bus_data_i};
        end
    end
end

always_comb begin : next_state_logic
    next_state = CpuInvalid;
    case (state_i)
        CpuInvalid: next_state = CpuInvalid;
        CpuReadOpcode: begin
            case (addr_mode)
                AddrModeIMM: next_state = CpuImmediate;
                AddrModeIMP: next_state = (curr_instr == CpuRTS || curr_instr == CpuRTI) ? CpuRtsRti1 : CpuImplied;
                AddrModeZPG,
                AddrModeZPX,
                AddrModeZPY: next_state = CpuZeroPage1;
                AddrModeABS,
                AddrModeABX,
                AddrModeABY: next_state = CpuAbsolute1;
                AddrModeREL: next_state = CpuRelative1;
                AddrModeINX: next_state = CpuIndirectX1;
                AddrModeINY: next_state = CpuIndirectY1;
                default: next_state = CpuInvalid;
            endcase
        end

        CpuImmediate: next_state = CpuReadOpcode;

        CpuImplied: begin
            case (curr_instr)
                CpuPHA, CpuPHP: next_state = CpuStackPush;
                CpuPLA, CpuPLP: next_state = CpuStackPop1;
                CpuRTS, CpuRTI: next_state = CpuRtsRti1;
                default: next_state = CpuReadOpcode;
            endcase
        end

        CpuZeroPage1: next_state = (addr_mode == AddrModeZPG) ? CpuZeroPage2 : CpuZeroPageIdx2;
        CpuZeroPageIdx2: next_state = CpuZeroPageIdx3;

        CpuAbsolute1: begin
            if (addr_mode == AddrModeABX || addr_mode == AddrModeABY) begin
                next_state = CpuAbsoluteIdx1;
            end else if (curr_instr == CpuJSR) begin
                next_state = CpuJsr1;
            end else begin
                next_state = CpuAbsolute2;
            end
        end
        CpuAbsolute2: begin
            if (curr_instr == CpuJMP) begin
                next_state = is_jmp_indirect(curr_opcode_i) ? CpuJmpInd1 : CpuReadOpcode;
            end else begin
                next_state = CpuAbsolute3;
            end
        end

        CpuAbsoluteIdx1: next_state = CpuAbsoluteIdx2;
        CpuAbsoluteIdx2: next_state = (indexed_needs_extra(curr_opcode_i) || eah_invalid) ? CpuAbsoluteIdx3 : CpuReadOpcode;

        CpuIndirectX1: next_state = CpuIndirectX2;
        CpuIndirectX2: next_state = CpuIndirectX3;
        CpuIndirectX3: next_state = CpuIndirectX4;
        CpuIndirectX4: next_state = CpuIndirectX5;

        CpuIndirectY1: next_state = CpuIndirectY2;
        CpuIndirectY2: next_state = CpuIndirectY3;
        CpuIndirectY3: next_state = CpuIndirectY4;
        CpuIndirectY4: next_state = (indexed_needs_extra(curr_opcode_i) || eah_invalid) ? CpuIndirectY5 : CpuReadOpcode;

        // Final cycle of indexing
        CpuZeroPage2,
        CpuZeroPageIdx3,
        CpuAbsolute3,
        CpuAbsoluteIdx3,
        CpuIndirectX5,
        CpuIndirectY5: next_state = curr_is_rmw ? CpuRMW1 : CpuReadOpcode;
        
        CpuRMW1: next_state = CpuRMW2;
        CpuRMW2: next_state = CpuReadOpcode;

        CpuJsr1: next_state = CpuJsr2;
        CpuJsr2: next_state = CpuJsr3;
        CpuJsr3: next_state = CpuJsr4;
        CpuJsr4: next_state = CpuReadOpcode;

        CpuJmpInd1: next_state = CpuJmpInd2;
        CpuJmpInd2: next_state = CpuReadOpcode;

        CpuRelative1: next_state = (branch_taken) ? CpuRelativeBrTaken : CpuReadOpcode;
        CpuRelativeBrTaken: next_state = (eah_invalid) ? CpuRelativeFixPCH : CpuReadOpcode;
        CpuRelativeFixPCH: next_state = CpuReadOpcode;
        
        CpuStackPop1: next_state = CpuStackPop2;
        CpuStackPop2: next_state = CpuReadOpcode;

        CpuStackPush: next_state = CpuReadOpcode;

        CpuRtsRti1: next_state = (curr_instr == CpuRTS) ? CpuRtsRti3 : CpuRti2;
        CpuRti2:    next_state = CpuRtsRti3;
        CpuRtsRti3: next_state = CpuRtsRti4;
        CpuRtsRti4: next_state = CpuRtsRti5;
        CpuRtsRti5: next_state = (curr_instr == CpuRTS) ? CpuRts6 : CpuReadOpcode;
        CpuRts6:    next_state = CpuReadOpcode;
        
        CpuBrk1: next_state = CpuBrk2;
        CpuBrk2: next_state = CpuBrk3;
        CpuBrk3: next_state = CpuBrk4;
        CpuBrk4: next_state = CpuBrk5;
        CpuBrk5: next_state = CpuBrk6;
        CpuBrk6: next_state = CpuBrk7;
        CpuBrk7: next_state = CpuReadOpcode;

        default: $error("State %s: Unhandled case for next_state", state_i.name());
    endcase
end

always_comb begin : register_calc_logic
    status_o = status_i;
    case (next_state)
        CpuReadOpcode,
        CpuStackPush,
        CpuRMW2: begin
            if (state_i != CpuBrk7) begin
                case (curr_instr)
                    CpuLDA, CpuLDX, CpuLDY, CpuPLA: assign_and_nz(op_result,  bus_data_i, status_i, status_o);
                    CpuTAX, CpuTAY:                 assign_and_nz(op_result,     reg_a_i, status_i, status_o);
                    CpuTXA:                         assign_and_nz(op_result,     reg_x_i, status_i, status_o);
                    CpuTYA:                         assign_and_nz(op_result,     reg_y_i, status_i, status_o);
                    CpuTSX:                         assign_and_nz(op_result,        sp_i, status_i, status_o);
                    CpuINX:                         assign_and_nz(op_result, reg_x_i + 1, status_i, status_o);
                    CpuINY:                         assign_and_nz(op_result, reg_y_i + 1, status_i, status_o);
                    CpuDEX:                         assign_and_nz(op_result, reg_x_i - 1, status_i, status_o);
                    CpuDEY:                         assign_and_nz(op_result, reg_y_i - 1, status_i, status_o);

                    CpuADC, CpuSBC, CpuAND, CpuEOR, CpuORA, CpuINC, CpuDEC,
                    CpuASL, CpuLSR, CpuROL, CpuROR: begin
                        assign_and_nz(op_result, alu_res_i, status_i, status_o);
                        if (curr_instr == CpuADC || curr_instr == CpuSBC ||
                            curr_instr == CpuASL || curr_instr == CpuLSR ||
                            curr_instr == CpuROL || curr_instr == CpuROR) begin
                                status_o[PS_CARRY] = alu_carry_i;
                        end
                        if (curr_instr == CpuADC || curr_instr == CpuSBC) begin
                            status_o[PS_OVERFLOW] = alu_overflow_i;
                        end
                    end
                    
                    CpuBIT: begin
                        status_o[PS_ZERO] = (alu_res_i == '0);
                        status_o[PS_OVERFLOW] = bus_data_i[6];
                        status_o[PS_NEGATIVE] = bus_data_i[7];
                    end
                    CpuCMP, CpuCPY, CpuCPX: begin
                        status_o[PS_CARRY] = (alu_carry_i || alu_res_i == '0);
                        status_o[PS_ZERO] = (alu_res_i == '0);
                        status_o[PS_NEGATIVE] = alu_res_i[7];
                    end
                    
                    CpuPHP: op_result = status_i | 8'b00110000;

                    CpuCLC: status_o[PS_CARRY] = '0;
                    CpuCLD: status_o[PS_DEC] = '0;
                    CpuCLI: status_o[PS_INTDIS] = '0;
                    CpuCLV: status_o[PS_OVERFLOW] = '0;
                    CpuSEC: status_o[PS_CARRY] = '1;
                    CpuSED: status_o[PS_DEC] = '1;
                    CpuSEI: status_o[PS_INTDIS] = '1;
                    CpuPLP: status_o = bus_data_i & 8'b11001111;
                    default: ;
                endcase
            end
        end
        CpuRMW1: op_result = bus_data_i;
        CpuRtsRti3: if (curr_instr == CpuRTI) status_o = bus_data_i & 8'b11001111;
        CpuBrk6: status_o[PS_INTDIS] = 1'b1;
        default: begin
            case (curr_instr)
                CpuSTA, CpuPHA: op_result = reg_a_i;
                CpuSTX:         op_result = reg_x_i;
                CpuSTY:         op_result = reg_y_i;
                default: ;
            endcase
        end
    endcase
    if (state_i == CpuRMW2) begin
        // Status should only change on first calculation (done in CpuRMW1)
        status_o = status_i;
    end
end

always_comb begin : register_store_logic
    reg_a_o = reg_a_i;
    reg_x_o = reg_x_i;
    reg_y_o = reg_y_i;
    sp_o = sp_i;
    
    case (next_state)
        CpuReadOpcode: begin
            case (curr_instr)
                CpuLDA, CpuTXA, CpuTYA, CpuPLA,
                CpuADC, CpuSBC, CpuAND, CpuEOR, CpuORA: reg_a_o = op_result;
                CpuLDX, CpuTAX, CpuTSX, CpuINX, CpuDEX: reg_x_o = op_result;
                CpuLDY, CpuTAY, CpuINY, CpuDEY:         reg_y_o = op_result;

                CpuTXS:         sp_o = reg_x_i;
                CpuPHA, CpuPHP: sp_o = alu_res_i;

                CpuASL, CpuLSR, CpuROL, CpuROR: begin
                    if (addr_mode == AddrModeIMM || addr_mode == AddrModeIMP) reg_a_o = op_result;
                end
                default: ;
            endcase
        end
        CpuStackPop2,
        CpuJsr2, CpuJsr3,
        CpuRti2, CpuRtsRti3, CpuRtsRti4,
        CpuBrk3, CpuBrk4, CpuBrk5: sp_o = alu_res_i;
        default: ;
    endcase
end
    
always_comb begin : bus_write_logic
    // Read or write
    case (next_state)
        CpuImplied,
        CpuImmediate,
        CpuZeroPage2,
        CpuZeroPageIdx3,
        CpuAbsolute3,
        CpuAbsoluteIdx3,
        CpuIndirectX5,
        CpuIndirectY5: begin
            case (curr_instr)
                CpuSTA, CpuSTX, CpuSTY: bus_rw_o = '1;
                default: bus_rw_o = '0;
            endcase
        end
        CpuRMW1, CpuRMW2,
        CpuStackPush,
        CpuJsr2, CpuJsr3: bus_rw_o = '1;
        CpuBrk3, CpuBrk4, CpuBrk5: bus_rw_o = (int_type != IntReset);
        default: bus_rw_o = '0;
    endcase

    // Write data
    case (next_state)
        CpuJsr2, CpuBrk3: bus_data_o = pc_i[15:8];
        CpuJsr3, CpuBrk4: bus_data_o = pc_i[7:0];
        CpuBrk5: bus_data_o = status_i | ((int_type == IntBRK) ? 8'b00110000 : 8'b00100000);
        default: bus_data_o = op_result;
    endcase
end

always_comb begin : bus_address_logic
    case (next_state)
        CpuInvalid: ;
        CpuReadOpcode,
        CpuImplied,
        CpuImmediate: bus_address_o = next_pc;

        CpuZeroPage1: bus_address_o = next_pc;
        CpuZeroPage2,
        CpuZeroPageIdx2: bus_address_o = {8'h0, bus_data_i};
        CpuZeroPageIdx3: bus_address_o = {bus_address_i[15:8], alu_res_i};

        CpuAbsolute1,
        CpuAbsolute2:    bus_address_o = next_pc;
        CpuAbsolute3:    bus_address_o = {bus_data_i, tmp_store_i[7:0]};
        CpuAbsoluteIdx1: bus_address_o = next_pc;
        CpuAbsoluteIdx2: bus_address_o = {bus_data_i, alu_res_i};
        CpuAbsoluteIdx3: bus_address_o = {alu_res_i, bus_address_i[7:0]};

        CpuIndirectX1: bus_address_o = next_pc;
        CpuIndirectX2: bus_address_o = {8'h0, bus_data_i};
        CpuIndirectX3,
        CpuIndirectX4: bus_address_o = {8'h0, alu_res_i};
        CpuIndirectX5: bus_address_o = {bus_data_i, tmp_store_i[7:0]};

        CpuIndirectY1: bus_address_o = next_pc;
        CpuIndirectY2: bus_address_o = {8'h0, bus_data_i};
        CpuIndirectY3: bus_address_o = {8'h0, alu_res_i};
        CpuIndirectY4: bus_address_o = {bus_data_i, alu_res_i};
        CpuIndirectY5: bus_address_o = {alu_res_i, tmp_store_i[7:0]};

        CpuRelative1, CpuRelativeBrTaken, CpuRelativeFixPCH: bus_address_o = next_pc;

        CpuRMW1, CpuRMW2: bus_address_o = bus_address_i;

        CpuStackPush: bus_address_o = {8'h01, sp_i};

        CpuStackPop1, CpuStackPop2: bus_address_o = {8'h01, alu_res_i};
        
        CpuJmpInd1: bus_address_o = {bus_data_i, tmp_store_i[7:0]};
        CpuJmpInd2: bus_address_o = {tmp_store_i[15:8], alu_res_i};

        CpuJsr1,
        CpuJsr2,
        CpuJsr3: bus_address_o = {8'h01, sp_i};
        CpuJsr4: bus_address_o = next_pc;

        CpuRtsRti1: bus_address_o = next_pc;
        CpuRti2,
        CpuRtsRti3,
        CpuRtsRti4,
        CpuRtsRti5: bus_address_o = {8'h01, alu_res_i};
        CpuRts6: bus_address_o = next_pc;

        CpuBrk1: bus_address_o = next_pc;
        CpuBrk2: bus_address_o = next_pc;
        CpuBrk3: bus_address_o = {8'h01, sp_i};
        CpuBrk4: bus_address_o = {8'h01, sp_i};
        CpuBrk5: bus_address_o = {8'h01, sp_i};
        CpuBrk6: bus_address_o = (int_type == IntNMI) ? 16'hFFFA : (int_type == IntReset) ? 16'hFFFC : 16'hFFFE;
        CpuBrk7: bus_address_o = (int_type == IntNMI) ? 16'hFFFB : (int_type == IntReset) ? 16'hFFFD : 16'hFFFF;

        default: $error("State %s: Unhandled case for bus_address_o", next_state.name());
    endcase
end

endmodule
