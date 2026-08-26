// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module pll (
    input  wire        refclk,
    input  wire        rst,
    output wire        outclk_0,
    output wire        outclk_1,
    output wire        outclk_sdram,
    output wire        locked,
    input  wire [63:0] reconfig_to_pll,
    output wire [63:0] reconfig_from_pll
);
    saturn_core_pll impl (
        .refclk_clk(refclk),
        .reset_reset(rst),
        .locked_export(locked),
        .outclk0_clk(outclk_0),
        .outclk1_clk(outclk_1),
        .outclk2_clk(outclk_sdram)
    );

    assign reconfig_from_pll = 64'd0;
endmodule

// Keep the first synthesis on the fixed NTSC clock pair. The platform clock
// service will supply PAL and dot-clock switching after the core compiles.
module pll_cfg (
    input  wire        mgmt_clk,
    input  wire        mgmt_reset,
    output wire        mgmt_waitrequest,
    input  wire        mgmt_read,
    output wire [31:0] mgmt_readdata,
    input  wire        mgmt_write,
    input  wire  [5:0] mgmt_address,
    input  wire [31:0] mgmt_writedata,
    output wire [63:0] reconfig_to_pll,
    input  wire [63:0] reconfig_from_pll
);
    assign mgmt_waitrequest = 1'b0;
    assign mgmt_readdata = 32'd0;
    assign reconfig_to_pll = 64'd0;
endmodule
