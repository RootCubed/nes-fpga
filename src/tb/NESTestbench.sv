`timescale 1ns / 1ps

// Simple testbench module.

module NESTestbench;
wire [11:0] rgb_out;
wire hsync;
wire vsync;

reg reset = 0;

reg clkMaster = 0;
reg clkVGA = 0;

parameter PERIOD_MASTER = 46.56179775280899; // 46.56084813; // 1 / 21.47727
parameter PERIOD_VGA = 39.79775280898877; //39.80099502;    // 1 / 25.125

always #PERIOD_MASTER clkMaster = ~clkMaster;
always #PERIOD_VGA    clkVGA    = ~clkVGA;

initial begin
    $dumpfile("NESTestbench.fst");
    $dumpvars();
    $dumpvars(0, nes.ppu.sprite_x_pos[0]);
    $dumpvars(0, nes.ppu.sprite_attr[0]);
    $dumpvars(0, nes.ppu.sprite_pattern_d_hi[0]);
    $dumpvars(0, nes.ppu.sprite_pattern_d_lo[0]);
end

reg [7:0] controller = 0;

always #100000000 begin
    $finish;
end

always @ (posedge nes.cpu.phi0) begin
    if (nes.cpu.state == 2) begin // ST_READ_OPCODE
        $display("%04x  %02x A:%02x X:%02x Y:%02x P:%02x SP:%02x", nes.cpu.pc, nes.cpu.data_in, nes.cpu.acc, nes.cpu.reg_x, nes.cpu.reg_y, nes.cpu.ps, nes.cpu.sp);
    end
end

reg [4:0] countHalt = 0;

always @ (posedge clkMaster) begin
    if (nes.cpu.state == 'h7F) countHalt = countHalt + 1;
    if (countHalt > 20) begin
        $display("%x, %x", nes.wram['h0002], nes.wram['h0003]);
        $finish;
    end
end

NESMain nes(
    .clkMaster(clkMaster),
    .clkVGA(clkVGA),
    .rgb_out(rgb_out),
    .hsync(hsync),
    .vsync(vsync),
    .rst(reset),
    .ctrl1(controller)
);

endmodule