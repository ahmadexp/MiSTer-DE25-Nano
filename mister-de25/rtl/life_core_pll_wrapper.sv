// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module pll (
    input  wire        refclk,
    input  wire        rst,
    output wire        outclk_0,
    input  wire [63:0] reconfig_to_pll,
    output wire [63:0] reconfig_from_pll
);
    wire locked_unused;

    life_core_pll impl (
        .refclk_clk(refclk),
        .reset_reset(rst),
        .locked_export(locked_unused),
        .outclk0_clk(outclk_0)
    );

    assign reconfig_from_pll = 64'd0;
endmodule
