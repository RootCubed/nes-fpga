`include "defs.svh"
`include "cpu6502_enums.svh"
`include "alu_op.svh"

module cpu6502 (
    input logic clk,
    input logic rst_n,

    output logic [15:0] bus_address_o,
    input  logic  [7:0] bus_data_i,
    output logic  [7:0] bus_data_o,
    output logic        bus_rw_o,

    input logic nmi_i
);

wire phi1 = !clk;
wire phi2 = !phi1;

cpu_state_e state_q, state_d; // FSM state

logic [15:0] pc_q, pc_d; // Program counter
logic [7:0] status_q, status_d; // Status flags
logic [7:0] sp_q, sp_d; // Stack pointer
logic [7:0] reg_a_q, reg_a_d, reg_x_q, reg_x_d, reg_y_q, reg_y_d;

`getter(state, state_q, cpu_state_e);
`getter(pc, pc_q, [15:0]);
`getter(a, reg_a_q, [7:0]);
`getter(x, reg_x_q, [7:0]);
`getter(y, reg_y_q, [7:0]);
`getter(sp, sp_q, [7:0]);
`getter(status, status_q, [7:0]);

// ALU signals
logic [7:0] alu_a, alu_b, alu_res;
alu_op_e alu_op;
logic alu_cin, alu_flag_o, alu_flag_c;

alu i_alu (
    .a_i(alu_a),
    .b_i(alu_b),
    .op_i(alu_op),
    .carry_i(alu_cin),
    .res_o(alu_res),
    .overflow_o(alu_flag_o),
    .carry_o(alu_flag_c)
);

// Interrupt signals
logic nmi_q, nmi_active;
cpu_interrupt_type_e int_type_q, int_type_d;

always_comb begin : int_type_logic
    int_type_d = int_type_q;
    if (nmi_active) begin
        int_type_d = IntNMI;
    end
end

// Phase 1 logic signals
logic bus_rw_q, bus_rw_d;
logic [15:0] bus_address_q, bus_address_d;
logic [7:0] curr_opcode_q, curr_opcode_d;
logic [15:0] tmp_store_q, tmp_store_d; // Register used for various temporaries
logic eah_invalid_q, eah_invalid_d;
assign bus_rw_o = bus_rw_q;
assign bus_address_o = bus_address_q;

// Phase 2 logic signals
logic [7:0] bus_data_o_q, bus_data_o_d, bus_data_phi2_o;
assign bus_data_o = bus_data_phi2_o;

// OAM DMA
logic oam_dma_active_q, oam_dma_active_d;
logic [7:0] oam_dma_page_q, oam_dma_page_d;
logic [7:0] oam_dma_count_q, oam_dma_count_d;
logic oam_dma_is_read;
logic oam_dma_delay;
logic [15:0] oam_dma_curr_addr;

// TODO: cleanup
always_comb begin : oam_dma_logic
    oam_dma_page_d = oam_dma_page_q;
    oam_dma_delay = '0;
    if (oam_dma_is_read) begin
        oam_dma_curr_addr = {oam_dma_page_q, oam_dma_count_q};
    end else begin
        oam_dma_curr_addr = 16'h2004;
    end
    if (oam_dma_active_q) begin
        if (oam_dma_is_read) begin
            oam_dma_active_d = 1'h1;
            oam_dma_count_d = oam_dma_count_q;
        end else begin
            oam_dma_active_d = oam_dma_count_q != 8'hFF;
            oam_dma_count_d = oam_dma_count_q + 8'h1;
        end
    end else if (bus_address_d == 16'h4014 && bus_rw_d) begin
        if (oam_dma_is_read) begin
            oam_dma_delay = 1'h1;
            oam_dma_active_d = 1'h0;
        end else begin
            oam_dma_delay = 1'h0;
            oam_dma_active_d = 1'h1;
        end
        oam_dma_count_d = '0;
        oam_dma_page_d = bus_data_o;
    end else begin
        oam_dma_active_d = '0;
        oam_dma_count_d = '0;
    end
end

cpu6502_control i_cpu6502_control (
    .state_i(state_q),
    .state_o(state_d),

    .bus_address_i(bus_address_q),
    .bus_address_o(bus_address_d),
    .bus_data_i(bus_data_i),
    .bus_data_o(bus_data_o_d),
    .bus_rw_o(bus_rw_d),

    .pc_i(pc_q),
    .pc_o(pc_d),
    .curr_opcode_i(curr_opcode_q),
    .curr_opcode_o(curr_opcode_d),

    .tmp_store_i(tmp_store_q),
    .tmp_store_o(tmp_store_d),
    .eah_invalid_i(eah_invalid_q),
    .eah_invalid_o(eah_invalid_d),

    .alu_a_o(alu_a),
    .alu_b_o(alu_b),
    .alu_op_o(alu_op),
    .alu_carry_o(alu_cin),
    .alu_res_i(alu_res),
    .alu_overflow_i(alu_flag_o),
    .alu_carry_i(alu_flag_c),

    .reg_a_i(reg_a_q),
    .reg_a_o(reg_a_d),
    .reg_x_i(reg_x_q),
    .reg_x_o(reg_x_d),
    .reg_y_i(reg_y_q),
    .reg_y_o(reg_y_d),
    .sp_i(sp_q),
    .sp_o(sp_d),
    .status_i(status_q),
    .status_o(status_d),

    .int_type(int_type_d)
);

always_ff @(posedge phi1 or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= CpuBrk1;

        pc_q <= '0;
        curr_opcode_q <= '0;

        reg_a_q  <= '0;
        reg_x_q  <= '0;
        reg_y_q  <= '0;
        status_q <= '0;
        sp_q     <= '0;

        bus_rw_q <= '0;
        bus_address_q <= '0;
        bus_data_o_q <= '0;

        tmp_store_q <= '0;
        eah_invalid_q <= '0;

        int_type_q <= IntReset;
        nmi_q <= '0;
        nmi_active <= '0;

        oam_dma_is_read <= '0;
        oam_dma_active_q <= '0;
        oam_dma_count_q <= '0;
        oam_dma_page_q <= '0;
    end else begin
        if (!oam_dma_active_q && !oam_dma_delay) begin
            if (state_d == CpuReadOpcode && nmi_active) begin
                state_q <= CpuBrk1;
            end else begin
                state_q <= state_d;
            end

            pc_q <= pc_d;
            curr_opcode_q <= curr_opcode_d;

            reg_a_q  <= reg_a_d;
            reg_x_q  <= reg_x_d;
            reg_y_q  <= reg_y_d;
            status_q <= status_d;
            sp_q     <= sp_d;

            bus_rw_q <= bus_rw_d;
            bus_address_q <= bus_address_d;
            bus_data_o_q <= bus_data_o_d;

            tmp_store_q <= tmp_store_d;
            eah_invalid_q <= eah_invalid_d;

            int_type_q <= int_type_d;
            nmi_q <= nmi_i;
            if (state_d == CpuBrk7) begin
                nmi_active <= 1'b0;
            end else if (nmi_i && !nmi_q) begin
                nmi_active <= 1'b1;
            end
        end else if (oam_dma_delay) begin
            bus_rw_q <= '0;
            bus_address_q <= 16'h4014;
        end else begin
            bus_rw_q <= !oam_dma_is_read;
            bus_address_q <= oam_dma_curr_addr;
            bus_data_o_q <= bus_data_i;
        end

        oam_dma_is_read <= !oam_dma_is_read;
        oam_dma_active_q <= oam_dma_active_d;
        oam_dma_count_q <= oam_dma_count_d;
        oam_dma_page_q <= oam_dma_page_d;
    end
end

always_ff @(posedge phi2) begin
    bus_data_phi2_o <= bus_data_o_q;
end

endmodule
