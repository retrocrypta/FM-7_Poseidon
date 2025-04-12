module guest_top(
    input         CLOCK_27,
    `ifdef USE_CLOCK_50
    input         CLOCK_50,
    `endif

    // LED outputs
    output        LED,

    // Video outputs
    output  [5:0] VGA_R,
    output  [5:0] VGA_G,
    output  [5:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,

    `ifdef USE_HDMI
    output        HDMI_RST,
    output  [7:0] HDMI_R,
    output  [7:0] HDMI_G,
    output  [7:0] HDMI_B,
    output        HDMI_HS,
    output        HDMI_VS,
    output        HDMI_PCLK,
    output        HDMI_DE,
    inout         HDMI_SDA,
    inout         HDMI_SCL,
    input         HDMI_INT,
    `endif

    // Audio outputs
    output        AUDIO_L,
    output        AUDIO_R,

    // SPI interface to control module
    input         SPI_SCK,
    input         SPI_SS2,
    input         SPI_SS3,
    input         SPI_DI,
    output        SPI_DO,
    input         CONF_DATA0,

    // SDRAM interface
    inout  [15:0] SDRAM_DQ,
    output [12:0] SDRAM_A,
    output  [1:0] SDRAM_BA,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output        SDRAM_nWE,
    output        SDRAM_nCAS,
    output        SDRAM_nRAS,
    output        SDRAM_nCS,
    output        SDRAM_CLK,
    output        SDRAM_CKE
);

`ifdef NO_DIRECT_UPLOAD
localparam bit DIRECT_UPLOAD = 0;
wire SPI_SS4 = 1;
`else
localparam bit DIRECT_UPLOAD = 1;
`endif

`ifdef USE_QSPI
localparam bit QSPI = 1;
assign QDAT = 4'hZ;
`else
localparam bit QSPI = 0;
`endif

`ifdef VGA_8BIT
localparam VGA_BITS = 8;
`else
localparam VGA_BITS = 6;
`endif

`ifdef USE_HDMI
localparam bit HDMI = 1;
assign HDMI_RST = 1'b1;
`else
localparam bit HDMI = 0;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif

// remove this if the 2nd chip is actually used
`ifdef DUAL_SDRAM
assign SDRAM2_A = 13'hZZZZ;
assign SDRAM2_BA = 0;
assign SDRAM2_DQML = 0;
assign SDRAM2_DQMH = 0;
assign SDRAM2_CKE = 0;
assign SDRAM2_CLK = 0;
assign SDRAM2_nCS = 1;
assign SDRAM2_DQ = 16'hZZZZ;
assign SDRAM2_nCAS = 1;
assign SDRAM2_nRAS = 1;
assign SDRAM2_nWE = 1;
`endif

`ifdef USE_HDMI
wire        i2c_start;
wire        i2c_read;
wire  [6:0] i2c_addr;
wire  [7:0] i2c_subaddr;
wire  [7:0] i2c_dout;
wire  [7:0] i2c_din;
wire        i2c_ack;
wire        i2c_end;
`endif


// Configuration string
localparam CONF_STR = {
    "FM-7;;",
    "F1,t77,Load Tape;",
    "O1,Tape Rewind;",
    "O2,Tape Audio,Off,On;",
    "O3,BootROM,Basic;",
    `SEP
    "O4,TV Mode,NTSC,PAL;",
    "O5,Noise,White,Red;",
    "T0,Reset;",
    "V,v1.0."
};

// Clocks and PLL
wire clk_sys, clk_ram, clk_emu;
wire pll_locked;

pll pll(
    .inclk0(CLOCK_50),
    .c0(clk_sys),  // SDRAM clock
    .c1(_2MHz),  // System clock
    .locked(locked)
);

// Reset logic
wire reset = ~locked | status[0] | buttons[1];

// Status and control signals
wire [31:0] status;
wire  [1:0] buttons;
wire  [1:0] scandoubler_disable;
wire        ypbpr;
wire        no_csync;

// Data IO interface
wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_data;

data_io data_io(
    .clk_sys(clk_sys),
    .SPI_SCK(SPI_SCK),
    .SPI_SS2(SPI_SS2),
    .SPI_DI(SPI_DI),
    .clkref_n(1'b0),
    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_data)
);

// User IO interface
wire [31:0] joy1, joy2;
wire [10:0] ps2_key;

user_io #(
    .STRLEN($size(CONF_STR)>>3),
    .SD_IMAGES(2),
    .FEATURES(32'h0 | (BIG_OSD << 13))
) user_io(
    .clk_sys(clk_sys),
    .clk_sd(clk_sys),
    .conf_str(CONF_STR),
    .SPI_CLK(SPI_SCK),
    .SPI_SS_IO(CONF_DATA0),
    .SPI_MOSI(SPI_DI),
    .SPI_MISO(SPI_DO),
    .joystick_0(joy1),
    .joystick_1(joy2),
    .status(status)
);

// Video signals
wire [7:0] video_r, video_g, video_b;
wire       video_hs, video_vs;
wire       video_hblank, video_vblank;
wire       ce_pix;

// Video output
mist_video #(
    .COLOR_DEPTH(8),
    .SD_HCNT_WIDTH(10),
    .USE_BLANKS(1'b1),
    .OUT_COLOR_DEPTH(VGA_BITS),
    .BIG_OSD(BIG_OSD)
) mist_video(
    .clk_sys(clk_sys),
    .SPI_SCK(SPI_SCK),
    .SPI_SS3(SPI_SS3),
    .SPI_DI(SPI_DI),
    .R(video_r),
    .G(video_g),
    .B(video_b),
    .HSync(video_hs),
    .VSync(video_vs),
    .HBlank(video_hblank),
    .VBlank(video_vblank),
    .VGA_R(VGA_R),
    .VGA_G(VGA_G),
    .VGA_B(VGA_B),
    .VGA_VS(VGA_VS),
    .VGA_HS(VGA_HS),
    .ce_divider(1'b0),
    .scandoubler_disable(scandoubler_disable),
    .scanlines(status[3:1]),
    .ypbpr(ypbpr),
    .no_csync(no_csync)
);

// Audio output
wire [15:0] audio_l, audio_r;

dac #(.C_bits(16)) dac_l(
    .clk_i(clk_sys),
    .res_n_i(1),
    .dac_i(audio_l),
    .dac_o(AUDIO_L)
);

dac #(.C_bits(16)) dac_r(
    .clk_i(clk_sys),
    .res_n_i(1),
    .dac_i(audio_r),
    .dac_o(AUDIO_R)
);

// Core instance
core u_core(
    .RESETn(~reset),
    .CLKSYS(clk_sys),
    .HBLANK(video_hblank),
    .VBLANK(video_vblank),
    .VSync(video_vs),
    .HSync(video_hs),
    .grb({video_g[7], video_r[7], video_b[7]}),
    .ps2_key(ps2_key),
    .ce_pix(ce_pix),
    .bootrom_sel(status[3])
);

// LED assignment (inverted)
assign LED = ~ioctl_download;

`ifdef USE_HDMI
assign HDMI_RST = 1'b1;
`endif
// [8] - extended, [9] - pressed, [10] - toggles with every press/release
wire        key_pressed;
wire [7:0]  key_code;
wire        key_strobe;
wire        key_extended;


assign ps2_key = {key_strobe,key_pressed,key_extended,key_code};


endmodule
