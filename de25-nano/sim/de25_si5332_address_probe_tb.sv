// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

module de25_si5332_address_probe_tb;
    logic clk = 1'b0;
    logic reset_n = 1'b0;
    tri1 scl;
    tri1 sda;
    wire [31:0] status;
    logic stretch_started = 1'b0;
    logic [4:0] stretch_cycles = '0;

    // Model an Si5332B at 0x6A and hold SCL low briefly during the first data
    // bit. This covers ACK sampling and the controller's clock-stretch wait.
    assign sda = (!dut.probe_index && dut.state >= 9 && dut.state <= 12) ?
        1'b0 : 1'bz;
    assign scl = (stretch_cycles != 0) ? 1'b0 : 1'bz;

    de25_si5332_address_probe #(
        .TICK_DIV(4)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .scl(scl),
        .sda(sda),
        .status(status)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            stretch_started <= 1'b0;
            stretch_cycles <= '0;
        end else if (!stretch_started && dut.state == 6) begin
            stretch_started <= 1'b1;
            stretch_cycles <= 5'd12;
        end else if (stretch_cycles != 0) begin
            stretch_cycles <= stretch_cycles - 1'b1;
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        reset_n = 1'b1;

        repeat (16384) begin
            @(posedge clk);
            if (status[7])
                $fatal(1,
                    "probe latched a bus fault: state=%0d scl=%b sda=%b scl_low=%b sda_low=%b status=%08x",
                    dut.state, dut.scl_sync, dut.sda_sync,
                    dut.scl_low, dut.sda_low, status);
            if (status[6]) begin
                repeat (8) @(posedge clk);
                if (status[7])
                    $fatal(1, "probe faulted after completing: status=%08x", status);
                if (status[5:4] != 2'b01)
                    $fatal(1, "expected only address 0x6A to ACK: status=%08x", status);
                if (status[3:2] != 2'b11)
                    $fatal(1, "probe did not release SDA/SCL: status=%08x", status);
                if (!stretch_started)
                    $fatal(1, "clock-stretch model did not run");
                $display("PASS: address probe tolerates clock stretching, detects 0x6A, and releases the bus");
                $finish;
            end
        end

        $fatal(1, "probe did not complete: status=%08x", status);
    end
endmodule

`default_nettype wire
