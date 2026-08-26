`timescale 1ns/1ps

// DE25-Nano rev-B PC110 integration target.
//
// SW0 is a deliberate run interlock.  Leave it low while Linux reserves and
// initializes the PC110's LPDDR window, then raise it to release the x86 core.
// KEY0 resets the FPGA fabric and KEY1 restarts the ADV7513 initialization.
module de25_pc110_top (
    input  logic        CLOCK0_50,
    input  logic [1:0]  KEY,
    input  logic [3:0]  SW,
    output logic [7:0]  LED,

    input  logic        LPDDR4A_REFCLK_p,
    output wire         LPDDR4A_CS_n,
    output wire [5:0]   LPDDR4A_CA,
    output wire         LPDDR4A_CK,
    output wire         LPDDR4A_CKE,
    output wire         LPDDR4A_CK_n,
    inout  wire [3:0]   LPDDR4A_DM,
    inout  wire [31:0]  LPDDR4A_DQ,
    inout  wire [3:0]   LPDDR4A_DQS,
    inout  wire [3:0]   LPDDR4A_DQS_n,
    output wire         LPDDR4A_RESET_n,
    input  logic        LPDDR4A_RZQ,

    inout  wire         HDMI_LRCLK,
    inout  wire         HDMI_MCLK,
    inout  wire         HDMI_SCLK,
    output wire         HDMI_TX_CLK,
    output wire         HDMI_TX_HS,
    output wire         HDMI_TX_VS,
    output wire [23:0]  HDMI_TX_D,
    output wire         HDMI_TX_DE,
    inout  wire         HDMI_I2C_SCL,
    inout  wire         HDMI_I2C_SDA,
    input  logic        HDMI_TX_INT,
    inout  wire         HDMI_I2S,

    output wire         FPGA_UART_TX,
    input  logic        FPGA_UART_RX,

    input  logic        HPS_CLK_25,
    output wire         HPS_ENET_MDC,
    inout  wire         HPS_ENET_MDIO,
    input  logic        HPS_ENET_RX_CLK,
    input  logic        HPS_ENET_RX_CTL,
    input  logic [3:0]  HPS_ENET_RX_DATA,
    output wire         HPS_ENET_TX_CLK,
    output wire         HPS_ENET_TX_CTL,
    output wire [3:0]   HPS_ENET_TX_DATA,
    inout  wire         HPS_GSENSOR_I2C_EN,
    inout  wire         HPS_GSENSOR_INT,
    inout  wire         HPS_I2C_SCL,
    inout  wire         HPS_I2C_SDA,
    inout  wire         HPS_KEY,
    inout  wire         HPS_LED,
    output wire         HPS_SD_CLK,
    inout  wire         HPS_SD_CMD,
    inout  wire [3:0]   HPS_SD_DATA,
    input  logic        HPS_UART_RX,
    output wire         HPS_UART_TX,
    input  logic        HPS_USB_CLK,
    inout  wire [7:0]   HPS_USB_DATA,
    input  logic        HPS_USB_DIR,
    input  logic        HPS_USB_NXT,
    output wire         HPS_USB_STP,

    input  logic        FAN_ALERT_n
);

    // The production DE25-Nano reports 1 GiB of calibrated LPDDR beginning at
    // 0x8000_0000. Keep the upper 256 MiB private to the PC110 core so Linux
    // cannot share live cache lines with the FPGA.
    localparam logic [31:0] PC110_LPDDR_BASE = 32'hB000_0000;

    logic ninit_done;
    logic pll_locked;
    logic hps_pll_locked;
    logic vga_pll_locked;
    logic clk_sys;
    logic clk_uart1;
    logic clk_mpu;
    logic clk_opl;
    logic clk_vga;
    logic clk_uart2;
    logic clk_hps_fabric;
    logic h2f_reset;
    logic h2f_warm_reset_req;
    logic [2:0] hps_led_out;
    logic [26:0] heartbeat = '0;

    wire all_plls_locked = pll_locked && hps_pll_locked && vga_pll_locked;
    wire fabric_reset_request = ninit_done || !KEY[0] || !all_plls_locked || h2f_reset;
    wire core_reset_request   = fabric_reset_request || !SW[0];
    logic [2:0] core_reset_pipe = 3'b111;
    wire fabric_reset = fabric_reset_request;
    wire core_reset   = core_reset_pipe[2];
    wire qsys_reset_n = !ninit_done && KEY[0] && all_plls_locked;

    // Reset assertion is asynchronous, but release is synchronized to the
    // PC110 system clock.  In particular, do not let the HPS reset-manager
    // output deassert directly into the ao486 and peripheral state machines.
    always_ff @(posedge clk_sys or posedge core_reset_request) begin
        if (core_reset_request)
            core_reset_pipe <= 3'b111;
        else
            core_reset_pipe <= {core_reset_pipe[1:0], 1'b0};
    end

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
    wire ddram_waitrequest;
    wire [63:0] ddram_readdata;
    wire ddram_readdatavalid;

    logic hdmi_init_done;
    logic hdmi_init_error;
    logic hdmi_status_valid;
    logic hdmi_transmitter_powered;
    logic hdmi_hpd_high;
    logic hdmi_monitor_sense;
    logic hdmi_pll_locked;
    logic hdmi_tmds_powered;
    logic hdmi_edid_ready;
    logic [3:0] hdmi_ddc_state;
    logic [3:0] hdmi_ddc_error;
    logic [63:0] hdmi_raw_status;

    pc110_pll clocks (
        .refclk_clk(CLOCK0_50),
        .locked_export(pll_locked),
        .reset_reset(ninit_done || !KEY[0]),
        .hps_refclk_clk(CLOCK0_50),
        .hps_locked_export(hps_pll_locked),
        .hps_reset_reset(ninit_done || !KEY[0]),
        .vga_refclk_clk(CLOCK0_50),
        .vga_locked_export(vga_pll_locked),
        .vga_reset_reset(ninit_done || !KEY[0]),
        .outclk0_clk(clk_sys),
        .outclk1_clk(clk_uart1),
        .outclk2_clk(clk_mpu),
        .outclk4_clk(clk_vga),
        .outclk5_clk(clk_uart2),
        .outclk6_clk(clk_hps_fabric)
    );

    assign clk_opl = CLOCK0_50;

    pc110_hps hps (
        .clk_100_clk(clk_hps_fabric),
        .pc110_clk_clk(clk_sys),
        .pc110_reset_reset(core_reset),
        .pc110_mem_waitrequest(ddram_waitrequest),
        .pc110_mem_readdata(ddram_readdata),
        .pc110_mem_readdatavalid(ddram_readdatavalid),
        .pc110_mem_burstcount(ddram_burstcount),
        .pc110_mem_writedata(ddram_writedata),
        .pc110_mem_address(PC110_LPDDR_BASE | {4'b0000, ddram_address, 3'b000}),
        .pc110_mem_write(ddram_write),
        .pc110_mem_read(ddram_read),
        .pc110_mem_byteenable(ddram_byteenable),
        .pc110_mem_debugaccess(1'b0),
        .reset_reset_n(qsys_reset_n),
        .ninit_done_ninit_done(ninit_done),
        .h2f_reset_reset(h2f_reset),
        .h2f_warm_reset_handshake_reset_req(h2f_warm_reset_req),
        .h2f_warm_reset_handshake_reset_ack(h2f_warm_reset_req),
        .hps_io_hps_osc_clk(HPS_CLK_25),
        .hps_io_sdmmc_data0(HPS_SD_DATA[0]),
        .hps_io_sdmmc_data1(HPS_SD_DATA[1]),
        .hps_io_sdmmc_cclk(HPS_SD_CLK),
        .hps_io_sdmmc_data2(HPS_SD_DATA[2]),
        .hps_io_sdmmc_data3(HPS_SD_DATA[3]),
        .hps_io_sdmmc_cmd(HPS_SD_CMD),
        .hps_io_usb0_clk(HPS_USB_CLK),
        .hps_io_usb0_stp(HPS_USB_STP),
        .hps_io_usb0_dir(HPS_USB_DIR),
        .hps_io_usb0_data0(HPS_USB_DATA[0]),
        .hps_io_usb0_data1(HPS_USB_DATA[1]),
        .hps_io_usb0_nxt(HPS_USB_NXT),
        .hps_io_usb0_data2(HPS_USB_DATA[2]),
        .hps_io_usb0_data3(HPS_USB_DATA[3]),
        .hps_io_usb0_data4(HPS_USB_DATA[4]),
        .hps_io_usb0_data5(HPS_USB_DATA[5]),
        .hps_io_usb0_data6(HPS_USB_DATA[6]),
        .hps_io_usb0_data7(HPS_USB_DATA[7]),
        .hps_io_emac0_tx_clk(HPS_ENET_TX_CLK),
        .hps_io_emac0_tx_ctl(HPS_ENET_TX_CTL),
        .hps_io_emac0_rx_clk(HPS_ENET_RX_CLK),
        .hps_io_emac0_rx_ctl(HPS_ENET_RX_CTL),
        .hps_io_emac0_txd0(HPS_ENET_TX_DATA[0]),
        .hps_io_emac0_txd1(HPS_ENET_TX_DATA[1]),
        .hps_io_emac0_rxd0(HPS_ENET_RX_DATA[0]),
        .hps_io_emac0_rxd1(HPS_ENET_RX_DATA[1]),
        .hps_io_emac0_txd2(HPS_ENET_TX_DATA[2]),
        .hps_io_emac0_txd3(HPS_ENET_TX_DATA[3]),
        .hps_io_emac0_rxd2(HPS_ENET_RX_DATA[2]),
        .hps_io_emac0_rxd3(HPS_ENET_RX_DATA[3]),
        .hps_io_mdio0_mdio(HPS_ENET_MDIO),
        .hps_io_mdio0_mdc(HPS_ENET_MDC),
        .hps_io_uart1_tx(HPS_UART_TX),
        .hps_io_uart1_rx(HPS_UART_RX),
        .hps_io_i2c1_sda(HPS_I2C_SDA),
        .hps_io_i2c1_scl(HPS_I2C_SCL),
        .hps_io_gpio28(HPS_GSENSOR_INT),
        .hps_io_gpio34(HPS_GSENSOR_I2C_EN),
        .hps_io_gpio40(HPS_KEY),
        .hps_io_gpio41(HPS_LED),
        .f2h_irq1_in_irq(32'd0),
        .emif_hps_emif_mem_0_mem_cs(LPDDR4A_CS_n),
        .emif_hps_emif_mem_0_mem_ca(LPDDR4A_CA),
        .emif_hps_emif_mem_0_mem_cke(LPDDR4A_CKE),
        .emif_hps_emif_mem_0_mem_dq(LPDDR4A_DQ),
        .emif_hps_emif_mem_0_mem_dqs_t(LPDDR4A_DQS),
        .emif_hps_emif_mem_0_mem_dqs_c(LPDDR4A_DQS_n),
        .emif_hps_emif_mem_0_mem_dmi(LPDDR4A_DM),
        .emif_hps_emif_mem_ck_0_mem_ck_t(LPDDR4A_CK),
        .emif_hps_emif_mem_ck_0_mem_ck_c(LPDDR4A_CK_n),
        .emif_hps_emif_mem_reset_n_mem_reset_n(LPDDR4A_RESET_n),
        .emif_hps_emif_oct_0_oct_rzqin(LPDDR4A_RZQ),
        .emif_hps_emif_ref_clk_0_clk(LPDDR4A_REFCLK_p),
        .button_pio_external_connection_export({2'b11, KEY}),
        .dipsw_pio_external_connection_export(SW),
        .led_pio_external_connection_in_port({all_plls_locked, !fabric_reset, !core_reset}),
        .led_pio_external_connection_out_port(hps_led_out)
    );

    system #(
        .PC110_POSTLOG_ENABLE(1'b1)
    ) core (
        .reset(core_reset),
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
        .inject_f1(SW[1]),
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
        .video_f60(!SW[2]),
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
        .DDRAM_BUSY(ddram_waitrequest),
        .DDRAM_BURSTCNT(ddram_burstcount),
        .DDRAM_ADDR(ddram_address),
        .DDRAM_DOUT(ddram_readdata),
        .DDRAM_DOUT_READY(ddram_readdatavalid),
        .DDRAM_RD(ddram_read),
        .DDRAM_DIN(ddram_writedata),
        .DDRAM_BE(ddram_byteenable),
        .DDRAM_WE(ddram_write)
    );

    // The ADV7513 receives the 90 MHz VGA engine clock.  PC110 pixel values
    // remain stable between video_ce pulses, so repeated samples preserve the
    // guest scan timing while avoiding a fabric-generated gated clock.
    assign HDMI_TX_CLK = clk_vga;
    assign HDMI_TX_HS  = video_hsync;
    assign HDMI_TX_VS  = video_vsync;
    assign HDMI_TX_D   = {video_r, video_g, video_b};
    assign HDMI_TX_DE  = video_blank_n;

    assign HDMI_LRCLK = 1'b0;
    assign HDMI_MCLK  = 1'b0;
    assign HDMI_SCLK  = 1'b0;
    assign HDMI_I2S   = 1'b0;
    assign FPGA_UART_TX = pc110_postlog_tx & uart1_tx;

    adv7513_init #(
        .CLOCK_HZ(50_000_000),
        .I2C_HZ(100_000)
    ) hdmi_init (
        .clk(CLOCK0_50),
        .reset_n(!ninit_done && KEY[1]),
        .interrupt_n(HDMI_TX_INT),
        .scl(HDMI_I2C_SCL),
        .sda(HDMI_I2C_SDA),
        .done(hdmi_init_done),
        .ack_error(hdmi_init_error),
        .status_valid(hdmi_status_valid),
        .transmitter_powered(hdmi_transmitter_powered),
        .hpd_high(hdmi_hpd_high),
        .monitor_sense(hdmi_monitor_sense),
        .pll_locked(hdmi_pll_locked),
        .tmds_outputs_powered(hdmi_tmds_powered),
        .edid_ready(hdmi_edid_ready),
        .ddc_state(hdmi_ddc_state),
        .ddc_error(hdmi_ddc_error),
        .raw_status(hdmi_raw_status)
    );

    always_ff @(posedge clk_sys) begin
        if (core_reset)
            heartbeat <= '0;
        else
            heartbeat <= heartbeat + 1'b1;
    end

    always_comb begin
        LED[0] = all_plls_locked;
        LED[1] = !fabric_reset;
        LED[2] = !core_reset;
        LED[3] = ddram_read | ddram_write;
        LED[4] = hdmi_init_done;
        LED[5] = hdmi_hpd_high;
        LED[6] = hdmi_pll_locked;
        LED[7] = hdmi_init_error ? heartbeat[20] : heartbeat[26];
    end

    // Present in the official board top and retained here so the pin stays a
    // harmless input.  The fan is autonomous on DE25-Nano.
    wire unused_fan_alert = FAN_ALERT_n;
    wire unused_video_ce = video_ce;
    wire [2:0] unused_hps_led = hps_led_out;

endmodule
