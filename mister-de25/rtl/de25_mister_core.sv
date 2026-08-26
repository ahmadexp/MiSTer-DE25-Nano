// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

// Common source-level adapter between the DE25 board shell and MiSTer cores.
//
// The outer shell owns every board pin, HPS/LPDDR, HDMI transmitter, OSD,
// audio serializer, and Main bridge. This module contains the core-facing
// logic and is compiled into every complete RBF. Its superset port list is
// intentionally independent of optional ports in any one upstream `emu`.
module de25_mister_core (
    input  wire         clock_50,
    input  wire         platform_reset,
    input  wire         core_reset,
    input  wire         root_clk_100,
    input  wire         root_reset,
    input  wire         clk_audio,
    input  wire         osd_status,
    input  wire         uart_rx,
    input  wire  [3:0]  clock_bank0,
    input  wire         clock_bank0_locked,
    input  wire [48:0]  hps_bus_to_core,
    output wire [48:0]  hps_bus_from_core,

    output wire [26:0]  clock_bank0_awaddr,
    output wire         clock_bank0_awvalid,
    input  wire         clock_bank0_awready,
    output wire [31:0]  clock_bank0_wdata,
    output wire  [3:0]  clock_bank0_wstrb,
    output wire         clock_bank0_wvalid,
    input  wire         clock_bank0_wready,
    input  wire  [1:0]  clock_bank0_bresp,
    input  wire         clock_bank0_bvalid,
    output wire         clock_bank0_bready,
    output wire [26:0]  clock_bank0_araddr,
    output wire         clock_bank0_arvalid,
    input  wire         clock_bank0_arready,
    input  wire [31:0]  clock_bank0_rdata,
    input  wire  [1:0]  clock_bank0_rresp,
    input  wire         clock_bank0_rvalid,
    output wire         clock_bank0_rready,

    output wire         core_locked,
    output wire         menu_core,
    output wire         ce_pixel,
    output wire  [7:0]  video_r,
    output wire  [7:0]  video_g,
    output wire  [7:0]  video_b,
    output wire         video_hs,
    output wire         video_vs,
    output wire         video_de,
    output wire         video_f1,
    output wire  [1:0]  video_scanlines,

    output wire         fb_en,
    output wire  [4:0]  fb_format,
    output wire [11:0]  fb_width,
    output wire [11:0]  fb_height,
    output wire [31:0]  fb_base,
    output wire [13:0]  fb_stride,
    output wire         fb_force_blank,
    output wire         fb_pal_clk,
    output wire  [7:0]  fb_pal_addr,
    output wire [23:0]  fb_pal_dout,
    input  wire [23:0]  fb_pal_din,
    output wire         fb_pal_wr,

    output wire         led_user,
    output wire  [1:0]  led_power,
    output wire  [1:0]  led_disk,
    output wire  [1:0]  buttons,
    output wire [15:0]  audio_l,
    output wire [15:0]  audio_r,
    output wire         audio_signed,

    output wire  [7:0]  ddram_burstcount,
    output wire [28:0]  ddram_address,
    output wire [63:0]  ddram_writedata,
    output wire  [7:0]  ddram_byteenable,
    output wire         ddram_read,
    output wire         ddram_write,
    input  wire         ddram_busy,
    input  wire [63:0]  ddram_readdata,
    input  wire         ddram_readdatavalid,

    output wire         sdram_used,
    output wire         sdram_cke,
    output wire [12:0]  sdram_addr,
    output wire  [1:0]  sdram_ba,
    input  wire [15:0]  sdram_dq_in,
    output wire [15:0]  sdram_dq_out,
    output wire         sdram_dq_oe,
    output wire         sdram_dqml,
    output wire         sdram_dqmh,
    output wire         sdram_ncs,
    output wire         sdram_ncas,
    output wire         sdram_nras,
    output wire         sdram_nwe,

    output wire         uart_tx,
    output wire         uart_rts,
    output wire         uart_dtr,
    output wire  [6:0]  user_out
);
    wire         emu_ddram_clk;
    wire  [7:0]  emu_ddram_burstcount;
    wire [28:0]  emu_ddram_address;
    wire [63:0]  emu_ddram_writedata;
    wire  [7:0]  emu_ddram_byteenable;
    wire         emu_ddram_read;
    wire         emu_ddram_write;
    wire         emu_ddram_busy;
    wire [63:0]  emu_ddram_readdata;
    wire         emu_ddram_readdatavalid;

    // Bridge variable core clocks to the fixed 100 MHz HPS-side DDR channel.
    de25_ddram_cdc ddram_cdc (
        .core_clk_clk(emu_ddram_clk),
        .core_reset_reset(core_reset),
        .core_waitrequest(emu_ddram_busy),
        .core_readdata(emu_ddram_readdata),
        .core_readdatavalid(emu_ddram_readdatavalid),
        .core_burstcount(emu_ddram_burstcount),
        .core_writedata(emu_ddram_writedata),
        .core_address(emu_ddram_address),
        .core_write(emu_ddram_write),
        .core_read(emu_ddram_read),
        .core_byteenable(emu_ddram_byteenable),
        .core_debugaccess(1'b0),
        .root_clk_clk(root_clk_100),
        .root_reset_reset(root_reset),
        .root_waitrequest(ddram_busy),
        .root_readdata(ddram_readdata),
        .root_readdatavalid(ddram_readdatavalid),
        .root_burstcount(ddram_burstcount),
        .root_writedata(ddram_writedata),
        .root_address(ddram_address),
        .root_write(ddram_write),
        .root_read(ddram_read),
        .root_byteenable(ddram_byteenable),
        .root_debugaccess()
    );

    // MiSTer's HPS_BUS has fixed bit directions, even though upstream cores
    // declare it as an inout. Keep that convention inside the core, but expose
    // two unidirectional vectors to the board shell so Quartus does not create
    // competing drivers.
    wire [48:0] hps_bus;
    assign hps_bus[48:38] = hps_bus_to_core[48:38];
    assign hps_bus[35:33] = hps_bus_to_core[35:33];
    assign hps_bus[31:16] = hps_bus_to_core[31:16];
    assign hps_bus_from_core = {
        11'd0,
        hps_bus[37],
        1'b0,
        3'd0,
        hps_bus[32],
        16'd0,
        hps_bus[15:0]
    };

    // Fixed personas leave the calibration channel idle. Variable-clock
    // cores replace these assignments with an AXI-Lite master.
    assign clock_bank0_awaddr  = 27'd0;
    assign clock_bank0_awvalid = 1'b0;
    assign clock_bank0_wdata   = 32'd0;
    assign clock_bank0_wstrb   = 4'd0;
    assign clock_bank0_wvalid  = 1'b0;
    assign clock_bank0_bready  = 1'b1;
    assign clock_bank0_araddr  = 27'd0;
    assign clock_bank0_arvalid = 1'b0;
    assign clock_bank0_rready  = 1'b1;
    assign core_locked = clock_bank0_locked;

`ifdef DE25_MENU_CORE
    assign menu_core = 1'b1;
`else
    assign menu_core = 1'b0;
`endif

`ifdef DE25_CORE_HAS_SDRAM
    assign sdram_used = 1'b1;
`else
    assign sdram_used = 1'b0;
`endif

`ifndef DE25_CORE_HAS_FB
    assign fb_en          = 1'b0;
    assign fb_format      = 5'd0;
    assign fb_width       = 12'd0;
    assign fb_height      = 12'd0;
    assign fb_base        = 32'd0;
    assign fb_stride      = 14'd0;
    assign fb_force_blank = 1'b0;
`endif

`ifndef DE25_CORE_HAS_FB_PALETTE
    assign fb_pal_clk  = 1'b0;
    assign fb_pal_addr = 8'd0;
    assign fb_pal_dout = 24'd0;
    assign fb_pal_wr   = 1'b0;
`endif

`ifndef DE25_CORE_HAS_SPLIT_SDRAM_DQ
    wire [15:0] unused_sdram_dq;
    assign sdram_dq_out = 16'd0;
    assign sdram_dq_oe  = 1'b0;
`endif

    wire [12:0] unused_video_arx;
    wire [12:0] unused_video_ary;
    wire unused_video_scaler;
    wire unused_video_disable;
    wire unused_hdmi_freeze;
    wire unused_hdmi_blackout;
    wire [1:0] unused_audio_mix;
    wire unused_sd_sck;
    wire unused_sd_mosi;
    wire unused_sd_cs;
    wire unused_core_clk_video;
    wire unused_sdram_clk;
`ifdef DE25_CORE_HAS_HDMI_BOB_DEINT
    wire unused_hdmi_bob_deint;
`endif

    emu core (
        .CLK_50M(clock_50),
`ifdef DE25_PC110_CORE
        .DE25_CLK_SYS(clock_bank0[0]),
        .DE25_CLK_UART1(clock_bank0[2]),
        .DE25_CLK_MPU(clock_bank0[3]),
        .DE25_CLK_OPL(clock_50),
        .DE25_CLK_VGA(clock_bank0[1]),
        .DE25_CLK_UART2(clock_bank0[2]),
`elsif DE25_MENU_CORE
        .DE25_CLK_SYS(clock_bank0[0]),
        .DE25_CLK_VIDEO(clock_bank0[1]),
        .DE25_CLK_SDRAM(clock_bank0[2]),
        .DE25_CLK_SDRAM_CAPTURE(clock_bank0[3]),
        .DE25_PLL_LOCKED(clock_bank0_locked),
`endif
        .RESET(core_reset),
`ifdef DE25_HPS_BUS_49
        .HPS_BUS(hps_bus),
`else
        .HPS_BUS(hps_bus[45:0]),
`endif
        .CLK_VIDEO(unused_core_clk_video),
        .CE_PIXEL(ce_pixel),
        .VIDEO_ARX(unused_video_arx),
        .VIDEO_ARY(unused_video_ary),
        .VGA_R(video_r),
        .VGA_G(video_g),
        .VGA_B(video_b),
        .VGA_HS(video_hs),
        .VGA_VS(video_vs),
        .VGA_DE(video_de),
        .VGA_F1(video_f1),
        .VGA_SL(video_scanlines),
        .VGA_SCALER(unused_video_scaler),
        .VGA_DISABLE(unused_video_disable),
        .HDMI_WIDTH(12'd0),
        .HDMI_HEIGHT(12'd0),
        .HDMI_FREEZE(unused_hdmi_freeze),
        .HDMI_BLACKOUT(unused_hdmi_blackout),
`ifdef DE25_CORE_HAS_HDMI_BOB_DEINT
        .HDMI_BOB_DEINT(unused_hdmi_bob_deint),
`endif
`ifdef DE25_CORE_HAS_FB
        .FB_EN(fb_en),
        .FB_FORMAT(fb_format),
        .FB_WIDTH(fb_width),
        .FB_HEIGHT(fb_height),
        .FB_BASE(fb_base),
        .FB_STRIDE(fb_stride),
        .FB_VBL(video_vs),
        .FB_LL(1'b0),
        .FB_FORCE_BLANK(fb_force_blank),
`ifdef DE25_CORE_HAS_FB_PALETTE
        .FB_PAL_CLK(fb_pal_clk),
        .FB_PAL_ADDR(fb_pal_addr),
        .FB_PAL_DOUT(fb_pal_dout),
        .FB_PAL_DIN(fb_pal_din),
        .FB_PAL_WR(fb_pal_wr),
`endif
`endif
        .LED_USER(led_user),
        .LED_POWER(led_power),
        .LED_DISK(led_disk),
        .BUTTONS(buttons),
        .CLK_AUDIO(clk_audio),
        .AUDIO_L(audio_l),
        .AUDIO_R(audio_r),
        .AUDIO_S(audio_signed),
        .AUDIO_MIX(unused_audio_mix),
`ifdef DE25_CORE_HAS_TAPE_IN
        .TAPE_IN(1'b0),
`endif
        // ADC_BUS is omitted on DE25. Every supported persona disables the
        // optional MiSTer ADC header, so the adapter never infers a physical
        // bidirectional buffer for it.
        .SD_SCK(unused_sd_sck),
        .SD_MOSI(unused_sd_mosi),
        .SD_MISO(1'b1),
        .SD_CS(unused_sd_cs),
        .SD_CD(1'b1),
        .DDRAM_CLK(emu_ddram_clk),
        .DDRAM_BUSY(emu_ddram_busy),
        .DDRAM_BURSTCNT(emu_ddram_burstcount),
        .DDRAM_ADDR(emu_ddram_address),
        .DDRAM_DOUT(emu_ddram_readdata),
        .DDRAM_DOUT_READY(emu_ddram_readdatavalid),
        .DDRAM_RD(emu_ddram_read),
        .DDRAM_DIN(emu_ddram_writedata),
        .DDRAM_BE(emu_ddram_byteenable),
        .DDRAM_WE(emu_ddram_write),
        .SDRAM_CLK(unused_sdram_clk),
        .SDRAM_CKE(sdram_cke),
        .SDRAM_A(sdram_addr),
        .SDRAM_BA(sdram_ba),
`ifdef DE25_CORE_HAS_SPLIT_SDRAM_DQ
        .de25_sdram_dq_in(sdram_dq_in),
        .de25_sdram_dq_out(sdram_dq_out),
        .de25_sdram_dq_oe(sdram_dq_oe),
`else
        .SDRAM_DQ(unused_sdram_dq),
`endif
        .SDRAM_DQML(sdram_dqml),
        .SDRAM_DQMH(sdram_dqmh),
        .SDRAM_nCS(sdram_ncs),
        .SDRAM_nCAS(sdram_ncas),
        .SDRAM_nRAS(sdram_nras),
        .SDRAM_nWE(sdram_nwe),
        .UART_CTS(1'b0),
        .UART_RTS(uart_rts),
        .UART_RXD(uart_rx),
        .UART_TXD(uart_tx),
        .UART_DTR(uart_dtr),
        .UART_DSR(1'b0),
        .USER_IN(7'h7f),
        .USER_OUT(user_out),
        .OSD_STATUS(osd_status)
    );

    wire unused = &{1'b0, unused_video_arx, unused_video_ary,
                    unused_video_scaler, unused_video_disable,
                    unused_hdmi_freeze, unused_hdmi_blackout,
                    unused_audio_mix, unused_sd_sck, unused_sd_mosi,
                    unused_sd_cs, sdram_dq_in,
                    fb_pal_din
`ifdef DE25_CORE_HAS_HDMI_BOB_DEINT
                    , unused_hdmi_bob_deint
`endif
                    };
endmodule

`default_nettype wire
