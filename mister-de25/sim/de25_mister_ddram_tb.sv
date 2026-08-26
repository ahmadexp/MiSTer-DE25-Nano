`timescale 1ns/1ps

module de25_mister_ddram_tb;
    logic reset = 1;
    logic [7:0] core_burstcount = 8'd1;
    logic [28:0] core_address = 29'h04000000;
    logic core_busy;
    logic [63:0] core_readdata;
    logic core_readdatavalid;
    logic core_read = 0;
    logic [63:0] core_writedata = 64'h0123456789ABCDEF;
    logic [7:0] core_byteenable = 8'hF0;
    logic core_write = 0;
    logic av_waitrequest = 0;
    logic [63:0] av_readdata = 64'hFEDCBA9876543210;
    logic av_readdatavalid = 0;
    logic [7:0] av_burstcount;
    logic [31:0] av_address;
    logic [63:0] av_writedata;
    logic [7:0] av_byteenable;
    logic av_read;
    logic av_write;

    de25_mister_ddram dut (.*);

    initial begin
        #1;
        if (!core_busy || av_read || av_write) $fatal(1, "reset gating failed");
        reset = 0;
        core_read = 1;
        #1;
        if (core_busy || !av_read || av_write) $fatal(1, "read forwarding failed");
        if (av_address !== 32'hA0000000)
            $fatal(1, "address translation failed: %h", av_address);
        core_address = 29'h06000000;
        #1;
        if (av_address !== 32'hB0000000)
            $fatal(1, "upper-half address translation aliased: %h", av_address);
        core_read = 0;
        core_write = 1;
        #1;
        if (!av_write || av_writedata !== core_writedata || av_byteenable !== 8'hF0)
            $fatal(1, "write forwarding failed");
        av_waitrequest = 1;
        #1;
        if (!core_busy) $fatal(1, "waitrequest forwarding failed");
        av_readdatavalid = 1;
        #1;
        if (!core_readdatavalid || core_readdata !== av_readdata)
            $fatal(1, "read response forwarding failed");
        $display("PASS: DE25 MiSTer DDRAM adapter");
        $finish;
    end
endmodule
