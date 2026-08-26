`timescale 1ns/1ps

// Synthesis and JTAG smoke target for the complete PC110 RTL datapath.  The
// host and external-memory ports are intentionally stalled at this milestone;
// this image proves that the ao486, chipset, video, and sound logic elaborate
// and fit on Agilex 5 before the HPS and SDRAM bridges are introduced.
module de25_pc110_core_smoke (
    input  logic       CLOCK0_50,
    input  logic [1:0] KEY,
    output logic [7:0] LED,
    input  logic       FPGA_UART_RX,
    output logic       FPGA_UART_TX
);

    logic ninit_done;
    logic pll_locked;
    logic clk_sys;
    logic clk_uart1;
    logic clk_mpu;
    logic clk_opl;
    logic clk_vga;
    logic clk_uart2;
    logic [26:0] heartbeat = '0;

    wire reset = ninit_done || !pll_locked || !KEY[0];

    wire [1:0] fdd_request;
    wire [2:0] ide0_request;
    wire [2:0] ide1_request;
    wire pcmcia_request;
    wire [15:0] mgmt_readdata;
    wire bios_setup_ack;
    wire ps2_kbclk_out;
    wire ps2_kbdat_out;
    wire ps2_mouseclk_out;
    wire ps2_mousedat_out;
    wire ps2_reset_n;
    wire [7:0] syscfg;
    wire uart1_tx;
    wire pc110_postlog_tx;
    wire uart1_rts_n;
    wire uart1_dtr_n;
    wire uart2_tx;
    wire uart2_rts_n;
    wire uart2_dtr_n;
    wire mpu_tx;
    wire [15:0] sound_sample_l;
    wire [15:0] sound_sample_r;
    wire speaker_out;
    wire video_ce;
    wire video_blank_n;
    wire video_hsync;
    wire video_vsync;
    wire [7:0] video_r;
    wire [7:0] video_g;
    wire [7:0] video_b;
    wire [7:0] video_pal_a;
    wire [17:0] video_pal_d;
    wire video_pal_we;
    wire [19:0] video_start_addr;
    wire [8:0] video_width;
    wire [10:0] video_height;
    wire [3:0] video_flags;
    wire [8:0] video_stride;
    wire video_off;
    wire ddram_clk;
    wire [7:0] ddram_burstcount;
    wire [24:0] ddram_address;
    wire ddram_read;
    wire [63:0] ddram_writedata;
    wire [7:0] ddram_byteenable;
    wire ddram_write;

    ResetRelease reset_release (
        .ninit_done(ninit_done)
    );

    pc110_pll clocks (
        .refclk_clk(CLOCK0_50),
        .locked_export(pll_locked),
        .reset_reset(!KEY[0] || ninit_done),
        .outclk0_clk(clk_sys),
        .outclk1_clk(clk_uart1),
        .outclk2_clk(clk_mpu),
        .outclk3_clk(clk_opl),
        .outclk4_clk(clk_vga),
        .outclk5_clk(clk_uart2)
    );

    always_ff @(posedge clk_sys) begin
        if (reset)
            heartbeat <= '0;
        else
            heartbeat <= heartbeat + 1'b1;
    end

    always_comb begin
        LED[0] = pll_locked;
        LED[1] = !reset;
        LED[2] = heartbeat[26];
        LED[3] = ps2_reset_n;
        LED[4] = |syscfg;
        LED[5] = ddram_read;
        LED[6] = ddram_write;
        LED[7] = |{ide0_request, ide1_request, fdd_request, pcmcia_request};
        FPGA_UART_TX = pc110_postlog_tx & uart1_tx;
    end

    system core (
        .reset(reset),
        .clk_sys(clk_sys),
        .clock_rate(28'd30000000),
        .l1_disable(1'b0),
        .l2_disable(1'b0),
        .fdd_request(fdd_request),
        .ide0_request(ide0_request),
        .ide1_request(ide1_request),
        .pcmcia_request(pcmcia_request),
        .floppy_wp(2'b11),
        .joystick_dig_1(14'd0),
        .joystick_dig_2(14'd0),
        .joystick_ana_1(16'd0),
        .joystick_ana_2(16'd0),
        .joystick_mode(2'd0),
        .mgmt_address(16'd0),
        .mgmt_read(1'b0),
        .mgmt_readdata(mgmt_readdata),
        .mgmt_write(1'b0),
        .mgmt_writedata(16'd0),
        .ps2_kbclk_in(1'b1),
        .ps2_kbdat_in(1'b1),
        .inject_f1(1'b0),
        .bios_setup_req(1'b0),
        .bios_setup_ack(bios_setup_ack),
        .ps2_kbclk_out(ps2_kbclk_out),
        .ps2_kbdat_out(ps2_kbdat_out),
        .ps2_mouseclk_in(1'b1),
        .ps2_mousedat_in(1'b1),
        .ps2_mouseclk_out(ps2_mouseclk_out),
        .ps2_mousedat_out(ps2_mousedat_out),
        .ps2_reset_n(ps2_reset_n),
        .bootcfg(6'd0),
        .ram_option(2'd0),
        .syscfg(syscfg),
        .clk_uart1(clk_uart1),
        .uart1_rx(FPGA_UART_RX),
        .uart1_tx(uart1_tx),
        .pc110_postlog_tx(pc110_postlog_tx),
        .uart1_cts_n(1'b0),
        .uart1_dcd_n(1'b0),
        .uart1_dsr_n(1'b0),
        .uart1_rts_n(uart1_rts_n),
        .uart1_dtr_n(uart1_dtr_n),
        .clk_uart2(clk_uart2),
        .uart2_rx(1'b1),
        .uart2_tx(uart2_tx),
        .uart2_cts_n(1'b0),
        .uart2_dcd_n(1'b0),
        .uart2_dsr_n(1'b0),
        .uart2_rts_n(uart2_rts_n),
        .uart2_dtr_n(uart2_dtr_n),
        .clk_mpu(clk_mpu),
        .mpu_rx(1'b1),
        .mpu_tx(mpu_tx),
        .clk_opl(clk_opl),
        .sound_sample_l(sound_sample_l),
        .sound_sample_r(sound_sample_r),
        .sound_fm_mode(1'b0),
        .sound_cms_en(1'b0),
        .speaker_out(speaker_out),
        .clk_vga(clk_vga),
        .clock_rate_vga(28'd90000000),
        .video_ce(video_ce),
        .video_blank_n(video_blank_n),
        .video_hsync(video_hsync),
        .video_vsync(video_vsync),
        .video_r(video_r),
        .video_g(video_g),
        .video_b(video_b),
        .video_f60(1'b1),
        .video_pal_a(video_pal_a),
        .video_pal_d(video_pal_d),
        .video_pal_we(video_pal_we),
        .video_start_addr(video_start_addr),
        .video_width(video_width),
        .video_height(video_height),
        .video_flags(video_flags),
        .video_stride(video_stride),
        .video_off(video_off),
        .video_fb_en(1'b0),
        .video_lores(1'b0),
        .DDRAM_CLK(ddram_clk),
        .DDRAM_BUSY(1'b1),
        .DDRAM_BURSTCNT(ddram_burstcount),
        .DDRAM_ADDR(ddram_address),
        .DDRAM_DOUT(64'd0),
        .DDRAM_DOUT_READY(1'b0),
        .DDRAM_RD(ddram_read),
        .DDRAM_DIN(ddram_writedata),
        .DDRAM_BE(ddram_byteenable),
        .DDRAM_WE(ddram_write)
    );

endmodule
