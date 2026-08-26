`timescale 1ns/1ps

module de25_mister_osd_bridge_tb;
    logic clk_sys = 0;
    logic clk_video = 0;
    logic reset = 1;
    logic [31:0] hps_gp_out = 0;
    logic [31:0] hps_gp_in;
    logic [31:0] gp_out_sync;
    logic [15:0] io_din;
    logic io_fpga;
    logic io_uio;
    logic io_strobe;
    logic io_ack;
    logic [1:0] core_reset_state;
    logic osd_status;
    wire io_osd = gp_out_sync[19] & ~gp_out_sync[18];
    wire [23:0] video_out;
    wire de_out;
    wire vs_out;
    wire hs_out;

    always #5 clk_sys = ~clk_sys;
    always #7 clk_video = ~clk_video;

    de25_mister_gp_bridge #(.CORE_TYPE(8'hA4)) bridge (
        .clk_sys(clk_sys),
        .reset(reset),
        .hps_gp_out(hps_gp_out),
        .hps_gp_in(hps_gp_in),
        .gp_out_sync(gp_out_sync),
        .btn_user(1'b0),
        .btn_osd(1'b0),
        .osd_status(osd_status),
        .io_dig(1'b0),
        .hdmi_int_n(1'b1),
        .io_ver(2'b01),
        .io_wait(1'b0),
        .vs_wait(1'b0),
        .io_wide(1'b0),
        .io_dout(16'd0),
        .io_dout_sys(16'd0),
        .diagnostic(6'd0),
        .io_din(io_din),
        .io_fpga(io_fpga),
        .io_uio(io_uio),
        .io_strobe(io_strobe),
        .io_ack(io_ack),
        .core_reset_state(core_reset_state)
    );

    osd compositor (
        .clk_sys(clk_sys),
        .menu_core(1'b0),
        .force_highres(1'b1),
        .io_osd(io_osd),
        .io_strobe(io_strobe),
        .io_din(io_din),
        .clk_video(clk_video),
        .din(24'h404040),
        .de_in(1'b1),
        .vs_in(1'b0),
        .hs_in(1'b0),
        .dout(video_out),
        .de_out(de_out),
        .vs_out(vs_out),
        .hs_out(hs_out),
        .osd_status(osd_status)
    );

    task automatic osd_command(input logic [7:0] command);
        begin
            hps_gp_out <= 32'h80080000 | command;
            repeat (3) @(posedge clk_sys);
            hps_gp_out[17] <= 1'b1;
            wait (io_strobe);
            repeat (2) @(posedge clk_sys);
            hps_gp_out[17] <= 1'b0;
            wait (!io_ack);
            hps_gp_out[19] <= 1'b0;
            repeat (4) @(posedge clk_sys);
        end
    endtask

    task automatic check_condition(input logic condition, input string message);
        if (!condition) begin
            $error("FAIL: %s", message);
            $finish(1);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk_sys);
        reset <= 0;
        repeat (3) @(posedge clk_sys);

        osd_command(8'h41);
        check_condition(osd_status, "OSD compositor accepted enable command");
        check_condition(hps_gp_in[27], "Main-visible hardware OSD status asserted");

        check_condition(compositor.osd_h == 22'd128,
                        "scaled-core OSD starts at its full sixteen-line height");

        // Main selects the 16-line OSD by writing line 8 (command 0x28).
        // The Settings page photographed on hardware exposed only its first
        // eight lines, so keep this exact protocol transition covered.
        osd_command(8'h28);
        repeat (2) @(posedge clk_sys);
        check_condition(compositor.osd_h == 22'd128,
                        "scaled-core OSD remains sixteen lines after line 8");

        osd_command(8'h40);
        check_condition(!osd_status, "OSD compositor accepted disable command");
        check_condition(!hps_gp_in[27], "Main-visible hardware OSD status cleared");
        check_condition(compositor.osd_h == 22'd128,
                        "scaled-core OSD preserves sixteen-line height while disabled");

        $display("PASS: DE25 Main-to-OSD bridge enable and status feedback");
        $finish;
    end
endmodule
