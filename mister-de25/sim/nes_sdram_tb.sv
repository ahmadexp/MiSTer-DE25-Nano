`timescale 1ns/1ps

module nes_sdram_tb;
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
    logic [24:0] ch0_addr = 25'h0123456;
    logic ch0_rd = 1'b0;
    logic ch0_wr = 1'b0;
    logic [7:0] ch0_din = 8'ha5;
    wire [7:0] ch0_dout;
    wire ch0_busy;
    integer read_latency = -1;
    integer capture_edges_after_read = 0;
    logic saw_read_command = 1'b0;
    logic saw_write_command = 1'b0;

    always #6 clk = ~clk;
    initial begin
        #5.3;
        forever #6 clk_physical = ~clk_physical;
    end
    initial begin
        #11.1;
        forever #6 clk_capture = ~clk_capture;
    end

    // Minimal CAS-latency-2 SDRAM read model. A READ command is accepted on
    // the forwarded clock and data appears two device clocks later.
    always @(posedge clk_physical) begin
        if (!sdram_nras && sdram_ncas && !sdram_nwe)
            saw_write_command <= 1'b1;
        if (sdram_nras && !sdram_ncas && sdram_nwe) begin
            saw_read_command <= 1'b1;
            read_latency <= 2;
        end else if (read_latency > 0)
            read_latency <= read_latency - 1;

        // IS42/45VM16320G-6 specifies tAC(max)=5.5 ns. Model the worst-case
        // clock-to-data delay so an early capture edge cannot pass simulation.
        if (read_latency == 1)
            dq_in <= #5.5 16'h3cc3;
    end

    always @(posedge clk_capture) begin
        if (read_latency >= 0)
            capture_edges_after_read <= capture_edges_after_read + 1;
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
        .ch0_addr(ch0_addr),
        .ch0_rd(ch0_rd),
        .ch0_wr(ch0_wr),
        .ch0_din(ch0_din),
        .ch0_dout(ch0_dout),
        .ch0_busy(ch0_busy),
        .ch1_addr(25'd0),
        .ch1_rd(1'b0),
        .ch1_wr(1'b0),
        .ch1_din(8'd0),
        .ch1_dout(),
        .ch1_busy(),
        .ch2_addr(25'd0),
        .ch2_rd(1'b0),
        .ch2_wr(1'b0),
        .ch2_din(8'd0),
        .ch2_dout(),
        .ch2_busy(),
        .refresh(1'b0),
        .ss_in(16'd0),
        .ss_load(1'b0),
        .ss_out()
    );

    task automatic wait_idle;
        integer timeout;
        begin
            timeout = 0;
            while ((dut.mode != dut.MODE_NORMAL || dut.state != dut.STATE_IDLE) &&
                   timeout < 1000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 1000)
                $fatal(1, "SDRAM controller did not finish initialization");
        end
    endtask

    initial begin
        integer timeout;
        repeat (4) @(posedge clk);
        init <= 1'b0;
        wait_idle();
        repeat (10) @(posedge clk);

        @(negedge clk);
        ch0_wr <= 1'b1;

        timeout = 0;
        while (!dq_oe && timeout < 20) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        ch0_wr <= 1'b0;
        if (!dq_oe || dq_out != 16'ha5a5)
            $fatal(1, "SDRAM write mismatch: oe=%b out=%h",
                   dq_oe, dq_out);
        wait_idle();
        if (!saw_write_command)
            $fatal(1, "SDRAM WRITE command was not issued");

        @(negedge clk);
        ch0_rd <= 1'b1;

        timeout = 0;
        while (!ch0_busy && timeout < 20) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!ch0_busy)
            $fatal(1, "SDRAM controller did not accept read");
        ch0_rd <= 1'b0;
        while (ch0_busy)
            @(posedge clk);
        #1;
        if (ch0_dout != 8'hc3)
            $fatal(1, "SDRAM captured %h instead of c3", ch0_dout);
        if (dut.data_capture != 16'h3cc3)
            $fatal(1, "capture register missed CAS-latency data");
        if (!saw_read_command)
            $fatal(1, "SDRAM READ command was not issued");

        quiesce <= 1'b1;
        timeout = 0;
        while (!quiesced && timeout < 20) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!quiesced)
            $fatal(1, "controller did not acknowledge idle state");

        active <= 1'b0;
        #1;
        if (sdram_cke || dq_oe)
            $fatal(1, "quiesce did not disable SDRAM pins");

        $display("PASS: NES SDRAM write, CAS-2 read capture, and quiesce");
        $finish;
    end
endmodule
