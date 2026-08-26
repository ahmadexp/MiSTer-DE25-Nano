`timescale 1ns/1ps

module de25_hps_warm_reset_handshake_tb;
    logic clk = 1'b0;
    logic reset_req_n = 1'b1;
    wire reset_ack_n;
    wire reset_pending;

    always #5 clk = ~clk;

    de25_hps_warm_reset_handshake dut (
        .clk(clk),
        .reset_req_n(reset_req_n),
        .reset_ack_n(reset_ack_n),
        .reset_pending(reset_pending)
    );

    initial begin
        #1;
        if (reset_ack_n !== 1'b1 || reset_pending !== 1'b0)
            $fatal(1, "handshake must start idle");

        repeat (2) @(posedge clk);
        #1;
        if (reset_ack_n !== 1'b1 || reset_pending !== 1'b0)
            $fatal(1, "idle handshake changed without a request");

        #2 reset_req_n = 1'b0;
        #1;
        if (reset_ack_n !== 1'b1 || reset_pending !== 1'b1)
            $fatal(1, "reset did not assert before acknowledgement");

        repeat (2) @(posedge clk);
        #1;
        if (reset_ack_n !== 1'b1 || reset_pending !== 1'b1)
            $fatal(1, "reset request was acknowledged before soft reset settled");

        @(posedge clk);
        #1;
        if (reset_ack_n !== 1'b0 || reset_pending !== 1'b1)
            $fatal(1, "active-low reset request was not acknowledged");

        #7 reset_req_n = 1'b1;
        repeat (2) @(posedge clk);
        #1;
        if (reset_ack_n !== 1'b0 || reset_pending !== 1'b1)
            $fatal(1, "warm reset released before request synchronization");

        @(posedge clk);
        #1;
        if (reset_ack_n !== 1'b0 || reset_pending !== 1'b1)
            $fatal(1, "soft reset released before acknowledgement");

        @(posedge clk);
        #1;
        if (reset_ack_n !== 1'b1 || reset_pending !== 1'b0)
            $fatal(1, "warm-reset acknowledgement did not release");

        $display("PASS: active-low Agilex HPS warm-reset acknowledgement follows soft reset");
        $finish;
    end
endmodule
