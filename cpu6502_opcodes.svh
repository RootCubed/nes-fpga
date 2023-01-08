`ifndef CPU6502_OPCODES_SV
`define CPU6502_OPCODES_SV

typedef enum {
    CpuERR,
    CpuADC, CpuAND, CpuASL, CpuBCC, CpuBCS, CpuBEQ, CpuBIT,
    CpuBMI, CpuBNE, CpuBPL, CpuBRK, CpuBVC, CpuBVS, CpuCLC,
    CpuCLD, CpuCLI, CpuCLV, CpuCMP, CpuCPX, CpuCPY, CpuDEC,
    CpuDEX, CpuDEY, CpuEOR, CpuINC, CpuINX, CpuINY, CpuJMP,
    CpuJSR, CpuLDA, CpuLDX, CpuLDY, CpuLSR, CpuNOP, CpuORA,
    CpuPHA, CpuPHP, CpuPLA, CpuPLP, CpuROL, CpuROR, CpuRTI,
    CpuRTS, CpuSBC, CpuSEC, CpuSED, CpuSEI, CpuSTA, CpuSTX,
    CpuSTY, CpuTAX, CpuTAY, CpuTSX, CpuTXA, CpuTXS, CpuTYA
} cpu_instr_e;

/*
Addressing types:

IMP: Implied
IMM: Immediate
ZPG: Zero page
ZPX: Zero page, X
ZPY: Zero page, Y
ABS: Absolute
ABX: Absolute, X
ABY: Absolute, Y
INX: (Indirect, X)
INY: (Indirect), Y
REL: Relative
*/

typedef enum {
    AddrModeIMP, AddrModeIMM, AddrModeZPG,
    AddrModeZPX, AddrModeZPY, AddrModeABS,
    AddrModeABX, AddrModeABY, AddrModeINX,
    AddrModeINY, AddrModeREL
} cpu_addrmode_e;

// Lookup tables for addressing modes
localparam cpu_addrmode_e c0_c2_addrmodes[0:7] = {
    AddrModeIMM, AddrModeZPG, AddrModeIMP, AddrModeABS,
    AddrModeREL, AddrModeZPX, AddrModeIMP, AddrModeABX
};
localparam cpu_addrmode_e c1_addrmodes[0:7] = {
    AddrModeINX, AddrModeZPG, AddrModeIMM, AddrModeABS,
    AddrModeINY, AddrModeZPX, AddrModeABY, AddrModeABX
};

// Gets the addressing mode for an opcode
function cpu_addrmode_e get_addr_mode([7:0] opcode);
    if (opcode[1:0] == 0) begin
        if (opcode[4:2] == 0 && opcode[7:5] < 4) begin
            if (opcode[7:5] == 1) begin
                get_addr_mode = AddrModeABS;
            end else begin
                get_addr_mode = AddrModeIMP;
            end
        end else begin
            get_addr_mode = c0_c2_addrmodes[opcode[4:2]];
        end
    end else if (opcode[1:0] == 1) begin
        get_addr_mode = c1_addrmodes[opcode[4:2]];
    end else begin
        if (opcode == 'hBE) begin
            get_addr_mode = AddrModeABY;
        end else begin
            get_addr_mode = c0_c2_addrmodes[opcode[4:2]];
        end
    end
endfunction

// Lookup tables for instruction names
localparam cpu_instr_e c0_b0_instrnames[0:7] = {
    CpuBRK, CpuJSR, CpuRTI, CpuRTS, CpuERR, CpuLDY, CpuCPY, CpuCPX
};
localparam cpu_instr_e c0_b1_instrnames[0:7] = {
    CpuERR, CpuBIT, CpuERR, CpuERR, CpuSTY, CpuLDY, CpuCPY, CpuCPX
};
localparam cpu_instr_e c0_b2_instrnames[0:7] = {
    CpuPHP, CpuPLP, CpuPHA, CpuPLA, CpuDEY, CpuTAY, CpuINY, CpuINX
};
localparam cpu_instr_e c0_b3_instrnames[0:7] = {
    CpuERR, CpuBIT, CpuJMP, CpuJMP, CpuSTY, CpuLDY, CpuCPY, CpuCPX
};
localparam cpu_instr_e c0_b4_instrnames[0:7] = {
    CpuBPL, CpuBMI, CpuBVC, CpuBVS, CpuBCC, CpuBCS, CpuBNE, CpuBEQ
};
localparam cpu_instr_e c0_b6_instrnames[0:7] = {
    CpuCLC, CpuSEC, CpuCLI, CpuSEI, CpuTYA, CpuCLV, CpuCLD, CpuSED
};

// Gets the instruction name for an opcode
function cpu_instr_e get_instr([7:0] opcode);
    if (opcode[1:0] == 0) begin
        case (opcode[4:2])
            0: get_instr = c0_b0_instrnames[opcode[7:5]];
            1: get_instr = c0_b1_instrnames[opcode[7:5]];
            2: get_instr = c0_b2_instrnames[opcode[7:5]];
            3: get_instr = c0_b3_instrnames[opcode[7:5]];
            4: get_instr = c0_b4_instrnames[opcode[7:5]];
            5: get_instr = (opcode == 'h94) ? CpuSTY : CpuLDY;
            6: get_instr = c0_b6_instrnames[opcode[7:5]];
            7: get_instr = CpuLDY;
            default: get_instr = CpuERR;
        endcase
    end else if (opcode[1:0] == 1) begin
        case (opcode[7:5])
            0: get_instr = CpuORA;
            1: get_instr = CpuAND;
            2: get_instr = CpuEOR;
            3: get_instr = CpuADC;
            4: get_instr = CpuSTA;
            5: get_instr = CpuLDA;
            6: get_instr = CpuCMP;
            7: get_instr = CpuSBC;
            default: get_instr = CpuERR;
        endcase
    end else begin
        case (opcode[7:5])
            0: get_instr = CpuASL;
            1: get_instr = CpuROL;
            2: get_instr = CpuLSR;
            3: get_instr = CpuROR;
            4: begin
                case (opcode[4:2])
                    1, 3, 5: get_instr = CpuSTX;
                    2:       get_instr = CpuTXA;
                    6:       get_instr = CpuTXS;
                    default: get_instr = CpuERR;
                endcase
            end
            5: begin
                case (opcode[4:2])
                    0, 1, 3, 5, 7: get_instr = CpuLDX;
                    2:             get_instr = CpuTAX;
                    6:             get_instr = CpuTSX;
                    default:       get_instr = CpuERR;
                endcase
            end
            6: get_instr = (opcode == 'hCA) ? CpuDEX : CpuDEC;
            7: get_instr = (opcode == 'hEA) ? CpuNOP : CpuINC;
            default: get_instr = CpuERR;
        endcase
    end
endfunction;

// Returns if an opcode is a branch instruction
function is_branch([7:0] opcode);
    case (get_instr(opcode))
        CpuBCC, CpuBCS, CpuBEQ, CpuBMI,
        CpuBNE, CpuBPL, CpuBVC, CpuBVS: is_branch = '1;
        default: is_branch = '0;
    endcase
endfunction

// Returns if an opcode is an instruction that pushes/pulls a single value to/from the stack
function is_stack([7:0] opcode);
    case (get_instr(opcode))
        CpuPHA, CpuPHP, CpuPLA, CpuPLP: is_stack = '1;
        default: is_stack = '0;
    endcase
endfunction

// Returns if an opcode is a Read-Modify-Write instruction (if not in implied or immediate addressing mode)
function is_rmw([7:0] opcode);
    case (get_instr(opcode))
        CpuASL, CpuLSR, CpuROL, CpuROR,
        CpuINC, CpuDEC: begin
            case (get_addr_mode(opcode))
                AddrModeIMP, AddrModeIMM: is_rmw = '0;
                default: is_rmw = '1;
            endcase
        end
        default: is_rmw = '0;
    endcase
endfunction

// Returns if an opcode is an indirect JMP opcode
function is_jmp_indirect([7:0] opcode);
    is_jmp_indirect = (opcode == 'h6C);
endfunction

// Returns if an opcode uses Y-based indexing
function is_y_indexed([7:0] opcode);
    case (opcode)
        // STX and LDX are zero-page, Y
        'h96, 'hB6: is_y_indexed = '1;
        default: begin
            case (get_addr_mode(opcode))
                AddrModeABY, AddrModeINY: is_y_indexed = '1;
                default: is_y_indexed = '0;
            endcase
        end
    endcase
endfunction

// Returns if an opcode always needs an extra cycle for address calculation
function indexed_needs_extra([7:0] opcode);
    if (is_rmw(opcode)) begin
        indexed_needs_extra = '1;
    end else begin
        case (get_instr(opcode))
            CpuSTA, CpuSTX, CpuSTY: indexed_needs_extra = '1;
            default: indexed_needs_extra = '0;
        endcase
    end
endfunction

`endif
