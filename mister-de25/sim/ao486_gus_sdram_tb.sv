`timescale 1ns/1ps

module ao486_gus_sdram_tb;
    logic clk = 1'b0;
    logic clk_physical = 1'b1;
    always #5 clk = ~clk;
    always #5 clk_physical = ~clk_physical;

    logic init = 1'b1;
    logic active = 1'b0;
    logic [27:0] clock_rate = 28'd30_000_000;
    logic [24:0] addr = '0;
    logic [15:0] din = '0;
    logic we = 1'b0;
    logic rd = 1'b0;
    logic word = 1'b1;
    logic [15:0] dq_in = 16'h5aa5;

    wire [15:0] dout;
    wire ready;
    wire [15:0] dq_out;
    wire dq_oe;
    wire [12:0] sdram_a;
    wire [1:0] sdram_ba;
    wire dqml;
    wire dqmh;
    wire ncs;
    wire nwe;
    wire nras;
    wire ncas;
    wire cke;
    wire sdram_clk;

    sdram dut (
        .init,
        .clk,
        .clock_rate,
        .active,
        .clk_physical,
        .SDRAM_DQ_IN(dq_in),
        .SDRAM_DQ_OUT(dq_out),
        .SDRAM_DQ_OE(dq_oe),
        .SDRAM_A(sdram_a),
        .SDRAM_DQML(dqml),
        .SDRAM_DQMH(dqmh),
        .SDRAM_BA(sdram_ba),
        .SDRAM_nCS(ncs),
        .SDRAM_nWE(nwe),
        .SDRAM_nRAS(nras),
        .SDRAM_nCAS(ncas),
        .SDRAM_CKE(cke),
        .SDRAM_CLK(sdram_clk),
        .addr,
        .dout,
        .din,
        .we,
        .rd,
        .refresh(1'b0),
        .word,
        .ready
    );

    task automatic wait_controller_cycles(input integer count);
        repeat (count) @(posedge clk);
    endtask

    task automatic pulse_write(input [24:0] write_addr,
                               input [15:0] write_data);
        begin
            addr = write_addr;
            din = write_data;
            we = 1'b1;
            @(posedge clk);
            #1 we = 1'b0;
        end
    endtask

    task automatic pulse_read(input [24:0] read_addr);
        begin
            addr = read_addr;
            rd = 1'b1;
            @(posedge clk);
            #1 rd = 1'b0;
        end
    endtask

    integer cycles;
    integer refresh_cycles;
    logic saw_write;
    logic saw_read;

    initial begin
        wait_controller_cycles(4);
        if (cke !== 1'b0)
            $fatal(1, "GUS SDRAM CKE asserted while the PLL was inactive");
        if (sdram_clk !== clk_physical)
            $fatal(1, "GUS SDRAM did not forward the phase-shifted IOPLL clock");

        active = 1'b1;
        init = 1'b0;
        cycles = 0;
        while (!ready && cycles < 12_150) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (!ready)
            $fatal(1, "GUS SDRAM initialization did not complete");
        if (cycles < 12_090)
            $fatal(1, "GUS SDRAM violated its power-up delay");

        // At 30 MHz the refresh budget is 210 controller cycles. Allow the
        // two-state scheduler latency, but reject the old 780-cycle behavior.
        refresh_cycles = 0;
        while ({nras, ncas, nwe} != 3'b001 && refresh_cycles < 225) begin
            @(posedge clk);
            refresh_cycles = refresh_cycles + 1;
        end
        if (refresh_cycles < 205 || refresh_cycles >= 225)
            $fatal(1, "30 MHz refresh deadline was %0d cycles", refresh_cycles);

        wait_controller_cycles(10);
        pulse_write(25'h001234, 16'hc35a);
        saw_write = 1'b0;
        repeat (12) begin
            @(posedge clk);
            #1;
            if ({nras, ncas, nwe} == 3'b100) begin
                saw_write = 1'b1;
                if (!dq_oe || dq_out != 16'hc35a)
                    $fatal(1, "GUS SDRAM write data or OE was incorrect");
            end
        end
        if (!saw_write)
            $fatal(1, "GUS SDRAM write command was not issued");

        pulse_read(25'h001238);
        saw_read = 1'b0;
        repeat (14) begin
            @(posedge clk);
            #1;
            if ({nras, ncas, nwe} == 3'b101)
                saw_read = 1'b1;
        end
        if (!saw_read)
            $fatal(1, "GUS SDRAM read command was not issued");
        if (dout != 16'h5aa5)
            $fatal(1, "GUS SDRAM read capture returned %h", dout);

        active = 1'b0;
        init = 1'b1;
        #1;
        if (cke !== 1'b0)
            $fatal(1, "GUS SDRAM did not quiesce before PLL reconfiguration");
        @(posedge clk);
        #1;
        if (dq_oe !== 1'b0)
            $fatal(1, "GUS SDRAM DQ remained driven while inactive");

        $display("PASS: ao486 GUS SDRAM clock, refresh, read, write, and quiesce");
        $finish;
    end
endmodule
