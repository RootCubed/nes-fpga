`timescale 1ns / 1ps

// Module for controlling the memory-mapped registers such as DMA access and controllers.

module MemMapRegs(
    input [4:0] addr,
    input [7:0] data_in,
    output reg [7:0] data_out = 0,
    input is_active,
    input is_read,
    input [7:0] controller1,
    input [7:0] controller2,
    output reg activate_dma = 0,
    input clk
);

reg controller_port_latch = 0;

reg [7:0] controller1_latch = 7'b1111111;
reg [7:0] controller2_latch = 7'b1111111;

reg [4:0] del_addr = 0;

always @ (negedge clk) begin
    del_addr <= addr;
    if (addr != del_addr) begin
        activate_dma <= 0;
        if (is_active && is_read) begin
            case (addr)
                'h16: begin
                    data_out[0] <= controller1_latch[0];
                    controller1_latch <= {1'b1, controller1_latch[7:1]};
                end
                'h17: begin
                    data_out[0] <= controller2_latch[0];
                    controller2_latch <= {1'b1, controller2_latch[7:1]};
                end
            endcase
        end else if (is_active) begin
            case (addr)
                'h14: begin
                    activate_dma <= 1;
                end
                'h16: begin
                    controller_port_latch <= data_in[0];
                    controller1_latch <= controller1;
                    controller2_latch <= controller2;
                end
            endcase
        end
    end
    if (controller_port_latch) begin
        controller1_latch <= controller1;
        controller2_latch <= controller2;
    end
end

endmodule