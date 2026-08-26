`timescale 1ns/1ps

module menu_sdram_tb;
    logic clk = 1'b0;
    logic clk_capture = 1'b0;
    logic init = 1'b1;
    logic [15:0] dq_in = 16'hffff;
    wire [15:0] dq_out;
    wire dq_oe;
    wire [12:0] sdram_a;
    wire [1:0] sdram_ba;
    wire sdram_dqml;
    wire sdram_dqmh;
    wire sdram_ncs;
    wire sdram_nwe;
    wire sdram_nras;
    wire sdram_ncas;
    wire sdram_clk;
    wire sdram_cke;
    logic [1:0] wtbt = 2'b11;
    logic [26:0] addr = 27'h0123456;
    wire [15:0] dout;
    logic [15:0] din = 16'ha55a;
    logic we = 1'b0;
    logic rd = 1'b0;
    wire ready;

    always #5 clk = ~clk;
    initial begin
        #6.5 clk_capture = 1'b1;
        forever #5 clk_capture = ~clk_capture;
    end

    sdram dut (
        .init(init),
        .clk(clk),
        .clk_capture(clk_capture),
        .SDRAM_DQ_IN(dq_in),
        .SDRAM_DQ_OUT(dq_out),
        .SDRAM_DQ_OE(dq_oe),
        .SDRAM_A(sdram_a),
        .SDRAM_DQML(sdram_dqml),
        .SDRAM_DQMH(sdram_dqmh),
        .SDRAM_BA(sdram_ba),
        .SDRAM_nCS(sdram_ncs),
        .SDRAM_nWE(sdram_nwe),
        .SDRAM_nRAS(sdram_nras),
        .SDRAM_nCAS(sdram_ncas),
        .SDRAM_CLK(sdram_clk),
        .SDRAM_CKE(sdram_cke),
        .wtbt(wtbt),
        .addr(addr),
        .dout(dout),
        .din(din),
        .we(we),
        .rd(rd),
        .ready(ready)
    );

    initial begin
        integer timeout;
        repeat (4) @(posedge clk);
        init <= 1'b0;

        timeout = 0;
        while (ready !== 1'b1 && timeout < 20000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (ready !== 1'b1)
            $fatal(1, "SDRAM controller did not finish initialization: count=%h ready=%b state=%0d", dut.refresh_count, ready, dut.state);

        @(posedge clk);
        we <= 1'b1;
        @(posedge clk);
        we <= 1'b0;

        timeout = 0;
        while (dq_oe !== 1'b1 && timeout < 20) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (dq_oe !== 1'b1)
            $fatal(1, "SDRAM controller did not drive a write");
        if (dq_out !== din)
            $fatal(1, "SDRAM write data mismatch: %h", dq_out);
        if (sdram_nwe !== 1'b0)
            $fatal(1, "SDRAM write-enable command was not asserted");

        dq_in <= 16'h3cc3;
        @(posedge clk);
        rd <= 1'b1;
        @(posedge clk);
        rd <= 1'b0;

        timeout = 0;
        while (ready !== 1'b0 && timeout < 20) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (ready !== 1'b0)
            $fatal(1, "SDRAM controller did not accept a read");

        timeout = 0;
        while (ready !== 1'b1 && timeout < 40) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (ready !== 1'b1)
            $fatal(1, "SDRAM controller did not finish a read");
        if (dout !== 16'h3cc3)
            $fatal(1, "SDRAM captured read data mismatch: %h", dout);

        $display("PASS: Menu SDRAM initialization, write, and read capture");
        $finish;
    end
endmodule
