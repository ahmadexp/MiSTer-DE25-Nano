`timescale 1ns/1ps

module snes_sdram_tb;
    logic clk = 1'b0;
    logic clk_capture = 1'b0;
    logic clk_physical = 1'b0;
    logic init = 1'b1;
    logic active = 1'b1;
    logic quiesce = 1'b0;
    wire quiesced;
    logic [15:0] dq_in = 16'hdead;
    wire [15:0] dq_out;
    wire dq_oe;
    wire [12:0] sdram_a;
    wire sdram_dqml;
    wire sdram_dqmh;
    wire [1:0] sdram_ba;
    wire sdram_ncs;
    wire sdram_nwe;
    wire sdram_nras;
    wire sdram_ncas;
    wire sdram_clk;
    wire sdram_cke;
    logic [23:0] addr0 = 24'h123456;
    logic [15:0] din0 = 16'ha55a;
    wire [15:0] dout0;
    logic wr0 = 1'b0;
    logic rd0 = 1'b0;
    logic word0 = 1'b1;
    integer read_latency = -1;
    logic saw_read_command = 1'b0;
    logic saw_write_command = 1'b0;

    // NTSC profile: 85.909091 MHz controller, with board clock and capture
    // edges shifted by the Quartus-derived 5.291 ns and 6.349 ns phases.
    always #5.82 clk = ~clk;
    initial begin
        #5.291;
        forever #5.82 clk_physical = ~clk_physical;
    end
    initial begin
        #6.349;
        forever #5.82 clk_capture = ~clk_capture;
    end

    // Minimal CAS-latency-2 model. The controller command pins are stable at
    // the forwarded SDRAM clock edge and the read word appears two edges later.
    always @(posedge clk_physical) begin
        if (!sdram_nras && sdram_ncas && !sdram_nwe)
            saw_write_command <= 1'b1;
        if (sdram_nras && !sdram_ncas && sdram_nwe) begin
            saw_read_command <= 1'b1;
            read_latency <= 2;
        end else if (read_latency > 0)
            read_latency <= read_latency - 1;

        if (read_latency == 1)
            dq_in <= 16'h3cc3;
    end

    sdram dut (
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
        .init(init),
        .clk(clk),
        .clk_capture(clk_capture),
        .clk_physical(clk_physical),
        .active(active),
        .quiesce(quiesce),
        .quiesced(quiesced),
        .addr0(addr0),
        .din0(din0),
        .dout0(dout0),
        .wr0(wr0),
        .rd0(rd0),
        .word0(word0),
        .addr1(24'd0),
        .din1(16'd0),
        .dout1(),
        .wr1(1'b0),
        .rd1(1'b0),
        .rfs1(1'b0),
        .word1(1'b1),
        .sni_addr(25'd0),
        .sni_din(16'd0),
        .sni_dout(),
        .sni_wr_req(1'b0),
        .sni_rd_req(1'b0),
        .sni_word(1'b1),
        .sni_ready()
    );

    task automatic wait_initialized;
        integer timeout;
        begin
            timeout = 0;
            while ((!dut.init_done || dut.st_num < 8) && timeout < 1000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 1000)
                $fatal(1, "SNES SDRAM controller did not initialize");
        end
    endtask

    initial begin
        integer timeout;
        repeat (4) @(posedge clk);
        init <= 1'b0;
        wait_initialized();
        repeat (4) @(posedge clk);

        @(negedge clk);
        wr0 <= 1'b1;
        @(negedge clk);
        wr0 <= 1'b0;

        timeout = 0;
        while (!dq_oe && timeout < 30) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!dq_oe || dq_out != 16'ha55a)
            $fatal(1, "SNES SDRAM write mismatch: oe=%b out=%h", dq_oe, dq_out);
        repeat (12) @(posedge clk);
        if (!saw_write_command)
            $fatal(1, "SNES SDRAM WRITE command was not issued");

        @(negedge clk);
		addr0 <= 24'h123458;
        rd0 <= 1'b1;
        @(negedge clk);
        rd0 <= 1'b0;

        timeout = 0;
        while (!saw_read_command && timeout < 40) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!saw_read_command)
            $fatal(1, "SNES SDRAM READ command was not issued");
        repeat (10) @(posedge clk);
        #1;
        if (dout0 != 16'h3cc3)
            $fatal(1, "SNES SDRAM captured %h instead of 3cc3", dout0);
        if (dut.data_capture != 16'h3cc3)
            $fatal(1, "SNES capture register missed CAS-latency data");

        quiesce <= 1'b1;
        timeout = 0;
        while (!quiesced && timeout < 30) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!quiesced)
            $fatal(1, "SNES controller did not acknowledge idle state");

        active <= 1'b0;
        #1;
        if (sdram_cke || dq_oe)
            $fatal(1, "SNES quiesce did not disable SDRAM pins");

        $display("PASS: SNES SDRAM write, CAS-2 read capture, and quiesce");
        $finish;
    end
endmodule
