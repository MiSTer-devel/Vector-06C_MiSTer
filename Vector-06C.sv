// ====================================================================
//                Vector 06C FPGA REPLICA
//
//            Copyright (C) 2016-2017 Sorgelig
//
// This core is distributed under modified BSD license. 
// For complete licensing information see LICENSE.TXT.
// -------------------------------------------------------------------- 
//
// An open implementation of Vector 06C home computer
//
// Based on code from Dmitry Tselikov and Viacheslav Slavinsky
// 

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [37:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status ORed with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	input         TAPE_IN,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE
);

assign AUDIO_S   = 0;

assign LED_USER  = ioctl_download | ioctl_erasing;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = status[8] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[8] ? 8'd9  : 8'd3;
assign CLK_VIDEO = clk_sys;

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;


`include "build_id.v"
localparam CONF_STR =
{
	"VECTOR06;;",
	"-;",
	"F0,ROMCOMC00EDD;",
	"S3,FDD,Mount Floppy;",
	"-;",
	"O8,Aspect ratio,4:3,16:9;",
	"O12,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"O7,Reset Palette,Yes,No;",
	"-;",
	"O4,CPU Speed,3MHz,6MHz;",
	"O5,CPU Type,i8080,Z80;",
	"-;",
	"T6,Cold Reboot;",
	"V0,v2.51.",`BUILD_DATE
};


///////////////   MIST ARM I/O   /////////////////
wire        forced_scandoubler;
wire        ps2_kbd_clk, ps2_kbd_data;

wire [31:0] status;
wire  [1:0] buttons;
wire  [7:0] joyA;
wire  [7:0] joyB;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;
wire        ioctl_download;
wire        ioctl_erasing;
wire  [7:0] ioctl_index;

wire [31:0] sd_lba;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire [63:0] img_size;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io 
(
	.*,

	.conf_str(CONF_STR),
	.sd_conf(0),

	.joystick_0(joyA),
	.joystick_1(joyB),

	.ioctl_force_erase(cold_reset),
	.ioctl_dout(ioctl_data),

	// unused
	.sd_ack_conf(),

	.joystick_analog_0(),
	.joystick_analog_1(),

	.ps2_kbd_led_use(0),
	.ps2_kbd_led_status(0),
	.ps2_mouse_clk(),
	.ps2_mouse_data()
);


////////////////////   CLOCKS   ///////////////////
wire locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(SDRAM_CLK),
	.locked(locked)
);

wire clk_sys;      // 96MHz
reg  ce_f1, ce_f2; // 3MHz/6MHz
reg  ce_12mp;
reg  ce_12mn;
reg  ce_psg;       // 1.75MHz
reg  clk_pit;      // 1.5MHz

always @(negedge clk_sys) begin
	reg [6:0] div = 0;
	reg [5:0] psg_div = 0;
	reg       turbo;

	div <= div + 1'd1;

	if(&div) turbo <= status[4];
	if(turbo) begin
		ce_f1 <= !div[3] & !div[2:0];
		ce_f2 <=  div[3] & !div[2:0];
		cpu_ready <= 1;
	end else begin
		ce_f1 <= !div[4] & !div[3:0];
		ce_f2 <=  div[4] & !div[3:0];
		if(div[6:4]==3'b100) cpu_ready <= 1;
			else if(!div[4:2] & cpu_sync & mreq) cpu_ready <= 0;
	end
	
	ce_12mp <= !div[2] & !div[1:0];
	ce_12mn <=  div[2] & !div[1:0];

	psg_div <= psg_div + 1'b1;
	if(psg_div == 54) psg_div <= 0;
	ce_psg <= !psg_div;

	clk_pit <= div[5];
end


////////////////////   RESET   ////////////////////
reg cold_reset;
reg reset;
reg rom_enable;

always @(posedge clk_sys) begin
	reg reset_flg  = 1;
	int reset_hold = 0;
	int init_reset = 90000000;

	if(ioctl_erasing | ioctl_download) begin
		reset_flg <= 1;
		reset     <= 1;
		if(ioctl_download) rom_enable <= ~((ioctl_index[4:0]==1) && (ioctl_index[7:6]<3));
	end else begin
		if(reset_flg) begin
			reset_flg  <= 0;
			cpu_type   <= status[5];
			reset      <= 1;
			reset_hold <= 1000;
		end else if(reset_hold) reset_hold <= reset_hold - 1;
		else {cold_reset,reset} <= 0;

		// initial reset
		if(init_reset) begin
			init_reset <= init_reset - 1;
			reset_flg  <= 1;
			rom_enable <= 1;
			cold_reset <= 1;
		end
		
		// reset by button or key
		if(status[6] | buttons[1] | reset_key[0] | (fdd_busy & rom_enable)) begin
			rom_enable <= ~reset_key[2]; // disable boot rom if Alt is held.
			reset_flg  <= 1;

			cold_reset <= status[6];
		end
	end

	if(cpu_type != status[5]) reset_flg <= 1;
end


////////////////////   CPU   ////////////////////
wire [15:0] addr     = cpu_type ? addr_z80     : addr_i80;
reg   [7:0] cpu_i;
wire  [7:0] cpu_o    = cpu_type ? cpu_o_z80    : cpu_o_i80;
wire        cpu_sync = cpu_type ? cpu_sync_z80 : cpu_sync_i80;
wire        cpu_rd   = cpu_type ? cpu_rd_z80   : cpu_rd_i80;
wire        cpu_wr_n = cpu_type ? cpu_wr_n_z80 : cpu_wr_n_i80;
reg         cpu_ready;

reg         cpu_type = 0;

reg   [7:0] status_word;
always @(posedge clk_sys) begin
	reg old_sync;
	old_sync <= cpu_sync;
	if(~old_sync & cpu_sync) status_word <= cpu_o;
end

wire int_ack  = status_word[0];
wire write_n  = status_word[1];
wire io_stack = status_word[2];
//wire halt_ack = status_word[3];
wire io_write = status_word[4];
//wire m1       = status_word[5];
wire io_read  = status_word[6];
wire ram_read = status_word[7];

wire mreq = (ram_read | ~write_n) & ~io_write & ~io_read;

reg ppi1_sel, joy_sel, vox_sel, pit_sel, pal_sel, psg_sel, edsk_sel, fdd_sel;

reg [7:0] io_data;
always_comb begin
	ppi1_sel =0;
	joy_sel  =0;
	vox_sel  =0;
	pit_sel  =0;
	pal_sel  =0;
	edsk_sel =0;
	psg_sel  =0;
	fdd_sel  =0;
	io_data  =255;
	casex(addr[7:0])
		8'b000000XX: begin ppi1_sel =1; io_data = ppi1_o;  end
		8'b0000010X: begin joy_sel  =1; io_data = 0;       end 
		8'b00000110: begin              io_data = joyP_o;  end
		8'b00000111: begin vox_sel  =1; io_data = joyPU_o; end
		8'b000010XX: begin pit_sel  =1; io_data = pit_o;   end
		8'b0000110X: begin pal_sel  =1;                    end
		8'b00001110: begin pal_sel  =1; io_data = joyA_o;  end
		8'b00001111: begin pal_sel  =1; io_data = joyB_o;  end
		8'b00010000: begin edsk_sel =1;                    end
		8'b0001010X: begin psg_sel  =1; io_data = psg_o;   end
		8'b000110XX: begin fdd_sel  =fdd_ready; if(fdd_ready) io_data = fdd_o; end
		8'b000111XX: begin fdd_sel  =fdd_ready;            end
		    default: ;
	endcase
end

always_comb begin
	casex({int_ack, io_read, rom_enable && !rom_size && !ed_page && !addr[15:11]})
		 3'b001: cpu_i = rom_o;
		 3'b01X: cpu_i = io_data;
		 3'b1XX: cpu_i = 255;
		default: cpu_i = ram_o;
	endcase
end

wire io_rd = io_read  & cpu_rd;
wire io_wr = io_write & ~cpu_wr_n;

wire [15:0] addr_i80;
wire  [7:0] cpu_o_i80;
wire        cpu_inte_i80;
wire        cpu_sync_i80;
wire        cpu_rd_i80;
wire        cpu_wr_n_i80;
reg         cpu_int_i80;

k580vm80a cpu_i80
(
   .pin_clk(clk_sys),
   .pin_f1(ce_f1),
   .pin_f2(ce_f2),
   .pin_reset(reset | cpu_type),
   .pin_a(addr_i80),
   .pin_dout(cpu_o_i80),
   .pin_din(cpu_i),
   .pin_hold(0),
   .pin_ready(cpu_ready),
   .pin_int(cpu_int_i80),
   .pin_inte(cpu_inte_i80),
   .pin_sync(cpu_sync_i80),
   .pin_dbin(cpu_rd_i80),
   .pin_wr_n(cpu_wr_n_i80)
);

wire [15:0] addr_z80;
wire  [7:0] cpu_o_z80;
wire        cpu_inte_z80;
wire        cpu_sync_z80;
wire        cpu_rd_z80;
wire        cpu_wr_n_z80;
reg         cpu_int_z80;

T8080se cpu_z80
(
	.CLK(clk_sys),
	.CLKEN(ce_f1),
	.RESET_n(~reset & cpu_type),
	.A(addr_z80),
	.DO(cpu_o_z80),
	.DI(cpu_i),
	.HOLD(0),
	.READY(cpu_ready),
	.INT(cpu_int_z80),
	.INTE(cpu_inte_z80),
	.SYNC(cpu_sync_z80),
	.DBIN(cpu_rd_z80),
	.WR_n(cpu_wr_n_z80)
);


////////////////////   MEM   ////////////////////
wire  [7:0] ram_o;
sdram ram
( 
	.*,
	.init(!locked),
	.clk_sdram(clk_sys),
	.dout(ram_o),
	.din( (ioctl_download | ioctl_erasing) ? ioctl_data : cpu_o),
	.addr((ioctl_download | ioctl_erasing) ? ioctl_addr : {read_rom, ed_page, addr}),
	.we(  (ioctl_download | ioctl_erasing) ? ioctl_wr   : ~cpu_wr_n & ~io_write),
	.rd(  (ioctl_download | ioctl_erasing) ? 1'b0       : cpu_rd),
	.ready()
);

reg  [15:0] rom_size = 0;
wire read_rom = rom_enable && (addr<rom_size) && !ed_page && ram_read;
always @(posedge clk_sys) begin
	reg old_download;

	old_download <= ioctl_download;
	if(~ioctl_download & old_download & !ioctl_index) rom_size <= ioctl_addr[15:0] + 1'b1;
end

wire [7:0] rom_o;
bios rom(.address(addr[10:0]), .clock(clk_sys), .q(rom_o));


/////////////////  E-DISK 256KB  ///////////////////
reg  [2:0] ed_page;
reg  [7:0] ed_reg;

wire edsk_we = io_wr & edsk_sel;
always @(posedge clk_sys) begin
	reg old_we;

	old_we <= edsk_we;
	if(reset) ed_reg <= 0;
		else if(~old_we & edsk_we) ed_reg <= cpu_o;
end

wire ed_win   = addr[15] & ((addr[13] ^ addr[14]) | (ed_reg[7] & addr[13] & addr[14]) | (ed_reg[6] & ~addr[13] & ~addr[14]));
wire ed_ram   = ed_reg[5] & ed_win   & (ram_read | ~write_n);
wire ed_stack = ed_reg[4] & io_stack & (ram_read | ~write_n);

always_comb begin
	casex({ed_stack, ed_ram, ed_reg[3:0]})
		6'b1X00XX, 6'b01XX00: ed_page = 1;
		6'b1X01XX, 6'b01XX01: ed_page = 2;
		6'b1X10XX, 6'b01XX10: ed_page = 3;
		6'b1X11XX, 6'b01XX11: ed_page = 4;
		             default: ed_page = 0;
	endcase
end


/////////////////////   FDD   /////////////////////
wire  [7:0] fdd_o;
reg         fdd_drive;
reg         fdd_ready;
reg         fdd_side;
wire        fdd_busy;

always @(posedge clk_sys) begin
	reg old_mounted, old_wr;

	old_mounted <= img_mounted;
	if(cold_reset) fdd_ready <= 0;
		else if(~old_mounted & img_mounted) fdd_ready <= 1;

	old_wr <= io_wr;
	if(~old_wr & io_wr & fdd_sel & addr[2]) {fdd_side, fdd_drive} <= {~cpu_o[2], cpu_o[0]};
end

wd1793 #(1) fdd
(
	.clk_sys(clk_sys),
	.ce(ce_f1),
	.reset(reset),
	.io_en(fdd_sel & ~addr[2]),
	.rd(io_rd),
	.wr(io_wr),
	.addr(~addr[1:0]),
	.din(cpu_o),
	.dout(fdd_o),

	.img_mounted(img_mounted),
	.img_size(img_size[31:0]),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.wp(0),

	.size_code(3),
	.layout(0),
	.side(fdd_side),
	.ready(!fdd_drive & fdd_ready),
	.prepare(fdd_busy),

	.input_active(0),
	.input_addr(0),
	.input_data(0),
	.input_wr(0),
	.buff_din(0)
);


////////////////////   VIDEO   ////////////////////
wire retrace;

video video
(
	.*,
	.ce_pix(CE_PIXEL),
	.reset(reset & ~status[7]),
	.addr(addr),
	.din(cpu_o),
	.we(~cpu_wr_n && ~io_write && !ed_page),
	
	.scroll(ppi1_a),
	.io_we(pal_sel & io_wr),
	.border(ppi1_b[3:0]),
	.mode512(ppi1_b[4]),
	.scale(status[2:1]),
	.retrace(retrace)
);

always @(posedge clk_sys) begin
	reg old_retrace;
	int z80_delay;
	old_retrace <= retrace;
	
	if(!cpu_inte_i80) cpu_int_i80 <= 0;
		else if(~old_retrace & retrace) cpu_int_i80 <= 1;

	if(!cpu_inte_z80) {z80_delay,cpu_int_z80} <= 0;
	else begin
		if(~old_retrace & retrace) z80_delay <= 1;
		if(ce_12mp && z80_delay) z80_delay <= z80_delay + 1;
		if(z80_delay == 700) begin
			z80_delay   <= 0;
			cpu_int_z80 <= 1;
		end
	end
end


/////////////////////   KBD   /////////////////////
wire [7:0] kbd_o;
wire [2:0] kbd_shift;
wire [2:0] reset_key;

keyboard kbd
(
	.clk(clk_sys), 
	.reset(cold_reset),
	.ps2_clk(ps2_kbd_clk),
	.ps2_dat(ps2_kbd_data),
	.addr(~ppi1_a), 
	.odata(kbd_o), 
	.shift(kbd_shift),
	.reset_key(reset_key)
);


/////////////////   PPI1 (SYS)   //////////////////
wire [7:0] ppi1_o;
wire [7:0] ppi1_a;
wire [7:0] ppi1_b;
wire [7:0] ppi1_c;

k580vv55 ppi1
(
	.clk_sys(clk_sys),
	.reset(0),
	.addr(~addr[1:0]),
	.we_n(~(io_wr & ppi1_sel)),
	.idata(cpu_o),
	.odata(ppi1_o),
	.opa(ppi1_a),
	.ipb(~kbd_o),
	.opb(ppi1_b),
	.ipc({~kbd_shift,tapein,4'b1111}),
	.opc(ppi1_c)
);


/////////////////   Joystick Zoo   /////////////////
wire [7:0] joyPU   = joyA | joyB;
wire [7:0] joyPU_o = {joyPU[3], joyPU[0], joyPU[2], joyPU[1], joyPU[4], joyPU[5], 2'b00};

wire [7:0] joyA_o  = ~{joyA[5], joyA[4], 2'b00, joyA[2], joyA[3], joyA[1], joyA[0]};
wire [7:0] joyB_o  = ~{joyB[5], joyB[4], 2'b00, joyB[2], joyB[3], joyB[1], joyB[0]};

reg  [7:0] joy_port;
wire       joy_we = io_wr & joy_sel;

always @(posedge clk_sys) begin
	reg old_we;
	
	old_we <= joy_we;
	if(reset) joy_port <= 0;
	else if(~old_we & joy_we) begin
		if(addr[0]) joy_port <= cpu_o;
			else if(!cpu_o[7]) joy_port[cpu_o[3:1]] <= cpu_o[0];
	end
end

reg  [7:0] joyP_o;
always_comb begin
	case(joy_port[6:5]) 
		2'b00: joyP_o = joyA_o & joyB_o;
		2'b01: joyP_o = joyA_o;
		2'b10: joyP_o = joyB_o;
		2'b11: joyP_o = 255;
	endcase
end


////////////////////   SOUND   ////////////////////
wire       tapein = 0;

wire [7:0] pit_o;
wire [2:0] pit_out;
wire [2:0] pit_active;
wire [2:0] pit_snd = pit_out & pit_active;

k580vi53 pit
(
	.reset(reset),
	.clk_sys(clk_sys),
	.clk_timer({clk_pit,clk_pit,clk_pit}),
	.addr(~addr[1:0]),
	.wr(io_wr & pit_sel),
	.rd(io_rd & pit_sel),
	.din(cpu_o),
	.dout(pit_o),
	.gate(3'b111),
	.out(pit_out),
	.sound_active(pit_active)
);

wire [1:0] legacy_audio = 2'd0 + ppi1_c[0] + pit_snd[0] + pit_snd[1] + pit_snd[2];

wire [7:0] psg_o;
wire [7:0] psg_ch_a;
wire [7:0] psg_ch_b;
wire [7:0] psg_ch_c;
wire [5:0] psg_active;

ym2149 ym2149
(
	.CLK(clk_sys),
	.CE(ce_psg),
	.RESET(reset),
	.BDIR(io_wr & psg_sel),
	.BC(addr[0]),
	.DI(cpu_o),
	.DO(psg_o),
	.CHANNEL_A(psg_ch_a),
	.CHANNEL_B(psg_ch_b),
	.CHANNEL_C(psg_ch_c),
	.ACTIVE(psg_active),
	.SEL(0),
	.MODE(0)
);

reg  [7:0] covox;
integer    covox_timeout;
wire       vox_we = io_wr & vox_sel & !covox_timeout;

always @(posedge clk_sys) begin
	reg old_we;
	
	if(reset | rom_enable) covox_timeout <= 200000000;
		else if(covox_timeout) covox_timeout <= covox_timeout - 1;

	old_we <= vox_we;
	if(reset) covox <= 0;
		else if(~old_we & vox_we) covox <= cpu_o;
end

assign AUDIO_L = {psg_active ? {1'b0, psg_ch_a, 1'b0} + {2'b00, psg_ch_b} + {1'b0, legacy_audio, 7'd0} : {1'b0, legacy_audio, 8'd0} + {1'b0, covox, 1'b0}, 5'd0};
assign AUDIO_R = {psg_active ? {1'b0, psg_ch_c, 1'b0} + {2'b00, psg_ch_b} + {1'b0, legacy_audio, 7'd0} : {1'b0, legacy_audio, 8'd0} + {1'b0, covox, 1'b0}, 5'd0};

endmodule