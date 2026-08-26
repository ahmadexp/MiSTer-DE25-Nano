// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

module de25_mister_audio_v2_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [15:0] core_left = 16'ha55a;
    logic [15:0] core_right = 16'h3cc3;
    logic core_signed = 1'b1;
    wire bit_clock;
    wire word_clock;
    wire serial_data;

    integer audio_cycles = 0;
    integer last_bclk_rise = -1;
    integer bclk_rises = 0;
    integer lr_edges = 0;
    integer bclk_at_last_lr_edge = 0;

    de25_mister_audio_v2 dut (
        .clk_audio(clk),
        .reset(reset),
        .core_left(core_left),
        .core_right(core_right),
        .core_signed(core_signed),
        .bit_clock(bit_clock),
        .word_clock(word_clock),
        .serial_data(serial_data)
    );

    always #5 clk = ~clk;
    always @(posedge clk)
        if (!reset)
            audio_cycles = audio_cycles + 1;

    always @(posedge bit_clock) begin
        if (!reset) begin
            if (last_bclk_rise >= 0 &&
                (audio_cycles - last_bclk_rise) != 16)
                $fatal(1, "BCLK period is %0d audio clocks, expected 16",
                       audio_cycles - last_bclk_rise);
            last_bclk_rise = audio_cycles;
            bclk_rises = bclk_rises + 1;
        end
    end

    always @(word_clock) begin
        if (!reset && bclk_rises > 2) begin
            if (lr_edges > 0 &&
                (bclk_rises - bclk_at_last_lr_edge) != 16)
                $fatal(1, "LRCLK half-period is %0d BCLKs, expected 16",
                       bclk_rises - bclk_at_last_lr_edge);
            bclk_at_last_lr_edge = bclk_rises;
            lr_edges = lr_edges + 1;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        reset <= 1'b0;
        wait (lr_edges >= 6);
        if (bclk_rises < 90)
            $fatal(1, "too few BCLK edges observed");
        $display("PASS: audio BCLK=clk/16, LRCLK=BCLK/32, balanced channels");
        $finish;
    end

    wire unused = serial_data;
endmodule

`default_nettype wire
