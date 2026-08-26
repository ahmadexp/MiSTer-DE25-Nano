`timescale 1ns/1ps

module de25_iopll_axil_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic write_request;
    logic [8:0] address;
    logic [31:0] writedata;
    logic [31:0] readdata;
    logic busy;
    logic done;
    logic response_error;
    logic timeout_error;
    logic [26:0] awaddr;
    logic awvalid;
    logic awready = 1'b0;
    logic [31:0] wdata;
    logic [3:0] wstrb;
    logic wvalid;
    logic wready = 1'b0;
    logic [1:0] bresp = 2'b00;
    logic bvalid = 1'b0;
    logic bready;
    logic [26:0] araddr;
    logic arvalid;
    logic arready = 1'b0;
    logic [31:0] rdata = 32'd0;
    logic [1:0] rresp = 2'b00;
    logic rvalid = 1'b0;
    logic rready;

    always #5 clk = ~clk;

    de25_iopll_axil dut (
        .clk, .reset, .start, .write_request, .address, .writedata,
        .readdata, .busy, .done, .response_error, .timeout_error,
        .axil_awaddr(awaddr), .axil_awvalid(awvalid), .axil_awready(awready),
        .axil_wdata(wdata), .axil_wstrb(wstrb), .axil_wvalid(wvalid),
        .axil_wready(wready), .axil_bresp(bresp), .axil_bvalid(bvalid),
        .axil_bready(bready), .axil_araddr(araddr), .axil_arvalid(arvalid),
        .axil_arready(arready), .axil_rdata(rdata), .axil_rresp(rresp),
        .axil_rvalid(rvalid), .axil_rready(rready)
    );

    initial begin
        repeat (3) @(negedge clk);
        reset = 1'b0;

        @(negedge clk);
        address = 9'h044;
        writedata = 32'h1234_5678;
        write_request = 1'b1;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        repeat (2) @(negedge clk);
        awready = 1'b1;
        @(negedge clk);
        awready = 1'b0;
        repeat (2) @(negedge clk);
        wready = 1'b1;
        @(negedge clk);
        wready = 1'b0;
        bvalid = 1'b1;
        @(negedge clk);
        bvalid = 1'b0;
        wait (done);

        if (awaddr !== 27'h0A0_0044 || wdata !== 32'h1234_5678 ||
            wstrb !== 4'hF || response_error)
            $fatal(1, "AXI-Lite write transaction mismatch");

        @(negedge clk);
        address = 9'h05C;
        write_request = 1'b0;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        repeat (2) @(negedge clk);
        arready = 1'b1;
        @(negedge clk);
        arready = 1'b0;
        rdata = 32'hCAFE_BABE;
        rvalid = 1'b1;
        @(negedge clk);
        rvalid = 1'b0;
        wait (done);

        if (araddr !== 27'h0A0_005C || readdata !== 32'hCAFE_BABE ||
            response_error)
            $fatal(1, "AXI-Lite read transaction mismatch");

        $display("PASS: Agilex 5 IOPLL EMIF Calibration AXI-Lite transport");
        $finish;
    end
endmodule
