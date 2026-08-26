// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire outclk_2,
    output wire outclk_3,
    output wire outclk_4,
    output wire locked
);
    atari7800_core_pll impl (
        .refclk_clk(refclk),
        .reset_reset(rst),
        .locked_export(locked),
        .outclk0_clk(outclk_0),
        .outclk1_clk(outclk_1),
        .outclk2_clk(outclk_2),
        .outclk3_clk(outclk_3),
        .outclk4_clk(outclk_4)
    );
endmodule
