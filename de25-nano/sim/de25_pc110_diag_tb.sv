`timescale 1ns/1ps

module de25_pc110_diag_tb;
    logic CLOCK0_50 = 1'b0;
    logic CLOCK1_50 = 1'b0;
    logic CLOCK2_50 = 1'b0;
    logic [1:0] KEY = 2'b11;
    logic [3:0] SW = 4'b0000;
    wire [7:0] LED;
    tri1 HDMI_LRCLK;
    tri1 HDMI_MCLK;
    tri1 HDMI_SCLK;
    wire HDMI_TX_CLK;
    wire HDMI_TX_HS;
    wire HDMI_TX_VS;
    wire [23:0] HDMI_TX_D;
    wire HDMI_TX_DE;
    tri1 HDMI_I2C_SCL;
    tri1 HDMI_I2C_SDA;
    logic HDMI_TX_INT = 1'b1;
    tri1 HDMI_I2S;

    always #10 CLOCK0_50 = ~CLOCK0_50;
    always #10 CLOCK1_50 = ~CLOCK1_50;
    always #10 CLOCK2_50 = ~CLOCK2_50;

    de25_pc110_diag dut (.*);

    initial begin : check_first_video_line
        integer pixels;
        integer active_pixels;
        integer sync_pixels;
        integer start_line;

        // Skip the hardware power-on delay. The delay counter itself is
        // synthesis-only board protection, while this test checks video.
        force dut.power_on_reset = '1;
        repeat (4) @(negedge HDMI_TX_CLK);

        // Start at a clean line boundary.
        while (dut.h_count != 0)
            @(negedge HDMI_TX_CLK);
        start_line = dut.v_count;

        active_pixels = 0;
        sync_pixels = 0;
        for (pixels = 0; pixels < 800; pixels = pixels + 1) begin
            @(negedge HDMI_TX_CLK);
            #1;
            if (HDMI_TX_DE)
                active_pixels = active_pixels + 1;
            if (!HDMI_TX_HS)
                sync_pixels = sync_pixels + 1;
        end

        if (active_pixels != 640)
            $fatal(1, "active pixel count %0d, expected 640", active_pixels);
        if (sync_pixels != 96)
            $fatal(1, "HSYNC width %0d, expected 96", sync_pixels);
        if (dut.h_count != 0)
            $fatal(1, "line did not roll over, h_count=%0d", dut.h_count);
        if (dut.v_count != start_line + 1)
            $fatal(1, "line did not advance once, v_count=%0d start=%0d",
                   dut.v_count, start_line);

        $display("PASS: DE25 diagnostic produces 640 active pixels and 96-pixel HSYNC");
        $finish;
    end
endmodule
