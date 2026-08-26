// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module pll (
    input  wire refclk,
    output wire outclk_0,
    output wire outclk_1,
    output wire locked
);
    chip8_core_pll impl (
        .refclk_clk(refclk),
        .reset_reset(1'b0),
        .locked_export(locked),
        .outclk0_clk(outclk_0),
        .outclk1_clk(outclk_1)
    );
endmodule

