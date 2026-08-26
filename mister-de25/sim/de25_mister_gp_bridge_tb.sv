`timescale 1ns/1ps

module de25_mister_gp_bridge_tb;
    logic clk = 0;
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

    always #5 clk = ~clk;

    de25_mister_gp_bridge #(.CORE_TYPE(8'hA4)) dut (
        .clk_sys(clk),
        .reset(reset),
        .hps_gp_out(hps_gp_out),
        .hps_gp_in(hps_gp_in),
        .gp_out_sync(gp_out_sync),
        .btn_user(1'b1),
        .btn_osd(1'b0),
        .osd_status(1'b1),
        .io_dig(1'b1),
        .hdmi_int_n(1'b0),
        .io_ver(2'b01),
        .io_wait(1'b0),
        .vs_wait(1'b0),
        .io_wide(1'b1),
        .io_dout(16'h1200),
        .io_dout_sys(16'h0034),
        .diagnostic(6'd0),
        .io_din(io_din),
        .io_fpga(io_fpga),
        .io_uio(io_uio),
        .io_strobe(io_strobe),
        .io_ack(io_ack),
        .core_reset_state(core_reset_state)
    );

    task automatic check_condition(input logic condition, input string message);
        if (!condition) begin
            $error("FAIL: %s", message);
            $finish(1);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset <= 0;
        repeat (3) @(posedge clk);
        check_condition(hps_gp_in == 32'h5CA623A4, "core identity word");

        // Select the live response and the core-side SPI target. The write is
        // visible after the two-stage clock-domain crossing.
        hps_gp_out <= 32'h8004A55A;
        repeat (3) @(posedge clk);
        #1;
        check_condition(io_din == 16'hA55A, "HPS data reaches io_din");
        check_condition(io_fpga && !io_uio, "FPGA target decode");
        check_condition(core_reset_state == 2'b10, "run/reset bits preserved");
        check_condition(hps_gp_in[15:0] == 16'h1234, "response words are ORed");
        check_condition(hps_gp_in[30:28] == 3'b101, "button and digital flags");
        check_condition(hps_gp_in[27] == 1'b1, "OSD compositor status");
        check_condition(hps_gp_in[20] == 1'b1, "active-low HDMI interrupt converted");
        check_condition(hps_gp_in[19:18] == 2'b01, "I/O protocol version");
        check_condition(hps_gp_in[16] == 1'b1, "wide transfer flag");

        // Raise the software strobe. It appears as a one-cycle io_strobe and
        // is followed by the acknowledge level expected by Main_MiSTer.
        hps_gp_out[17] <= 1'b1;
        wait (io_strobe);
        #1;
        check_condition(io_strobe, "rising transfer strobe");
        repeat (2) @(posedge clk);
        #1;
        check_condition(io_ack, "transfer acknowledge rises");

        hps_gp_out[17] <= 1'b0;
        repeat (4) @(posedge clk);
        #1;
        check_condition(!io_ack, "transfer acknowledge falls");

        $display("PASS: DE25 MiSTer GPO/GPI bridge protocol");
        $finish;
    end
endmodule
