//
// Vector-06C display implementation
// 
// Copyright (c) 2016 Sorgelig
//
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//


`timescale 1ns / 1ps

module video
(
	input         reset,

	// Clocks
	input         clk_sys,
	input         ce_12mp,
	input         ce_12mn,
	output        ce_pix,

	// Video outputs
	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_VS,
	output        VGA_HS,
	output        VGA_DE,
	
	// TV/VGA
	input         scandoubler,
	input         hq2x,
	inout  [21:0] gamma_bus,

	// Video memory
	output [12:0] vaddr,
	input	 [31:0] vdata,

	// CPU bus
	input  [7:0]  din,
	input         io_we,
	
	// Misc signals
	input   [7:0] scroll,
	input   [3:0] border,
	input         mode512,
	output reg    retrace
);

assign     retrace = VSync;
assign     vaddr   = {hc[8:4], ~vcr[7:0]};

reg  [9:0] hc;
reg  [8:0] vc;
wire [8:0] vcr = vc + ~roll;
reg  [7:0] roll;
reg        HBlank, HSync;
reg        VBlank, VSync;
reg        viden, dot;
reg  [7:0] idx0, idx1, idx2, idx3;

reg mode512_lock;

always @(posedge clk_sys) begin
	reg [7:0] border_d;
	reg       mode512_acc; 

	if(ce_12mp) begin
		if(hc == 767) begin
			hc <=0;
			if (vc == 311) vc <= 9'd0;
				else vc <= vc + 1'd1;
			if(vc == 271) begin
				mode512_lock <= (mode512_acc | ~hq2x);
				mode512_acc  <= 0;
			end
		end else begin
			hc <= hc + 1'd1;
		end

		if((vc == 311) && (hc == 759)) roll <= scroll;
		if(hc == 563) begin
			HBlank <= 1;
			if(vc == 267) VBlank <= 1;
		end
		if(hc == 597) begin
			HSync <= 1;
			if(vc == 271) VSync <= 1;
			if(vc == 281) VSync <= 0;
		end
		if(hc == 653) HSync <= 0;
		if(hc == 723) begin
			HBlank <= 0;
			if(vc == 295) VBlank <= 0;
		end
	end

	if(ce_12mn) begin
		if(hc[0]) begin
			idx0 <= {idx0[6:0], border_d[4]};
			idx1 <= {idx1[6:0], border_d[5]};
			idx2 <= {idx2[6:0], border_d[6]};
			idx3 <= {idx3[6:0], border_d[7]};
			if((hc[3:1] == 2) & ~hc[9] & ~vc[8]) {idx0, idx1, idx2, idx3} <= vdata;

			border_d <= {border_d[3:0], border};
		end

		dot   <= ~hc[0];
		viden <= ~HBlank & ~VBlank;
		if(~HBlank & ~VBlank) mode512_acc <= mode512_acc | mode512;
	end
end

reg  [7:0] palette[16];
wire [3:0] color_idx = {{2{~(mode512 & ~dot)}} & {idx3[7], idx2[7]}, {2{~(mode512 & dot)}} & {idx1[7], idx0[7]}};

always @(posedge clk_sys) begin
	reg old_we;
	old_we <= io_we;

	if(reset) begin
		palette[0]  <= ~8'b11111111;
		palette[1]  <= ~8'b01010101;
		palette[2]  <= ~8'b11010111;
		palette[3]  <= ~8'b10000111;
		palette[4]  <= ~8'b11101010;
		palette[5]  <= ~8'b01101000;
		palette[6]  <= ~8'b11010000;
		palette[7]  <= ~8'b11000000;
		palette[8]  <= ~8'b10111101;
		palette[9]  <= ~8'b01111010;
		palette[10] <= ~8'b11000111;
		palette[11] <= ~8'b00111111;
		palette[12] <= ~8'b11101000;
		palette[13] <= ~8'b11010010;
		palette[14] <= ~8'b10010000;
		palette[15] <= ~8'b00000010;
	end else if(~old_we & io_we) begin
		palette[color_idx] <= din;
	end
end

wire [3:0] R = {4{viden}} & {palette[color_idx][2:0], palette[color_idx][2]};
wire [3:0] G = {4{viden}} & {palette[color_idx][5:3], palette[color_idx][5]};
wire [3:0] B = {4{viden}} & {palette[color_idx][7:6], palette[color_idx][7:6]};

video_mixer #(.LINE_LENGTH(768), .HALF_DEPTH(1), .GAMMA(1)) video_mixer
(
	.*,

	.clk_vid(clk_sys),
	.ce_pix(ce_12mp & (mode512_lock | ~dot)),
	.ce_pix_out(ce_pix),

	.scanlines(0),
	.mono(0)
);

endmodule
