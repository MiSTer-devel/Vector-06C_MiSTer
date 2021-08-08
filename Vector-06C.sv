// ====================================================================
//                Vector 06C FPGA REPLICA
//
//            Copyright (C) 2016-2019 Sorgelig
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
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

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
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign AUDIO_S   = 0;
assign AUDIO_MIX = status[10:9];

assign LED_USER  = ioctl_download | erasing;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;
assign HDMI_FREEZE = 0;

wire [1:0] ar = status[12:11];
wire       vcrop_en = status[15];
reg        en270p;
always @(posedge CLK_VIDEO) begin
	en270p <= ((HDMI_WIDTH == 1920) && (HDMI_HEIGHT == 1080) && !forced_scandoubler && !scale);
end

wire vga_de;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de),
	.ARX((!ar) ? 12'd4 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE((en270p & vcrop_en) ? 10'd270 : 10'd0),
	.CROP_OFF(0),
	.SCALE(status[14:13])
);

assign CLK_VIDEO = clk_sys;

`include "build_id.v"
localparam CONF_STR =
{
	"VECTOR06;;",
	"-;",
	"F,ROMCOMC00EDD;",
	"-;",
	"S0,FDD,Mount Disk A;",
	"S1,FDD,Mount Disk B;",
	"-;",
	"OBC,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O12,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"O7,Reset Palette,Yes,No;",
	"-;",
	"d0OF,Vertical Crop,Disabled,270p(5x);",
	"ODE,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"-;",
	"O9A,Stereo mix,none,25%,50%,100%;",
	"-;",
	"O4,CPU Speed,3MHz,6MHz;",
	"O5,CPU Type,i8080,Z80;",
	"-;",
	"R6,Cold Reboot;",
	"J,Fire 1,Fire 2;",
	"V,v",`BUILD_DATE
};


///////////////   HPS I/O   /////////////////
wire        forced_scandoubler;
wire [10:0] ps2_key;
wire [21:0] gamma_bus;

wire [31:0] status;
wire  [1:0] buttons;
wire [15:0] joyA;
wire [15:0] joyB;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [24:0] ioctl_addr_orig;
wire  [7:0] ioctl_data;
wire        ioctl_download;
wire  [7:0] ioctl_index;

wire [31:0] sd_lba[2];
wire  [1:0] sd_rd;
wire  [1:0] sd_wr;
wire  [1:0] sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[2];
wire        sd_buff_wr;
wire  [1:0] img_mounted;
wire [63:0] img_size;
wire        img_readonly;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(2)) hps_io 
(
	.clk_sys(clk_sys),

	.HPS_BUS(HPS_BUS),
	
	.ps2_key(ps2_key),
	.joystick_0(joyA),
	.joystick_1(joyB),
	.gamma_bus(gamma_bus),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),
	.status(status),
	.status_menumask({en270p}), 

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr_orig),
	.ioctl_dout(ioctl_data),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index)  
);

////////////////////   CLOCKS   ///////////////////
wire locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
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
reg cold_reset = 0;
reg reset;
reg rom_enable;

always @(posedge clk_sys) begin
	reg reset_flg  = 1;
	int reset_hold = 0;
	reg old_rst = 0;
	
	// initial reset
	old_rst <= status[0];
	if(old_rst & ~status[0]) begin
		reset_flg  <= 1;
		rom_enable <= 1;
		cold_reset <= 1;
	end

	if(erasing | ioctl_download) begin
		reset_flg <= 1;
		reset     <= 1;
		if(ioctl_download) rom_enable <= ~((ioctl_index[4:0]==1) && (ioctl_index[7:6]<3));
	end else begin
		if(reset_flg) begin
			reset_flg  <= 0;
			cpu_type   <= status[5];
			reset      <= 1;
			reset_hold <= 10000;
		end else if(reset_hold) reset_hold <= reset_hold - 1;
		else {cold_reset,reset} <= 0;

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
		8'b000110XX: begin fdd_sel  =1; io_data = fdd_o;   end
		8'b000111XX: begin fdd_sel  =1;                    end
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
wire [18:0] ram_addr = ioctl_download ? ioctl_addr[18:0] : erasing ? erase_addr[18:0] : {read_rom ? 3'h5 : ed_page, addr};

dpram #(8, 19, 393216, 32, 17, 98304) ram
(
	.clock(clk_sys),

	.address_a({ram_addr[18:15], ram_addr[12:0], ram_addr[14:13]}),
	.data_a(ioctl_download ? ioctl_data : erasing ? 8'd0     : cpu_o),
	.wren_a(ioctl_download ? ioctl_wr   : erasing ? erase_wr : ~cpu_wr_n & ~io_write),
	.q_a(ram_o),

	.address_b({1'b1, vaddr}),
	.data_b(0),
	.wren_b(0),
	.q_b(vdata)
);

reg  [15:0] rom_size = 0;
wire read_rom = rom_enable && (addr<rom_size) && !ed_page && ram_read;
always @(posedge clk_sys) begin
	reg old_download;

	old_download <= ioctl_download;
	if(~ioctl_download & old_download & !ioctl_index) rom_size <= ioctl_addr[15:0];
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
reg         fdd_drive;
reg         fdd_side;
wire        fdd_busy  = fdd_drive ? fdd2_busy  : fdd1_busy;
wire        fdd_ready = fdd_drive ? fdd2_ready : fdd1_ready;
wire  [7:0] fdd_o = fdd_ready ? (fdd_drive ? fdd2_o : fdd1_o) : 8'd0;

always @(posedge clk_sys) begin
	reg old_wr;

	old_wr <= io_wr;
	if(~old_wr & io_wr & fdd_sel & addr[2]) {fdd_side, fdd_drive} <= {~cpu_o[2], cpu_o[0]};

	if(cold_reset) fdd_drive <= 0;
end

//FDD1
wire  [7:0] fdd1_o;
reg         fdd1_ready;
wire        fdd1_busy;

always @(posedge clk_sys) begin
	reg old_mounted;

	old_mounted <= img_mounted[0];
	if(cold_reset) fdd1_ready <= 0;
		else if(~old_mounted & img_mounted[0]) fdd1_ready <= |img_size;
end

wd1793 #(1) fdd1
(
	.clk_sys(clk_sys),
	.ce(ce_f1),
	.reset(reset),
	.io_en(fdd_sel & fdd1_ready & ~fdd_drive & ~addr[2]),
	.rd(io_rd),
	.wr(io_wr),
	.addr(~addr[1:0]),
	.din(cpu_o),
	.dout(fdd1_o),

	.img_mounted(img_mounted[0]),
	.img_size(img_size[19:0]),
	.sd_lba(sd_lba[0]),
	.sd_rd(sd_rd[0]),
	.sd_wr(sd_wr[0]),
	.sd_ack(sd_ack[0]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din[0]),
	.sd_buff_wr(sd_buff_wr),

	.wp(0),

	.size_code(3),
	.layout(0),
	.side(fdd_side),
	.ready(~fdd_drive & fdd1_ready),
	.prepare(fdd1_busy),

	.input_active(0),
	.input_addr(0),
	.input_data(0),
	.input_wr(0),
	.buff_din(0)
);


//FDD2
wire  [7:0] fdd2_o;
reg         fdd2_ready;
wire        fdd2_busy;

always @(posedge clk_sys) begin
	reg old_mounted;

	old_mounted <= img_mounted[1];
	if(cold_reset) fdd2_ready <= 0;
		else if(~old_mounted & img_mounted[1]) fdd2_ready <= |img_size;
end

wd1793 #(1) fdd2
(
	.clk_sys(clk_sys),
	.ce(ce_f1),
	.reset(reset),
	.io_en(fdd_sel & fdd2_ready & fdd_drive & ~addr[2]),
	.rd(io_rd),
	.wr(io_wr),
	.addr(~addr[1:0]),
	.din(cpu_o),
	.dout(fdd2_o),

	.img_mounted(img_mounted[1]),
	.img_size(img_size[19:0]),
	.sd_lba(sd_lba[1]),
	.sd_rd(sd_rd[1]),
	.sd_wr(sd_wr[1]),
	.sd_ack(sd_ack[1]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din[1]),
	.sd_buff_wr(sd_buff_wr),

	.wp(0),

	.size_code(3),
	.layout(0),
	.side(fdd_side),
	.ready(fdd_drive & fdd2_ready),
	.prepare(fdd2_busy),

	.input_active(0),
	.input_addr(0),
	.input_data(0),
	.input_wr(0),
	.buff_din(0)
);

////////////////////   VIDEO   ////////////////////
wire        retrace;
wire [12:0] vaddr;
wire [31:0] vdata;
wire  [1:0] scale = status[2:1];

video video
(
	.*,
	.reset(reset & ~status[7]),
	
	.scroll(ppi1_a),
	.din(cpu_o),
	.io_we(pal_sel & io_wr),
	.border(ppi1_b[3:0]),
	.mode512(ppi1_b[4]),
	.hq2x(scale == 1),
	.scandoubler(scale || forced_scandoubler),
	.VGA_DE(vga_de)
);

assign VGA_SL = scale ? scale - 1'd1 : 2'd0;
assign VGA_F1 = 0;


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
	.ps2_key(ps2_key),
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
wire [7:0] joyPU   = joyA[7:0] | joyB[7:0];
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

/////////////////////////////////////////////////

wire       force_erase = cold_reset;
reg        erasing = 0;
reg        erase_wr;
reg [24:0] erase_addr;

always_comb begin
	case(ioctl_index) 
				0: ioctl_addr = 25'h050000 + ioctl_addr_orig; // BOOT ROM
			'h01: ioctl_addr = 25'h000100 + ioctl_addr_orig; // ROM file
			'h41: ioctl_addr = 25'h000100 + ioctl_addr_orig; // COM file
			'h81: ioctl_addr = 25'h000000 + ioctl_addr_orig; // C00 file
			'hC1: ioctl_addr = 25'h010000 + ioctl_addr_orig; // EDD file
		default: ioctl_addr = ioctl_addr_orig; // ??
	endcase
end

reg  [24:0] erase_mask;
wire [24:0] next_erase = (erase_addr + 1'd1) & erase_mask;

always@(posedge clk_sys) begin
	reg [15:0] cmd;
	reg        has_cmd;
	reg [24:0] addr;
	reg        wr;

	reg        old_force = 0;
	reg  [5:0] erase_clk_div;
	reg [24:0] end_addr;
	reg        erase_trigger = 0;

	erase_wr <= wr;
	wr <= 0;

	if(ioctl_download) begin
		old_force <= 0;
		erasing   <= 0;
		erase_trigger <= (ioctl_index == 1) || (ioctl_index == 'h41);
	end else begin
	
		old_force <= force_erase;

		// start erasing
		if(erase_trigger) begin
			erase_trigger <= 0;
			erase_mask    <= 'hFFFF;
			end_addr      <= 'h0100;
			erase_addr    <= ioctl_addr;
			erase_clk_div <= 1;
			erasing       <= 1;
		end else if(~old_force & force_erase) begin
			erase_trigger <= 0;
			erase_addr    <= 'h1FFFFFF;
			erase_mask    <= 'h1FFFFFF;
			end_addr      <= 'h0050000;
			erase_clk_div <= 1;
			erasing       <= 1;
		end else if(erasing) begin
			erase_clk_div <= erase_clk_div + 1'd1;
			if(!erase_clk_div) begin
				if(next_erase == end_addr) erasing <= 0;
				else begin
					erase_addr <= next_erase;
					wr <= 1;
				end
			end
		end
	end
end

endmodule

module dpram #(parameter DATAWIDTH_A=8, ADDRWIDTH_A=8, NUMWORDS_A=1<<ADDRWIDTH_A,
                         DATAWIDTH_B=8, ADDRWIDTH_B=8, NUMWORDS_B=1<<ADDRWIDTH_B,
                         MEM_INIT_FILE="" )
(
	input	                       clock,

	input	     [ADDRWIDTH_A-1:0] address_a,
	input	     [DATAWIDTH_A-1:0] data_a,
	input	                       wren_a,
	output reg [DATAWIDTH_A-1:0] q_a,

	input	     [ADDRWIDTH_B-1:0] address_b,
	input	     [DATAWIDTH_B-1:0] data_b,
	input	                       wren_b,
	output reg [DATAWIDTH_B-1:0] q_b
);

altsyncram	altsyncram_component
(
			.address_a (address_a),
			.address_b (address_b),
			.clock0 (clock),
			.data_a (data_a),
			.data_b (data_b),
			.wren_a (wren_a),
			.wren_b (wren_b),
			.q_a (q_a),
			.q_b (q_b),
			.aclr0 (1'b0),
			.aclr1 (1'b0),
			.addressstall_a (1'b0),
			.addressstall_b (1'b0),
			.byteena_a (1'b1),
			.byteena_b (1'b1),
			.clock1 (1'b1),
			.clocken0 (1'b1),
			.clocken1 (1'b1),
			.clocken2 (1'b1),
			.clocken3 (1'b1),
			.eccstatus (),
			.rden_a (1'b1),
			.rden_b (1'b1));
defparam
	altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK0",
	altsyncram_component.address_reg_b = "CLOCK0",
	altsyncram_component.indata_reg_b = "CLOCK0",
	altsyncram_component.numwords_a = NUMWORDS_A,
	altsyncram_component.numwords_b = NUMWORDS_B,
	altsyncram_component.widthad_a = ADDRWIDTH_A,
	altsyncram_component.widthad_b = ADDRWIDTH_B,
	altsyncram_component.width_a = DATAWIDTH_A,
	altsyncram_component.width_b = DATAWIDTH_B,
	altsyncram_component.width_byteena_a = 1,
	altsyncram_component.width_byteena_b = 1,

	altsyncram_component.init_file = MEM_INIT_FILE, 
	altsyncram_component.clock_enable_input_a = "BYPASS",
	altsyncram_component.clock_enable_input_b = "BYPASS",
	altsyncram_component.clock_enable_output_a = "BYPASS",
	altsyncram_component.clock_enable_output_b = "BYPASS",
	altsyncram_component.intended_device_family = "Cyclone V",
	altsyncram_component.lpm_type = "altsyncram",
	altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
	altsyncram_component.outdata_aclr_a = "NONE",
	altsyncram_component.outdata_aclr_b = "NONE",
	altsyncram_component.outdata_reg_a = "UNREGISTERED",
	altsyncram_component.outdata_reg_b = "UNREGISTERED",
	altsyncram_component.power_up_uninitialized = "FALSE",
	altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
	altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
	altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ";


endmodule
