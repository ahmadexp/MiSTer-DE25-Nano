`timescale 1ns/1ps

module sms_sdram_tb;
    logic clk = 1'b0;
    logic clkref = 1'b0;
    logic init = 1'b0;
    logic active = 1'b1;
    logic quiesce = 1'b0;
    logic [15:0] dq_in = 16'h3cc3;
    logic rd = 1'b0;
    wire rd_rdy;
    wire [7:0] dout;

    always #5 clk = ~clk;

    sdram dut (
        .SDRAM_DQ_IN(dq_in),
        .SDRAM_DQ_OUT(),
        .SDRAM_DQ_OE(),
        .SDRAM_A(),
        .SDRAM_DQML(),
        .SDRAM_DQMH(),
        .SDRAM_BA(),
        .SDRAM_nCS(),
        .SDRAM_nWE(),
        .SDRAM_nRAS(),
        .SDRAM_nCAS(),
        .SDRAM_CKE(),
        .init(init),
        .clk(clk),
        .clkref(clkref),
        .clk_capture(clk),
        .active(active),
        .quiesce(quiesce),
        .quiesced(),
        .raddr(25'd0),
        .rd(rd),
        .rd_rdy(rd_rdy),
        .dout(dout),
        .waddr(25'd0),
        .din(8'd0),
        .we(1'b0),
        .we_ack()
    );

    initial begin
        integer timeout;

        // Establish the controller's power-on state, then provide the
        // clkref edge that starts a transaction slot.
        dut.q = dut.STATE_IDLE;
        dut.mode = dut.MODE_NORMAL;
        dut.ram_req = 1'b0;
        dut.rd_rdy = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk);
        clkref <= 1'b1;
        @(posedge clk);
        @(negedge clk);
        clkref <= 1'b0;
        rd <= 1'b1;

        timeout = 0;
        while (!dut.ram_req && timeout < 20) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!dut.ram_req)
            $fatal(1, "SMS SDRAM controller did not accept read");
        rd <= 1'b0;

        timeout = 0;
        while (dut.data_capture != 16'h3cc3 && timeout < 20) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end
        if (dut.data_capture != 16'h3cc3)
            $fatal(1, "SMS SDRAM capture register missed read data");
        if (rd_rdy)
            $fatal(1, "SMS SDRAM exposed data before the pipeline transfer");

        @(posedge clk);
        #1;
        if (!rd_rdy || dout != 8'hc3)
            $fatal(1, "SMS SDRAM delayed read mismatch: ready=%b data=%h",
                   rd_rdy, dout);

        $display("PASS: SMS SDRAM read capture precedes controller ready");
        $finish;
    end
endmodule
