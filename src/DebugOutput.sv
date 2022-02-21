`timescale 1ns / 1ps

// Outputs a 16-bit number to the 7-segment display and another one to the LEDs.

module DebugOutput(
    input clk,
    input [15:0] number_in,
    output reg [7:0] sevenseg_out,
    output reg [3:0] sevseg_active = 4'b1110
);

wire [3:0] nybble;

reg [7:0] count = 0;

assign nybble =
    (sevseg_active == 4'b1110) ? number_in[3:0] :
    (sevseg_active == 4'b1101) ? number_in[7:4] :
    (sevseg_active == 4'b1011) ? number_in[11:8] :
    (sevseg_active == 4'b0111) ? number_in[15:12] : 0;

always @(posedge clk) begin
    case (nybble)
        'h0: sevenseg_out <= 8'b1_000_0001;
        'h1: sevenseg_out <= 8'b1_100_1111;
        'h2: sevenseg_out <= 8'b1_001_0010;
        'h3: sevenseg_out <= 8'b1_000_0110;
        'h4: sevenseg_out <= 8'b1_100_1100;
        'h5: sevenseg_out <= 8'b1_010_0100;
        'h6: sevenseg_out <= 8'b1_010_0000;
        'h7: sevenseg_out <= 8'b1_000_1111;
        'h8: sevenseg_out <= 8'b1_000_0000;
        'h9: sevenseg_out <= 8'b1_000_0100;
        'hA: sevenseg_out <= 8'b1_000_1000;
        'hB: sevenseg_out <= 8'b1_110_0000;
        'hC: sevenseg_out <= 8'b1_011_0001;
        'hD: sevenseg_out <= 8'b1_100_0010;
        'hE: sevenseg_out <= 8'b1_011_0000;
        'hF: sevenseg_out <= 8'b1_011_1000;
    endcase
    if (count == 200) begin
        count = 0;
        sevseg_active <= (sevseg_active == 4'b0111) ? 4'b1110 : {sevseg_active[2:0], 1'b1};
    end else begin
        count = count + 1;
    end
end

endmodule
