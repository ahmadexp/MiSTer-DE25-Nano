// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

module de25_nes_standalone_top (
    input  wire        CLOCK0_50,
    input  wire [1:0]  KEY,
    output logic [7:0] LED,

    output wire        DRAM_CLK,
    output wire        DRAM_CKE,
    output wire [12:0] DRAM_ADDR,
    output wire [1:0]  DRAM_BA,
    inout  wire [15:0] DRAM_DQ,
    output wire        DRAM_LDQM,
    output wire        DRAM_UDQM,
    output wire [1:0]  DRAM_CS_n,
    output wire        DRAM_WE_n,
    output wire        DRAM_CAS_n,
    output wire        DRAM_RAS_n,

    inout  wire        HDMI_LRCLK,
    inout  wire        HDMI_MCLK,
    inout  wire        HDMI_SCLK,
    output wire        HDMI_TX_CLK,
    output wire        HDMI_TX_HS,
    output wire        HDMI_TX_VS,
    output wire [23:0] HDMI_TX_D,
    output wire        HDMI_TX_DE,
    inout  wire        HDMI_I2C_SCL,
    inout  wire        HDMI_I2C_SDA,
    input  wire        HDMI_TX_INT,
    inout  wire        HDMI_I2S
);
    wire clk_hps_unused;
    wire clk_audio;
    wire clk_video_out;
    wire platform_locked;

    mister_pll platform_clocks (
        .refclk_clk(CLOCK0_50),
        .reset_reset(~KEY[0]),
        .locked_export(platform_locked),
        .outclk0_clk(clk_hps_unused),
        .outclk1_clk(clk_audio),
        .outclk2_clk(clk_video_out)
    );

    tri [45:0] hps_bus;
    wire core_clk_video;
    wire core_ce_pixel;
    wire [7:0] core_r;
    wire [7:0] core_g;
    wire [7:0] core_b;
    wire core_hs;
    wire core_vs;
    wire core_de;
    wire core_f1;
    wire [1:0] core_scanlines;
    wire [15:0] audio_left;
    wire [15:0] audio_right;
    wire audio_signed;
    wire core_led_user;
    wire [1:0] core_led_power;
    wire [1:0] core_led_disk;
    wire [1:0] core_buttons;
    wire core_uart_tx;
    wire core_uart_rts;
    wire core_uart_dtr;
    wire [6:0] core_user_out;
    wire [3:0] adc_bus;

    // PLL lock and the pushbutton are asynchronous to every generated clock.
    // Assert all resets immediately, then release each one only after three
    // edges in its own destination domain.
    wire fabric_reset_request = ~KEY[0] | ~platform_locked;
    (* ASYNC_REG = "TRUE" *) logic [2:0] core_reset_pipe = 3'b111;
    (* ASYNC_REG = "TRUE" *) logic [2:0] video_in_reset_pipe = 3'b111;
    (* ASYNC_REG = "TRUE" *) logic [2:0] video_out_reset_pipe = 3'b111;
    (* ASYNC_REG = "TRUE" *) logic [2:0] audio_reset_pipe = 3'b111;

    always_ff @(posedge hps_bus[36] or posedge fabric_reset_request) begin
        if (fabric_reset_request)
            core_reset_pipe <= 3'b111;
        else
            core_reset_pipe <= {core_reset_pipe[1:0], 1'b0};
    end

    always_ff @(posedge core_clk_video or posedge fabric_reset_request) begin
        if (fabric_reset_request)
            video_in_reset_pipe <= 3'b111;
        else
            video_in_reset_pipe <= {video_in_reset_pipe[1:0], 1'b0};
    end

    always_ff @(posedge clk_video_out or posedge fabric_reset_request) begin
        if (fabric_reset_request)
            video_out_reset_pipe <= 3'b111;
        else
            video_out_reset_pipe <= {video_out_reset_pipe[1:0], 1'b0};
    end

    always_ff @(posedge clk_audio or posedge fabric_reset_request) begin
        if (fabric_reset_request)
            audio_reset_pipe <= 3'b111;
        else
            audio_reset_pipe <= {audio_reset_pipe[1:0], 1'b0};
    end

    wire core_reset = core_reset_pipe[2];
    wire video_in_reset = video_in_reset_pipe[2];
    wire video_out_reset = video_out_reset_pipe[2];
    wire audio_reset = audio_reset_pipe[2];

    // Feedback fields normally supplied by sys_top. The autoload hps_io
    // replacement drives the clock, wait, width, and read-data fields.
    assign hps_bus[45] = core_f1;
    assign hps_bus[44] = core_vs;
    assign hps_bus[43] = clk_hps_unused;
    assign hps_bus[42] = core_clk_video;
    assign hps_bus[41] = core_ce_pixel;
    assign hps_bus[40] = core_de;
    assign hps_bus[39] = core_hs;
    assign hps_bus[38] = core_vs;
    assign hps_bus[35:33] = 3'b000;
    assign hps_bus[31:16] = 16'd0;

    wire        core_sdram_clk;
    wire        core_sdram_cke;
    wire [12:0] core_sdram_addr;
    wire [1:0]  core_sdram_ba;
    wire [15:0] core_sdram_dq_out;
    wire        core_sdram_dq_oe;
    wire        core_sdram_dqml;
    wire        core_sdram_dqmh;
    wire        core_sdram_ncs;
    wire        core_sdram_ncas;
    wire        core_sdram_nras;
    wire        core_sdram_nwe;

    emu core (
        .CLK_50M(CLOCK0_50),
        .RESET(core_reset),
        .HPS_BUS(hps_bus),
        .CLK_VIDEO(core_clk_video),
        .CE_PIXEL(core_ce_pixel),
        .VIDEO_ARX(),
        .VIDEO_ARY(),
        .VGA_R(core_r),
        .VGA_G(core_g),
        .VGA_B(core_b),
        .VGA_HS(core_hs),
        .VGA_VS(core_vs),
        .VGA_DE(core_de),
        .VGA_F1(core_f1),
        .VGA_SL(core_scanlines),
        .VGA_SCALER(),
        .VGA_DISABLE(),
        .HDMI_WIDTH(12'd640),
        .HDMI_HEIGHT(12'd480),
        .HDMI_FREEZE(),
        .HDMI_BLACKOUT(),
        .HDMI_BOB_DEINT(),
        .LED_USER(core_led_user),
        .LED_POWER(core_led_power),
        .LED_DISK(core_led_disk),
        .BUTTONS(core_buttons),
        .CLK_AUDIO(clk_audio),
        .AUDIO_L(audio_left),
        .AUDIO_R(audio_right),
        .AUDIO_S(audio_signed),
        .AUDIO_MIX(),
        .ADC_BUS(adc_bus),
        .SD_SCK(),
        .SD_MOSI(),
        .SD_MISO(1'b1),
        .SD_CS(),
        .SD_CD(1'b1),
        .DDRAM_CLK(),
        .DDRAM_BUSY(1'b0),
        .DDRAM_BURSTCNT(),
        .DDRAM_ADDR(),
        .DDRAM_DOUT(64'd0),
        .DDRAM_DOUT_READY(1'b0),
        .DDRAM_RD(),
        .DDRAM_DIN(),
        .DDRAM_BE(),
        .DDRAM_WE(),
        .SDRAM_CLK(core_sdram_clk),
        .SDRAM_CKE(core_sdram_cke),
        .SDRAM_A(core_sdram_addr),
        .SDRAM_BA(core_sdram_ba),
        .de25_sdram_dq_in(16'd0),
        .de25_sdram_dq_out(core_sdram_dq_out),
        .de25_sdram_dq_oe(core_sdram_dq_oe),
        .SDRAM_DQML(core_sdram_dqml),
        .SDRAM_DQMH(core_sdram_dqmh),
        .SDRAM_nCS(core_sdram_ncs),
        .SDRAM_nCAS(core_sdram_ncas),
        .SDRAM_nRAS(core_sdram_nras),
        .SDRAM_nWE(core_sdram_nwe),
        .UART_CTS(1'b0),
        .UART_RTS(core_uart_rts),
        .UART_RXD(1'b1),
        .UART_TXD(core_uart_tx),
        .UART_DTR(core_uart_dtr),
        .UART_DSR(1'b0),
        .USER_IN(7'h7f),
        .USER_OUT(core_user_out),
        .OSD_STATUS(1'b0)
    );

    wire [23:0] scaled_rgb;
    wire scaled_de;
    wire scaled_hs;
    wire scaled_vs;
    wire input_frame_seen;
    wire [7:0] diagnostic;

    // Observe the byte at the CPU boundary, after cartridge memory latency.
    // This distinguishes correct M20K contents from data which arrives on the
    // wrong NES cycle. The first six flags cover the reset vector and first
    // opcode; the last two prove that program execution reaches both PPU
    // display-control registers.
    wire        nes_master_clk = core.clk;
    wire        nes_reset = core.reset_nes;
    wire        nes_cpu_ce = core.nes.cpu_ce;
    wire        nes_cpu_rnw = core.nes.cpu_rnw;
    wire [15:0] nes_cpu_addr = core.nes.cpu_addr;
    wire  [7:0] nes_cpu_data = core.nes.internal_data_bus;
    logic reset_low_seen = 1'b0;
    logic reset_low_correct = 1'b0;
    logic reset_high_seen = 1'b0;
    logic reset_high_correct = 1'b0;
    logic first_opcode_seen = 1'b0;
    logic first_opcode_correct = 1'b0;
    logic ppu_ctrl_write_seen = 1'b0;
    logic ppu_mask_write_seen = 1'b0;

    always_ff @(posedge nes_master_clk) begin
        if (nes_reset) begin
            reset_low_seen <= 1'b0;
            reset_low_correct <= 1'b0;
            reset_high_seen <= 1'b0;
            reset_high_correct <= 1'b0;
            first_opcode_seen <= 1'b0;
            first_opcode_correct <= 1'b0;
            ppu_ctrl_write_seen <= 1'b0;
            ppu_mask_write_seen <= 1'b0;
        end else if (nes_cpu_ce) begin
            if (nes_cpu_rnw && nes_cpu_addr == 16'hfffc) begin
                reset_low_seen <= 1'b1;
                if (nes_cpu_data == 8'h00)
                    reset_low_correct <= 1'b1;
            end
            if (nes_cpu_rnw && nes_cpu_addr == 16'hfffd) begin
                reset_high_seen <= 1'b1;
                if (nes_cpu_data == 8'h80)
                    reset_high_correct <= 1'b1;
            end
            if (nes_cpu_rnw && nes_cpu_addr == 16'h8000) begin
                first_opcode_seen <= 1'b1;
                if (nes_cpu_data == 8'h78)
                    first_opcode_correct <= 1'b1;
            end
            if (!nes_cpu_rnw && nes_cpu_addr == 16'h2000)
                ppu_ctrl_write_seen <= 1'b1;
            if (!nes_cpu_rnw && nes_cpu_addr == 16'h2001)
                ppu_mask_write_seen <= 1'b1;
        end
    end

    de25_nes_framebuffer framebuffer (
        .in_reset(video_in_reset),
        .out_reset(video_out_reset),
        .in_clk(core_clk_video),
        .in_ce(core_ce_pixel),
        .in_rgb({core_r, core_g, core_b}),
        .in_de(core_de),
        .in_vs(core_vs),
        .out_clk(clk_video_out),
        .diagnostic(diagnostic),
        .out_rgb(scaled_rgb),
        .out_de(scaled_de),
        .out_hs(scaled_hs),
        .out_vs(scaled_vs),
        .input_frame_seen(input_frame_seen)
    );

    wire audio_bit_clock;
    wire audio_word_clock;
    wire audio_data;
    de25_mister_audio audio (
        .clk_audio(clk_audio),
        .reset(audio_reset),
        .core_left(audio_left),
        .core_right(audio_right),
        .core_signed(audio_signed),
        .bit_clock(audio_bit_clock),
        .word_clock(audio_word_clock),
        .serial_data(audio_data)
    );

    assign HDMI_TX_CLK = ~clk_video_out;
    assign HDMI_TX_D = scaled_rgb;
    assign HDMI_TX_DE = scaled_de;
    assign HDMI_TX_HS = scaled_hs;
    assign HDMI_TX_VS = scaled_vs;
    assign HDMI_MCLK = clk_audio;
    assign HDMI_SCLK = audio_bit_clock;
    assign HDMI_LRCLK = audio_word_clock;
    assign HDMI_I2S = audio_data;

    logic [19:0] hdmi_power_on_reset = '0;
    always_ff @(posedge CLOCK0_50) begin
        if (!KEY[0])
            hdmi_power_on_reset <= '0;
        else if (!(&hdmi_power_on_reset))
            hdmi_power_on_reset <= hdmi_power_on_reset + 1'b1;
    end

    wire hdmi_init_done;
    wire hdmi_init_error;
    wire hdmi_hpd_high;
    wire hdmi_pll_locked;
    // The framebuffer displays these flags as eight left-to-right blocks.
    assign diagnostic = {
        ppu_mask_write_seen,
        ppu_ctrl_write_seen,
        first_opcode_correct,
        first_opcode_seen,
        reset_high_correct,
        reset_high_seen,
        reset_low_correct,
        reset_low_seen
    };
    adv7513_init hdmi_init (
        .clk(CLOCK0_50),
        .reset_n(KEY[1] & (&hdmi_power_on_reset)),
        .interrupt_n(HDMI_TX_INT),
        .scl(HDMI_I2C_SCL),
        .sda(HDMI_I2C_SDA),
        .done(hdmi_init_done),
        .ack_error(hdmi_init_error),
        .status_valid(),
        .transmitter_powered(),
        .hpd_high(hdmi_hpd_high),
        .monitor_sense(),
        .pll_locked(hdmi_pll_locked),
        .tmds_outputs_powered(),
        .edid_ready(),
        .ddc_state(),
        .ddc_error(),
        .raw_status()
    );

    // The physical SDRAM is not used by this diagnostic and remains safely
    // deselected. The on-chip memory module consumes the core's logical bus.
    assign DRAM_CLK = 1'b0;
    assign DRAM_CKE = 1'b0;
    assign DRAM_ADDR = 13'd0;
    assign DRAM_BA = 2'd0;
    assign DRAM_DQ = 16'bz;
    assign DRAM_LDQM = 1'b1;
    assign DRAM_UDQM = 1'b1;
    assign DRAM_CS_n = 2'b11;
    assign DRAM_WE_n = 1'b1;
    assign DRAM_CAS_n = 1'b1;
    assign DRAM_RAS_n = 1'b1;

    always_comb begin
        LED[0] = platform_locked;
        LED[1] = hdmi_init_done;
        LED[2] = hdmi_hpd_high;
        LED[3] = hdmi_pll_locked;
        LED[4] = core_led_user;
        LED[5] = input_frame_seen;
        LED[6] = scaled_de;
        LED[7] = hdmi_init_error;
    end

    wire unused = &{1'b0, core_uart_tx, core_scanlines,
                    core_led_power, core_led_disk, core_buttons,
                    core_uart_rts, core_uart_dtr, core_user_out, adc_bus,
                    core_sdram_clk, core_sdram_cke, core_sdram_addr,
                    core_sdram_ba, core_sdram_dq_out,
                    core_sdram_dq_oe, core_sdram_dqml,
                    core_sdram_dqmh, core_sdram_ncs, core_sdram_ncas,
                    core_sdram_nras, core_sdram_nwe};
endmodule

`default_nettype wire
