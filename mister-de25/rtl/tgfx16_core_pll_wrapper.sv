// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Preserve TurboGrafx16's upstream PLL interface with an Agilex 5 IOPLL.
module pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire locked
);
    tgfx16_core_pll impl (
        .refclk_clk(refclk),
        .reset_reset(rst),
        .locked_export(locked),
        .outclk0_clk(outclk_0),
        .outclk1_clk(outclk_1)
    );
endmodule
