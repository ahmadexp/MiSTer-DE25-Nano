`timescale 1ns/1ps

// DE25-Nano rev-B board diagnostic for the PC110 port.
//
// This image deliberately uses no generated IP. It verifies the exact board
// pinout, all three reference clocks, the ADV7513 I2C path, and parallel HDMI
// video before the PC110 core and Agilex memory/HPS subsystems are introduced.
module de25_pc110_diag (
    input  logic        CLOCK0_50,
    input  logic        CLOCK1_50,
    input  logic        CLOCK2_50,
    input  logic [1:0]  KEY,
    input  logic [3:0]  SW,
    output logic [7:0]  LED,

    inout  wire         HDMI_LRCLK,
    inout  wire         HDMI_MCLK,
    inout  wire         HDMI_SCLK,
    output wire         HDMI_TX_CLK,
    output logic        HDMI_TX_HS,
    output logic        HDMI_TX_VS,
    output logic [23:0] HDMI_TX_D,
    output logic        HDMI_TX_DE,
    inout  wire         HDMI_I2C_SCL,
    inout  wire         HDMI_I2C_SDA,
    input  logic        HDMI_TX_INT,
    inout  wire         HDMI_I2S
);

    localparam int H_ACTIVE = 640;
    localparam int H_FRONT  = 16;
    localparam int H_SYNC   = 96;
    localparam int H_BACK   = 48;
    localparam int H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam int V_ACTIVE = 480;
    localparam int V_FRONT  = 10;
    localparam int V_SYNC   = 2;
    localparam int V_BACK   = 33;
    localparam int V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    logic [9:0] h_count = '0;
    logic [9:0] v_count = '0;
    logic       pixel_phase = 1'b0;
    logic [25:0] heartbeat0 = '0;
    logic [25:0] heartbeat1 = '0;
    logic [25:0] heartbeat2 = '0;
    logic [19:0] power_on_reset = '0;
    logic [23:0] bars;

    logic init_done;
    logic init_error;
    logic status_valid;
    logic transmitter_powered;
    logic hpd_high;
    logic monitor_sense;
    logic pll_locked;
    logic tmds_outputs_powered;
    logic edid_ready;
    logic [3:0] ddc_state;
    logic [3:0] ddc_error;
    logic [63:0] raw_status;
    logic ninit_done;

    wire reset_n = KEY[0] && &power_on_reset && !ninit_done;
    wire active_video = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    wire hsync_n = !((h_count >= H_ACTIVE + H_FRONT) &&
                     (h_count < H_ACTIVE + H_FRONT + H_SYNC));
    wire vsync_n = !((v_count >= V_ACTIVE + V_FRONT) &&
                     (v_count < V_ACTIVE + V_FRONT + V_SYNC));

    // Terasic's ADV7513 setup samples the 24-bit bus on the falling edge.
    // Change video values on the rising edge of this 25 MHz divide-by-two
    // clock to provide a deterministic half-cycle setup interval.
    assign HDMI_TX_CLK = pixel_phase;

    // No audio is emitted by the diagnostic image.
    assign HDMI_LRCLK = 1'b0;
    assign HDMI_MCLK  = 1'b0;
    assign HDMI_SCLK  = 1'b0;
    assign HDMI_I2S   = 1'b0;

    // Agilex configuration completes asynchronously to the user clocks. The
    // device-specific Reset Release IP holds the design until SDM handoff is
    // complete, then the local counter provides an additional settling delay.
    ResetRelease reset_release (
        .ninit_done(ninit_done)
    );

    always_ff @(posedge CLOCK2_50) begin
        pixel_phase <= ~pixel_phase;

        if (!(&power_on_reset))
            power_on_reset <= power_on_reset + 1'b1;

        heartbeat2 <= heartbeat2 + 1'b1;

        if (!reset_n) begin
            h_count    <= '0;
            v_count    <= '0;
            HDMI_TX_DE <= 1'b0;
            HDMI_TX_HS <= 1'b1;
            HDMI_TX_VS <= 1'b1;
            HDMI_TX_D  <= 24'h000000;
        end else if (!pixel_phase) begin
            HDMI_TX_DE <= active_video;
            HDMI_TX_HS <= hsync_n;
            HDMI_TX_VS <= vsync_n;
            HDMI_TX_D  <= active_video ? (SW[0] ? ~bars : bars) :
                                         24'h000000;

            if (h_count == H_TOTAL - 1) begin
                h_count <= '0;
                if (v_count == V_TOTAL - 1)
                    v_count <= '0;
                else
                    v_count <= v_count + 1'b1;
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end

    always_ff @(posedge CLOCK0_50)
        heartbeat0 <= heartbeat0 + 1'b1;

    always_ff @(posedge CLOCK1_50)
        heartbeat1 <= heartbeat1 + 1'b1;

    always_comb begin
        if (SW[1]) begin
            if      (v_count <  60) bars = 24'hffffff;
            else if (v_count < 120) bars = 24'hffff00;
            else if (v_count < 180) bars = 24'h00ffff;
            else if (v_count < 240) bars = 24'h00ff00;
            else if (v_count < 300) bars = 24'hff00ff;
            else if (v_count < 360) bars = 24'hff0000;
            else if (v_count < 420) bars = 24'h0000ff;
            else                    bars = 24'h000000;
        end else begin
            if      (h_count <  80) bars = 24'hffffff;
            else if (h_count < 160) bars = 24'hffff00;
            else if (h_count < 240) bars = 24'h00ffff;
            else if (h_count < 320) bars = 24'h00ff00;
            else if (h_count < 400) bars = 24'hff00ff;
            else if (h_count < 480) bars = 24'hff0000;
            else if (h_count < 560) bars = 24'h0000ff;
            else                    bars = 24'h000000;
        end
    end

    always_comb begin
        LED[0] = SW[2] ? heartbeat0[25] : init_done;
        LED[1] = SW[2] ? heartbeat1[25] : status_valid;
        LED[2] = SW[2] ? heartbeat2[25] : transmitter_powered;
        LED[3] = hpd_high;
        LED[4] = monitor_sense;
        LED[5] = pll_locked;
        LED[6] = tmds_outputs_powered && edid_ready;
        LED[7] = init_error ? heartbeat2[22] :
                 ((ddc_error != 4'h0) ? heartbeat2[23] : 1'b0);
    end

    adv7513_init #(
        .CLOCK_HZ(50_000_000),
        .I2C_HZ(20_000)
    ) hdmi_init (
        .clk(CLOCK2_50),
        .reset_n(reset_n && KEY[1]),
        .interrupt_n(HDMI_TX_INT),
        .scl(HDMI_I2C_SCL),
        .sda(HDMI_I2C_SDA),
        .done(init_done),
        .ack_error(init_error),
        .status_valid(status_valid),
        .transmitter_powered(transmitter_powered),
        .hpd_high(hpd_high),
        .monitor_sense(monitor_sense),
        .pll_locked(pll_locked),
        .tmds_outputs_powered(tmds_outputs_powered),
        .edid_ready(edid_ready),
        .ddc_state(ddc_state),
        .ddc_error(ddc_error),
        .raw_status(raw_status)
    );

endmodule
