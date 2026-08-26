`timescale 1ns/1ps
`default_nettype none

module de25_sdram_quiesce_tb;
    logic clk_control = 1'b0;
    logic clk_sdram = 1'b0;
    logic clk_sdram_device = 1'b0;
    logic reset_control = 1'b1;
    logic pll_locked = 1'b0;
    logic request_control = 1'b0;
    logic hold_sdram = 1'b0;
    logic ready_sdram = 1'b1;
    wire quiesced_control;
    wire sdram_active;

    logic saw_sdram_quiesce_edge = 1'b0;
    logic monitor_request = 1'b0;

    always #10 clk_control = ~clk_control;
    always #3 clk_sdram = ~clk_sdram;
    // C1 has the same period as C0 and a positive phase shift.
    initial begin
        #1.5;
        forever #3 clk_sdram_device = ~clk_sdram_device;
    end

    de25_sdram_quiesce dut (
        .clk_control(clk_control),
        .reset_control(reset_control),
        .clk_sdram(clk_sdram),
        .pll_locked(pll_locked),
        .request_control(request_control),
        .hold_sdram(hold_sdram),
        .ready_sdram(ready_sdram),
        .quiesced_control(quiesced_control),
        .sdram_active(sdram_active)
    );

    always @(posedge clk_sdram_device) begin
        if (monitor_request && !sdram_active) begin
            saw_sdram_quiesce_edge <= 1'b1;
        end
    end

    always @(posedge quiesced_control) begin
        if (monitor_request && !saw_sdram_quiesce_edge) begin
            $fatal(1, "acknowledgement preceded the SDRAM quiesce edge");
        end
    end

    task automatic wait_active(input logic expected);
        integer cycles;
        begin
            cycles = 0;
            while ((sdram_active !== expected) && (cycles < 100)) begin
                @(posedge clk_control);
                cycles = cycles + 1;
            end
            if (sdram_active !== expected) begin
                $fatal(1, "timeout waiting for sdram_active=%0d", expected);
            end
        end
    endtask

    task automatic wait_quiesced(input logic expected);
        integer cycles;
        begin
            cycles = 0;
            while ((quiesced_control !== expected) && (cycles < 100)) begin
                @(posedge clk_control);
                cycles = cycles + 1;
            end
            if (quiesced_control !== expected) begin
                $fatal(1, "timeout waiting for quiesced_control=%0d", expected);
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk_control);
        pll_locked = 1'b1;
        reset_control = 1'b0;
        wait_active(1'b1);
        wait_quiesced(1'b0);

        // A normal request must quiesce the memory before acknowledgement.
        @(negedge clk_control);
        saw_sdram_quiesce_edge = 1'b0;
        monitor_request = 1'b1;
        request_control = 1'b1;
        ready_sdram = 1'b0;
        repeat (8) @(posedge clk_control);
        if (quiesced_control || !sdram_active) begin
            $fatal(1, "SDRAM stopped before the controller became idle");
        end
        ready_sdram = 1'b1;
        wait_quiesced(1'b1);
        if (!saw_sdram_quiesce_edge || sdram_active) begin
            $fatal(1, "normal request did not safely quiesce SDRAM");
        end

        // Releasing the request cannot restart while the SDRAM-domain hold is
        // active. MemTest uses this hold for its post-reconfiguration reset.
        hold_sdram = 1'b1;
        request_control = 1'b0;
        repeat (8) @(posedge clk_control);
        if (sdram_active || !quiesced_control) begin
            $fatal(1, "hold_sdram did not preserve the idle state");
        end
        hold_sdram = 1'b0;
        monitor_request = 1'b0;
        wait_active(1'b1);
        wait_quiesced(1'b0);

        // Lock loss must deactivate the interface without waiting for either
        // clock-domain synchronizer.
        #1 pll_locked = 1'b0;
        #1;
        if (sdram_active) begin
            $fatal(1, "PLL lock loss did not immediately disable SDRAM");
        end

        $display("PASS: SDRAM quiesce handshake and lock-loss protection");
        $finish;
    end
endmodule

`default_nettype wire
