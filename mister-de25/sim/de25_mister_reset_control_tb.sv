`timescale 1ns/1ps
`default_nettype none

module de25_mister_reset_control_tb;
    logic clk = 1'b0;
    logic fabric_reset_request = 1'b1;
    logic hps_reset_request = 1'b1;
    logic [1:0] core_reset_state = 2'd0;
    wire reset_request;
    wire guarded_reset_request;

    always #5 clk = ~clk;

    de25_mister_reset_control #(
        .STANDALONE_RELEASE_CYCLES(4)
    ) dut (
        .clk_sys(clk),
        .fabric_reset_request(fabric_reset_request),
        .hps_reset_request(hps_reset_request),
        .core_reset_state(core_reset_state),
        .reset_request(reset_request)
    );

    de25_mister_reset_control #(
        .STANDALONE_RELEASE_CYCLES(4),
        .ALLOW_STANDALONE_RELEASE(1'b0)
    ) guarded_dut (
        .clk_sys(clk),
        .fabric_reset_request(fabric_reset_request),
        .hps_reset_request(hps_reset_request),
        .core_reset_state(core_reset_state),
        .reset_request(guarded_reset_request)
    );

    initial begin
        repeat (2) @(posedge clk);
        fabric_reset_request <= 1'b0;
        // Blank-SD HPS reset must not prevent standalone startup.
        repeat (3) @(posedge clk);
        if (!reset_request)
            $fatal(1, "standalone reset released too early");
        @(posedge clk);
        #1;
        if (reset_request)
            $fatal(1, "standalone reset did not release");
        if (!guarded_reset_request)
            $fatal(1, "guarded core released before Main took ownership");

        hps_reset_request <= 1'b0;
        repeat (3) @(posedge clk);

        core_reset_state <= 2'd1;
        @(posedge clk);
        #1;
        if (!reset_request)
            $fatal(1, "Main assert command was ignored");

        core_reset_state <= 2'd0;
        repeat (6) @(posedge clk);
        if (!reset_request)
            $fatal(1, "timeout overrode a Main assert command");

        core_reset_state <= 2'd2;
        @(posedge clk);
        #1;
        if (reset_request)
            $fatal(1, "Main release command was ignored");
        if (guarded_reset_request)
            $fatal(1, "Main did not release the guarded core");

        core_reset_state <= 2'd0;
        hps_reset_request <= 1'b1;
        repeat (3) @(posedge clk);
        #1;
        if (!reset_request)
            $fatal(1, "HPS reset was ignored after Main took ownership");
        if (!guarded_reset_request)
            $fatal(1, "guarded core ignored HPS reset after Main ownership");

        $display("PASS: standalone reset release and Main override");
        $finish;
    end
endmodule

`default_nettype wire
