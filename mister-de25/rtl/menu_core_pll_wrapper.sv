// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Preserve the upstream Menu PLL interface while using Agilex 5 IOPLL IP.
module pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire outclk_2,
    output wire outclk_3,
    output wire locked
);
    menu_core_pll impl (
        .refclk_clk(refclk),
        .reset_reset(rst),
        .locked_export(locked),
        .outclk0_clk(outclk_0),
        .outclk1_clk(outclk_1),
        .outclk2_clk(outclk_2),
        .outclk3_clk(outclk_3)
    );
endmodule
