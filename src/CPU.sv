`timescale 1ns / 1ps

// 6502 CPU module.

module CPU(
    input phi0,
    output [15:0] addr,
    input [7:0] data_in,
    output reg [7:0] data_out,
    output reg is_read = 1,
    input nmi,
    input rst,
    input activate_dma,
    output reg dma_active = 0,
    output reg dma_write = 0
);

wire phi1;
wire phi2;

assign phi1 = !phi0;
assign phi2 = !phi1;

reg [15:0] pc = 0;
reg [7:0] ps = 8'h24, sp = 8'hFD, acc = 8'b0, reg_x = 8'b0, reg_y = 8'b0;

reg [15:0] mem_addr_rw;

assign addr = mem_addr_rw;

// Indices into the PS register
localparam
    PS_CARRY    = 0,
    PS_ZERO     = 1,
    PS_INTDIS   = 2,
    PS_DEC      = 3,
    PS_BREAK    = 4,
    PS_NONAME   = 5,
    PS_OVERFLOW = 6,
    PS_NEGATIVE = 7;

typedef enum {
    ST_RESET, ST_RESET2,
    ST_READ_OPCODE,
    ST_OPCODE_SEI,
    ST_OPCODE_CLI,
    ST_OPCODE_SED,
    ST_OPCODE_CLD,
    ST_OPCODE_SEC,
    ST_OPCODE_CLC,
    ST_OPCODE_CLV,
    ST_OPCODE_IMMEDIATE,
    ST_OPCODE_ABSOLUTE1, ST_OPCODE_ABSOLUTE2,
    ST_OPCODE_LOAD_A_EA,
    ST_OPCODE_LOAD_X_EA,
    ST_OPCODE_LOAD_Y_EA,
    ST_OPCODE_WRITE_A_EA,
    ST_OPCODE_WRITE_X_EA,
    ST_OPCODE_WRITE_Y_EA,
    ST_OPCODE_RELATIVE1, ST_OPCODE_RELATIVE2, ST_OPCODE_RELATIVE3,
    ST_OPCODE_ZEROPAGE1,
    ST_OPCODE_ZEROPAGE_IDX2,
    ST_OPCODE_INDIRECT1,
    ST_OPCODE_INDIRECT_X2, ST_OPCODE_INDIRECT_X3, ST_OPCODE_INDIRECT_X4,
    ST_OPCODE_INDIRECT_Y2, ST_OPCODE_INDIRECT_Y3, ST_OPCODE_INDIRECT_Y4,
    ST_OPCODE_IMPLIED,
    ST_OPCODE_ABSOLUTE_REINDEX,
    ST_OPCODE_JSR1, ST_OPCODE_JSR2, ST_OPCODE_JSR3, ST_OPCODE_JSR4,
    ST_OPCODE_WRITE_PC,
    ST_OPCODE_RTS1, ST_OPCODE_RTS2, ST_OPCODE_RTS3, ST_OPCODE_RTS4, ST_OPCODE_RTS5,
    ST_OPCODE_WRITE_PC1, ST_OPCODE_WRITE_PC2,
    ST_OPCODE_BIT_EA,
    ST_OPCODE_AND_EA,
    ST_OPCODE_ORA_EA,
    ST_OPCODE_EOR_EA,
    ST_OPCODE_ADC_EA,
    ST_OPCODE_SBC_EA,
    ST_OPCODE_SHR_EA,
    ST_OPCODE_RMW1, ST_OPCODE_RMW2, ST_OPCODE_RMW3,
    ST_OPCODE_PUSH_ST,
    ST_OPCODE_PULL_ST1, ST_OPCODE_PULL_ST2,
    ST_OPCODE_RTI2, ST_OPCODE_RTI3,
    ST_OPCODE_BRK1, ST_OPCODE_BRK2, ST_OPCODE_BRK3, ST_OPCODE_BRK4, ST_OPCODE_BRK5, ST_OPCODE_BRK6,
    ST_OPCODE_CMP_A_EA,
    ST_OPCODE_CMP_X_EA,
    ST_OPCODE_CMP_Y_EA,
    ST_DMA_DELAY,
    ST_DMA_READ,
    ST_DMA_WRITE,
    ST_HALT = 'h7F
} STATE_e;

STATE_e state = ST_RESET;
STATE_e state_next = ST_RESET;

// temporaries used during opcode execution
reg [7:0] opcode;

reg [15:0] eff_addr = 0;
reg [7:0] relative_branch_amount;

reg [7:0] indirect_addr_latch;
reg [7:0] jsr_tmp_address_byte;

reg [7:0] rmw_latch; // temporary storage for read-modify-write instructions

STATE_e backup_for_dma = ST_RESET; // where to resume after dma
reg [7:0] dma_offs = 0;
reg [7:0] dma_bank = 0;
reg [7:0] dma_data_latch = 0;

reg [7:0] alu_input_a = 0;
reg [7:0] alu_input_b = 0;
reg alu_use_data = 0;
reg alu_carry_in;
reg [2:0] aluop;
wire [7:0] alu_out;
wire alu_overflow;
wire alu_carry_out;

CPU_ALU alu(
    .in_a(alu_input_a),
    .in_b((alu_use_data) ? data_in : alu_input_b),
    .carry_in(alu_carry_in),
    .aluop(aluop),
    .out(alu_out),
    .overflow(alu_overflow),
    .carry_out(alu_carry_out)
);

task setPSZeroAndNeg;
    input [7:0] in;
begin
    ps[PS_ZERO] <= (in == 0);
    ps[PS_NEGATIVE] <= (in[7] == 1);
end
endtask

task setupALUWithData;
    input [7:0] a;
    input carry;
    input [2:0] op;
begin
    alu_input_a <= a;
    alu_use_data <= 1;
    alu_carry_in <= carry;
    aluop <= op;
end
endtask

task setupALUWithB;
    input [7:0] a;
    input [7:0] b;
    input carry;
    input [2:0] op;
begin
    alu_input_a <= a;
    alu_input_b <= b;
    alu_use_data <= 0;
    alu_carry_in <= carry;
    aluop <= op;
end
endtask

task handleImpliedPhi1;
begin
    case (opcode)
        'h0A: begin
            setupALUWithData(acc, 0, 6);
        end
        'h4A: begin
            setupALUWithData(acc, 0, 5);
        end
        'h6A: begin
            setupALUWithData(acc, ps[PS_CARRY], 5);
        end
        'h2A: begin
            setupALUWithData(acc, ps[PS_CARRY], 6);
        end
        'h9A: begin
            sp <= reg_x;
        end
        'hCA: begin
            setupALUWithB(reg_x, 1, 1, 1);
        end
        'h88: begin
            setupALUWithB(reg_y, 1, 1, 1);
        end
        'hE8: begin
            setupALUWithB(reg_x, 1, 0, 0);
        end
        'hC8: begin
            setupALUWithB(reg_y, 1, 0, 0);
        end
    endcase
end
endtask

task handleImpliedPhi2;
begin
    case (opcode)
        'h18: ps[PS_CARRY] <= 0;
        'h38: ps[PS_CARRY] <= 1;
        'h58: ps[PS_INTDIS] <= 0;
        'h78: ps[PS_INTDIS] <= 1;
        'hB8: ps[PS_OVERFLOW] <= 0;
        'hD8: ps[PS_DEC] <= 0;
        'hF8: ps[PS_DEC] <= 1;
        'h0A, 'h4A, 'h6A, 'h2A: begin
            acc = alu_out;
            ps[PS_CARRY] <= alu_carry_out;
            setPSZeroAndNeg(alu_out);
        end
        'h8A, 'h98: begin
            acc = (opcode[4]) ? reg_y : reg_x;
            setPSZeroAndNeg(acc);
        end
        'hAA, 'hBA: begin
            reg_x = (opcode[4]) ? sp : acc;
            setPSZeroAndNeg(reg_x);
        end
        'hA8: begin
            reg_y = acc;
            setPSZeroAndNeg(reg_y);
        end
        'hCA, 'hE8: begin
            reg_x = alu_out;
            setPSZeroAndNeg(reg_x);
        end
        'h88, 'hC8: begin
            reg_y = alu_out;
            setPSZeroAndNeg(reg_y);
        end
    endcase
end
endtask

reg powerup_latch = 0;
reg needs_break = 0;

reg nmi_delayed = 0;
always @ (posedge phi1) begin
    nmi_delayed <= nmi;
end
wire nmi_pulse = nmi & ~nmi_delayed;

reg del_activate_dma = 0;
always @ (posedge phi1) begin
    del_activate_dma <= activate_dma;
end
wire activate_dma_pulse = activate_dma & ~del_activate_dma;

always @ (posedge phi1)
begin
    if (state == ST_RESET) powerup_latch <= 1;
    state = state_next;
    alu_use_data <= 0;
    if (nmi_pulse) begin
        needs_break <= 1;
    end
    if (state == ST_READ_OPCODE && needs_break) begin
        needs_break <= 0;
        state = ST_OPCODE_BRK1;
    end

    if (activate_dma_pulse) begin
        backup_for_dma = state;
        state = ST_DMA_DELAY;
        dma_bank <= data_out;
        dma_offs <= 0;
    end

    dma_active <= (state == ST_DMA_READ || state == ST_DMA_WRITE);

    if (state == ST_DMA_READ) begin
        dma_write <= 0;
    end else if (state == ST_DMA_WRITE) begin
        dma_write <= 1;
        data_out <= dma_data_latch;
        dma_offs <= dma_offs + 1;
    end

    // set r/w
    case (state)
        ST_OPCODE_RMW2,
        ST_OPCODE_RMW3,
        ST_OPCODE_JSR3, ST_OPCODE_JSR4,
        ST_OPCODE_BRK2, ST_OPCODE_BRK3, ST_OPCODE_BRK4,
        ST_OPCODE_PUSH_ST,
        ST_OPCODE_WRITE_A_EA,
        ST_OPCODE_WRITE_X_EA,
        ST_OPCODE_WRITE_Y_EA:
            is_read <= 0;
        default:
            is_read <= 1;
    endcase

    // set r/w address
    case (state)
        ST_RESET: begin
            mem_addr_rw <= 'hFFFC;
            sp <= 8'hFD;
        end
        ST_RESET2:
            mem_addr_rw <= 'hFFFD;
        ST_OPCODE_BRK5:
            mem_addr_rw <= (opcode == 'h00) ? 'hFFFE : 'hFFFA;
        ST_OPCODE_BRK6:
            mem_addr_rw <= (opcode == 'h00) ? 'hFFFF : 'hFFFB;
        ST_OPCODE_JSR3, ST_OPCODE_JSR4,
        ST_OPCODE_BRK2,
        ST_OPCODE_BRK3,
        ST_OPCODE_BRK4,
        ST_OPCODE_RTS3, ST_OPCODE_RTS4,
        ST_OPCODE_RTI3,
        ST_OPCODE_PUSH_ST,
        ST_OPCODE_PULL_ST2:
            mem_addr_rw <= {8'h01, sp};
        ST_OPCODE_ZEROPAGE_IDX2,
        ST_OPCODE_RMW1, ST_OPCODE_RMW2, ST_OPCODE_RMW3,
        ST_OPCODE_WRITE_A_EA, ST_OPCODE_WRITE_X_EA, ST_OPCODE_WRITE_Y_EA,
        ST_OPCODE_LOAD_A_EA, ST_OPCODE_LOAD_X_EA, ST_OPCODE_LOAD_Y_EA,
        ST_OPCODE_WRITE_PC1,  ST_OPCODE_WRITE_PC2,
        ST_OPCODE_ADC_EA,
        ST_OPCODE_SBC_EA,
        ST_OPCODE_BIT_EA,
        ST_OPCODE_AND_EA,
        ST_OPCODE_EOR_EA,
        ST_OPCODE_ORA_EA,
        ST_OPCODE_CMP_A_EA, ST_OPCODE_CMP_X_EA, ST_OPCODE_CMP_Y_EA:
            mem_addr_rw <= eff_addr;
        ST_OPCODE_INDIRECT_Y2, ST_OPCODE_INDIRECT_Y3,
        ST_OPCODE_INDIRECT_X2, ST_OPCODE_INDIRECT_X3, ST_OPCODE_INDIRECT_X4:
            mem_addr_rw <= {7'b0, indirect_addr_latch};
        ST_DMA_READ:
            mem_addr_rw <= {dma_bank, dma_offs};
        default:
            mem_addr_rw <= pc;
    endcase

    // default ALU input: a: 0, b: <data>, carry: 0, operation: ADC
    alu_input_a <= 0;
    alu_carry_in <= 0;
    alu_use_data <= 1;
    aluop <= 0;

    case (state)
        ST_OPCODE_ZEROPAGE_IDX2: begin
            setupALUWithB(eff_addr[7:0], (opcode == 'h96 || opcode == 'hB6) ? reg_y : reg_x, 0, 0);
        end
        ST_OPCODE_ABSOLUTE2: begin
            setupALUWithB(eff_addr[7:0], (opcode[3:0] == 'h9 || opcode == 'hBE) ? reg_y : reg_x, 0, 0);
        end
        ST_OPCODE_ABSOLUTE_REINDEX: begin
            setupALUWithB(eff_addr[15:8], 1, 0, 0);
        end
        ST_OPCODE_RELATIVE2: begin
            alu_input_a <= pc[7:0];
            alu_input_b <= (relative_branch_amount[7]) ? -relative_branch_amount : relative_branch_amount;
            alu_use_data <= 0;
            alu_carry_in <= relative_branch_amount[7]; // carry is inverted when subtracting
            aluop <= {2'b00, relative_branch_amount[7]}; // 0 = add, 1 = subtract
        end
        ST_OPCODE_RELATIVE3: begin
            setupALUWithB(pc[15:8], (relative_branch_amount[7]) ? -8'b1 : 8'b1, 0, 0);
        end
        ST_OPCODE_INDIRECT_Y3: begin
            setupALUWithB(eff_addr[7:0], reg_y, 0, 0);
        end
        ST_OPCODE_INDIRECT_X2,
        ST_OPCODE_INDIRECT_X4: begin
            setupALUWithB(indirect_addr_latch, reg_x, 0, 0);
        end
        ST_OPCODE_INDIRECT_X3: begin
            setupALUWithB(indirect_addr_latch, 1, 0, 0);
        end
        ST_OPCODE_RMW2: begin
            data_out <= rmw_latch;
            case (opcode[7:5])
                'h0: setupALUWithB(rmw_latch, 0, 0, 6);
                'h1: setupALUWithB(rmw_latch, 0, ps[PS_CARRY], 6);
                'h2: setupALUWithB(rmw_latch, 0, 0, 5);
                'h3: setupALUWithB(rmw_latch, 0, ps[PS_CARRY], 5);
                'h6: setupALUWithB(rmw_latch, 1, 1, 1);
                'h7: setupALUWithB(rmw_latch, 1, 0, 0);
            endcase
        end
        ST_OPCODE_RMW3: begin
            data_out <= rmw_latch;
        end
        ST_OPCODE_JSR3,
        ST_OPCODE_BRK2: begin
            data_out <= pc[15:8];
            sp <= sp - 1;
        end
        ST_OPCODE_JSR4,
        ST_OPCODE_BRK3: begin
            data_out <= pc[7:0];
            sp <= sp - 1;
        end
        ST_OPCODE_BRK4: begin
            data_out <= ps;
            sp <= sp - 1;
        end
        ST_OPCODE_PUSH_ST: begin
            data_out <= (opcode[6]) ? acc : (ps | (1 << PS_BREAK));
            sp <= sp - 1;
        end
        ST_OPCODE_RTS2,
        ST_OPCODE_RTS3,
        ST_OPCODE_RTI2,
        ST_OPCODE_RTI3,
        ST_OPCODE_PULL_ST1: begin
            sp <= sp + 1;
        end
        ST_OPCODE_WRITE_A_EA,
        ST_OPCODE_WRITE_X_EA,
        ST_OPCODE_WRITE_Y_EA: begin
            data_out <= (state == ST_OPCODE_WRITE_A_EA) ? acc : (state == ST_OPCODE_WRITE_X_EA) ? reg_x : reg_y;
        end
        ST_OPCODE_ADC_EA: begin
            setupALUWithData(acc, ps[PS_CARRY], 0);
        end
        ST_OPCODE_SBC_EA: begin
            setupALUWithData(acc, ps[PS_CARRY], 1);
        end
        ST_OPCODE_CMP_A_EA: begin
            setupALUWithData(acc, 1, 1);
        end
        ST_OPCODE_CMP_X_EA: begin
            setupALUWithData(reg_x, 1, 1);
        end
        ST_OPCODE_CMP_Y_EA: begin
            setupALUWithData(reg_y, 1, 1);
        end
        ST_OPCODE_BIT_EA,
        ST_OPCODE_AND_EA: begin
            setupALUWithData(acc, 0, 2);
        end
        ST_OPCODE_EOR_EA: begin
            setupALUWithData(acc, 0, 3);
        end
        ST_OPCODE_ORA_EA: begin
            setupALUWithData(acc, 0, 4);
        end
        ST_OPCODE_IMPLIED: begin
            handleImpliedPhi1();
        end
    endcase
end

always @(posedge phi2) begin
    state_next <= ST_HALT; // for debugging purposes

    case (state)
        ST_READ_OPCODE,
        ST_OPCODE_ABSOLUTE1, ST_OPCODE_ABSOLUTE2,
        ST_OPCODE_IMMEDIATE,
        ST_OPCODE_RELATIVE1,
        ST_OPCODE_INDIRECT1,
        ST_OPCODE_ZEROPAGE1,
        ST_OPCODE_JSR1,
        ST_OPCODE_WRITE_PC: begin
            pc <= pc + 1;
        end

        ST_OPCODE_SEI,
        ST_OPCODE_CLI,
        ST_OPCODE_SED,
        ST_OPCODE_CLD,
        ST_OPCODE_SEC,
        ST_OPCODE_CLC,
        ST_OPCODE_CLV,
        ST_OPCODE_WRITE_A_EA,
        ST_OPCODE_WRITE_X_EA,
        ST_OPCODE_WRITE_Y_EA: begin
            state_next <= ST_READ_OPCODE;
        end
    endcase

    case (state)
        ST_RESET: begin
            pc[7:0] <= data_in;
            state_next <= (powerup_latch) ? ST_RESET2 : ST_RESET;
            ps <= 8'h24;
            acc = 8'b0;
            reg_x = 8'b0;
            reg_y = 8'b0;
        end
        ST_RESET2: begin
            pc[15:8] <= data_in;
            state_next <= ST_READ_OPCODE;
        end
        ST_DMA_DELAY: state_next <= ST_DMA_READ;
        ST_DMA_READ: begin
            state_next <= ST_DMA_WRITE;
            dma_data_latch <= data_in;
        end
        ST_DMA_WRITE: begin
            state_next <= ST_DMA_READ;
            if (dma_offs == 'hFF) state_next <= backup_for_dma;
        end
        ST_READ_OPCODE: begin
            opcode <= data_in;
            case (data_in)
                'h58: state_next <= ST_OPCODE_CLI;
                'h78: state_next <= ST_OPCODE_SEI;
                'hD8: state_next <= ST_OPCODE_CLD;
                'hF8: state_next <= ST_OPCODE_SED;
                'hA0: state_next <= ST_OPCODE_IMMEDIATE; // LDY
                'hA2: state_next <= ST_OPCODE_IMMEDIATE; // LDX
                'h20: state_next <= ST_OPCODE_JSR1;
                'hE0: begin
                    eff_addr <= pc + 1;
                    state_next <= ST_OPCODE_CMP_X_EA;
                end
                'hC0: begin
                    eff_addr <= pc + 1;
                    state_next <= ST_OPCODE_CMP_Y_EA;
                end
                'h08, 'h28, 'h48, 'h68: state_next <= ST_OPCODE_IMMEDIATE; // stack operations do a dummy read
                default: begin
                    case (data_in[3:0])
                        'h0: state_next <= ST_OPCODE_RELATIVE1;
                        'h1: state_next <= ST_OPCODE_INDIRECT1;
                        'h4, 'h5, 'h6: state_next <= ST_OPCODE_ZEROPAGE1;
                        'h8, 'hA: state_next <= ST_OPCODE_IMPLIED;
                        'h9: begin
                            if (!data_in[4]) begin
                                state_next <= ST_OPCODE_IMMEDIATE;
                                eff_addr <= pc + 1;
                                pc <= pc + 2;
                                case (data_in[7:5])
                                    'h0: state_next <= ST_OPCODE_ORA_EA;
                                    'h1: state_next <= ST_OPCODE_AND_EA;
                                    'h2: state_next <= ST_OPCODE_EOR_EA;
                                    'h3: state_next <= ST_OPCODE_ADC_EA;
                                    'h5: state_next <= ST_OPCODE_LOAD_A_EA;
                                    'h6: begin
                                        eff_addr <= pc + 1;
                                        state_next <= ST_OPCODE_CMP_A_EA;
                                    end
                                    'h7: state_next <= ST_OPCODE_SBC_EA;
                                endcase
                            end else begin
                                state_next <= ST_OPCODE_ABSOLUTE1;
                            end
                        end
                        'hC, 'hD, 'hE: state_next <= ST_OPCODE_ABSOLUTE1;
                    endcase
                end
            endcase
        end
        ST_OPCODE_ABSOLUTE1: begin
            eff_addr[7:0] <= data_in;
            state_next <= ST_OPCODE_ABSOLUTE2;
        end
        ST_OPCODE_ABSOLUTE2, ST_OPCODE_ABSOLUTE_REINDEX: begin
            eff_addr[15:8] <= (state == ST_OPCODE_ABSOLUTE_REINDEX) ? alu_out : data_in;
            case (opcode)
                'h0D, 'h19, 'h1D: state_next <= ST_OPCODE_ORA_EA;
                'h0E,       'h1E: state_next <= ST_OPCODE_RMW1; // ASL
                'h2C            : state_next <= ST_OPCODE_BIT_EA;
                'h2D, 'h39, 'h3D: state_next <= ST_OPCODE_AND_EA;
                'h2E,       'h3E: state_next <= ST_OPCODE_RMW1; // ROL
                'h4C: begin
                    pc <= {data_in, eff_addr[7:0]};
                    state_next <= ST_READ_OPCODE;
                end
                'h4D, 'h59, 'h5D: state_next <= ST_OPCODE_EOR_EA;
                'h4E,       'h5E: state_next <= ST_OPCODE_RMW1; // LSR
                'h6C            : state_next <= ST_OPCODE_WRITE_PC1;
                'h6D, 'h79, 'h7D: state_next <= ST_OPCODE_ADC_EA;
                'h6E,       'h7E: state_next <= ST_OPCODE_RMW1; // ROR
                'h8C,       'h9C: state_next <= ST_OPCODE_WRITE_Y_EA;
                'h8D, 'h99, 'h9D: state_next <= ST_OPCODE_WRITE_A_EA;
                'h8E,       'h9E: state_next <= ST_OPCODE_WRITE_X_EA;
                'hAC,       'hBC: state_next <= ST_OPCODE_LOAD_Y_EA;
                'hAD, 'hB9, 'hBD: state_next <= ST_OPCODE_LOAD_A_EA;
                'hAE, 'hBE      : state_next <= ST_OPCODE_LOAD_X_EA;
                'hCC            : state_next <= ST_OPCODE_CMP_Y_EA;
                'hCD, 'hD9, 'hDD: state_next <= ST_OPCODE_CMP_A_EA;
                'hCE,       'hDE: state_next <= ST_OPCODE_RMW1; // DEC
                'hEC            : state_next <= ST_OPCODE_CMP_X_EA;
                'hED, 'hF9, 'hFD: state_next <= ST_OPCODE_SBC_EA;
                'hEE,       'hFE: state_next <= ST_OPCODE_RMW1; // INC
            endcase

            if (opcode[4] && state == ST_OPCODE_ABSOLUTE2) begin
                eff_addr[7:0] <= alu_out;
                if (alu_carry_out) begin
                    state_next <= ST_OPCODE_ABSOLUTE_REINDEX;
                end
            end
        end
        ST_OPCODE_INDIRECT1: begin
            indirect_addr_latch <= data_in;
            state_next <= (opcode[4]) ? ST_OPCODE_INDIRECT_Y2 : ST_OPCODE_INDIRECT_X2;
        end
        ST_OPCODE_INDIRECT_Y2: begin
            eff_addr[7:0] <= data_in;
            indirect_addr_latch <= indirect_addr_latch + 1;
            state_next <= ST_OPCODE_INDIRECT_Y3;
        end
        ST_OPCODE_INDIRECT_Y3,
        ST_OPCODE_INDIRECT_Y4,
        ST_OPCODE_INDIRECT_X4: begin
            case (opcode[7:5])
                'h0: state_next <= ST_OPCODE_ORA_EA;
                'h1: state_next <= ST_OPCODE_AND_EA;
                'h2: state_next <= ST_OPCODE_EOR_EA;
                'h3: state_next <= ST_OPCODE_ADC_EA;
                'h4: state_next <= ST_OPCODE_WRITE_A_EA;
                'h5: state_next <= ST_OPCODE_LOAD_A_EA;
                'h6: state_next <= ST_OPCODE_CMP_A_EA;
                'h7: state_next <= ST_OPCODE_SBC_EA;
            endcase
            if (state == ST_OPCODE_INDIRECT_Y3) begin
                eff_addr[15:8] <= data_in;
                eff_addr[7:0] <= alu_out;
                if (alu_carry_out) state_next <= ST_OPCODE_INDIRECT_Y4;
            end else if (state == ST_OPCODE_INDIRECT_X4) begin
            eff_addr[15:8] <= data_in;
            end else begin
                eff_addr[15:8] <= eff_addr[15:8] + 1;
            end
        end
        ST_OPCODE_INDIRECT_X2: begin
            indirect_addr_latch <= alu_out;
            state_next <= ST_OPCODE_INDIRECT_X3;
        end
        ST_OPCODE_INDIRECT_X3: begin
            eff_addr[7:0] <= data_in;
            indirect_addr_latch <= alu_out;
            state_next <= ST_OPCODE_INDIRECT_X4;
        end
        ST_OPCODE_JSR1: begin
            jsr_tmp_address_byte <= data_in;
            state_next <= ST_OPCODE_JSR2;
        end
        ST_OPCODE_JSR2: state_next <= ST_OPCODE_JSR3;
        ST_OPCODE_JSR3: state_next <= ST_OPCODE_JSR4;
        ST_OPCODE_JSR4: state_next <= ST_OPCODE_WRITE_PC;
        ST_OPCODE_WRITE_PC: begin
            pc <= {data_in, jsr_tmp_address_byte};
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_RTI2: state_next <= ST_OPCODE_RTI3;
        ST_OPCODE_RTI3: begin
            // ignore break and unknown status bits
            ps[7:6] <= data_in[7:6];
            ps[3:0] <= data_in[3:0];
            state_next <= ST_OPCODE_RTS3;
        end
        ST_OPCODE_RTS2: state_next <= ST_OPCODE_RTS3;
        ST_OPCODE_RTS3: begin
            pc[7:0] <= data_in;
            state_next <= ST_OPCODE_RTS4;
        end
        ST_OPCODE_RTS4: begin
            pc[15:8] <= data_in;
            state_next <= (opcode[5]) ? ST_OPCODE_RTS5 : ST_READ_OPCODE; // RTS vs RTI
        end
        ST_OPCODE_RTS5: begin
            pc <= pc + 1;
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_IMPLIED: begin
            handleImpliedPhi2();
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_IMMEDIATE: begin
            if (opcode[7:4] == 'hA) begin
                case (opcode[3:0])
                    'h0: reg_y = data_in;
                    'h2: reg_x = data_in;
                    'h9: acc   = data_in;
                endcase
                setPSZeroAndNeg(data_in);
                state_next <= ST_READ_OPCODE;
            end
            case (opcode)
                'h08, 'h48: begin
                    pc <= pc; // don't increment pc
                    state_next <= ST_OPCODE_PUSH_ST;
                end
                'h28, 'h68: begin
                    pc <= pc; // don't increment pc
                    state_next <= ST_OPCODE_PULL_ST1;
                end
            endcase
        end
        ST_OPCODE_RELATIVE1: begin
            relative_branch_amount <= data_in;
            state_next <= ST_READ_OPCODE;
            case (opcode[7:4])
                'h0: state_next <= ST_OPCODE_BRK2;
                'h1: if (!ps[PS_NEGATIVE]) state_next <= ST_OPCODE_RELATIVE2;
                'h3: if (ps[PS_NEGATIVE]) state_next <= ST_OPCODE_RELATIVE2;
                'h4: state_next <= ST_OPCODE_RTI2;
                'h5: if (!ps[PS_OVERFLOW]) state_next <= ST_OPCODE_RELATIVE2;
                'h6: state_next <= ST_OPCODE_RTS2;
                'h7: if (ps[PS_OVERFLOW]) state_next <= ST_OPCODE_RELATIVE2;
                'h9: if (!ps[PS_CARRY]) state_next <= ST_OPCODE_RELATIVE2;
                'hB: if (ps[PS_CARRY]) state_next <= ST_OPCODE_RELATIVE2;
                'hD: if (!ps[PS_ZERO]) state_next <= ST_OPCODE_RELATIVE2;
                'hF: if (ps[PS_ZERO]) state_next <= ST_OPCODE_RELATIVE2;
            endcase
        end
        ST_OPCODE_RELATIVE2: begin
            pc <= {pc[15:8], alu_out};
            // carry is inverted when subtracting
            state_next <= (relative_branch_amount[7] ^ alu_carry_out) ? ST_OPCODE_RELATIVE3 : ST_READ_OPCODE;
        end
        ST_OPCODE_RELATIVE3: begin
            pc <= {alu_out, pc[7:0]};
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_ZEROPAGE1, ST_OPCODE_ZEROPAGE_IDX2: begin
            eff_addr <= {8'b0, alu_out};
            case ({opcode[7:5], 1'b0, opcode[3:0]}) // catch e.g. 0x05 and 0x15 as ORA
                'h05: state_next <= ST_OPCODE_ORA_EA;
                'h06: state_next <= ST_OPCODE_RMW1; // ASL
                'h24: state_next <= ST_OPCODE_BIT_EA;
                'h25: state_next <= ST_OPCODE_AND_EA;
                'h26: state_next <= ST_OPCODE_RMW1; // ROL
                'h45: state_next <= ST_OPCODE_EOR_EA;
                'h46: state_next <= ST_OPCODE_RMW1; // LSR
                'h65: state_next <= ST_OPCODE_ADC_EA;
                'h66: state_next <= ST_OPCODE_RMW1; // ROR
                'h84: state_next <= ST_OPCODE_WRITE_Y_EA;
                'h85: state_next <= ST_OPCODE_WRITE_A_EA;
                'h86: state_next <= ST_OPCODE_WRITE_X_EA;
                'hA4: state_next <= ST_OPCODE_LOAD_Y_EA;
                'hA5: state_next <= ST_OPCODE_LOAD_A_EA;
                'hA6: state_next <= ST_OPCODE_LOAD_X_EA;
                'hC4: state_next <= ST_OPCODE_CMP_Y_EA;
                'hC5: state_next <= ST_OPCODE_CMP_A_EA;
                'hC6: state_next <= ST_OPCODE_RMW1; // DEC
                'hE4: state_next <= ST_OPCODE_CMP_X_EA;
                'hE5: state_next <= ST_OPCODE_SBC_EA;
                'hE6: state_next <= ST_OPCODE_RMW1; // INC
            endcase
            if (opcode[4] && state == ST_OPCODE_ZEROPAGE1) begin
                state_next <= ST_OPCODE_ZEROPAGE_IDX2;
            end
        end
        ST_OPCODE_RMW1: begin
            rmw_latch <= data_in;
            state_next <= ST_OPCODE_RMW2;
        end
        ST_OPCODE_RMW2: begin
            rmw_latch <= alu_out;
            setPSZeroAndNeg(alu_out);
            case (opcode[7:5])
                'h0, 'h1, 'h2, 'h3:
                ps[PS_CARRY] <= alu_carry_out;
            endcase
            state_next <= ST_OPCODE_RMW3;
        end
        ST_OPCODE_RMW3: state_next <= ST_READ_OPCODE;
        ST_OPCODE_PUSH_ST: state_next <= ST_READ_OPCODE;
        ST_OPCODE_PULL_ST1: state_next <= ST_OPCODE_PULL_ST2;
        ST_OPCODE_PULL_ST2: begin
            if (opcode[6]) begin
                acc = data_in;
                setPSZeroAndNeg(data_in);
            end else begin
                // ignore break and unknown status bits
                ps[7:6] <= data_in[7:6];
                ps[3:0] <= data_in[3:0];
            end
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_LOAD_A_EA: begin
            acc = data_in;
            setPSZeroAndNeg(data_in);
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_LOAD_X_EA: begin
            reg_x = data_in;
            setPSZeroAndNeg(reg_x);
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_LOAD_Y_EA: begin
            reg_y = data_in;
            setPSZeroAndNeg(reg_y);
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_WRITE_PC1: begin
            pc[7:0] <= data_in;
            eff_addr[7:0] <= eff_addr[7:0] + 1;
            state_next <= ST_OPCODE_WRITE_PC2;
        end
        ST_OPCODE_WRITE_PC2: begin
            pc[15:8] <= data_in;
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_ADC_EA,
        ST_OPCODE_SBC_EA: begin
            acc = alu_out;
            ps[PS_CARRY] <= alu_carry_out;
            ps[PS_OVERFLOW] <= alu_overflow;
            setPSZeroAndNeg(alu_out);
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_BIT_EA: begin
            setPSZeroAndNeg(alu_out);
            ps[PS_OVERFLOW] <= data_in[6];
            ps[PS_NEGATIVE] <= data_in[7];
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_AND_EA,
        ST_OPCODE_ORA_EA,
        ST_OPCODE_EOR_EA: begin
            acc = alu_out;
            setPSZeroAndNeg(alu_out);
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_CMP_A_EA,
        ST_OPCODE_CMP_X_EA,
        ST_OPCODE_CMP_Y_EA: begin
            if (opcode == 'hE0 || opcode == 'hC0) pc <= pc + 1;
            setPSZeroAndNeg(alu_out);
            ps[PS_CARRY] <= (alu_input_a >= data_in); // TODO: should probably do this with the ALU
            state_next <= ST_READ_OPCODE;
        end
        ST_OPCODE_SEI: ps[PS_INTDIS] <= 1;
        ST_OPCODE_CLI: ps[PS_INTDIS] <= 0;
        ST_OPCODE_SED: ps[PS_DEC] <= 1;
        ST_OPCODE_CLD: ps[PS_DEC] <= 0;
        ST_OPCODE_SEC: ps[PS_CARRY] <= 1;
        ST_OPCODE_CLC: ps[PS_CARRY] <= 0;
        ST_OPCODE_CLV: ps[PS_OVERFLOW] <= 0;

        ST_OPCODE_BRK1: state_next <= ST_OPCODE_BRK2;
        ST_OPCODE_BRK2: state_next <= ST_OPCODE_BRK3;
        ST_OPCODE_BRK3: state_next <= ST_OPCODE_BRK4;
        ST_OPCODE_BRK4: state_next <= ST_OPCODE_BRK5;
        ST_OPCODE_BRK5: begin
            pc[7:0] <= data_in;
            state_next <= ST_OPCODE_BRK6;
        end
        ST_OPCODE_BRK6: begin
            pc[15:8] <= data_in;
            state_next <= ST_READ_OPCODE;
        end
    endcase

    if (rst) begin
        state_next <= ST_RESET;
    end
end

endmodule
