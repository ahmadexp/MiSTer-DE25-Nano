// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Preserve InputTest's upstream PLL interface while using Agilex 5 IOPLL IP.
module pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire locked
);
    inputtest_core_pll impl (
        .refclk_clk(refclk),
        .reset_reset(rst),
        .locked_export(locked),
        .outclk0_clk(outclk_0)
    );
endmodule
