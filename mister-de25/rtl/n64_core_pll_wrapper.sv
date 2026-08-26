// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire outclk_2,
    output wire outclk_3,
    output wire locked
);
    n64_core_pll impl (
        .refclk_clk(refclk),
        .reset_reset(rst),
        .locked_export(locked),
        .outclk0_clk(outclk_0),
        .outclk1_clk(outclk_1),
        .outclk2_clk(outclk_2),
        .outclk3_clk(outclk_3)
    );
endmodule

module pll2 (
    input  wire        refclk,
    input  wire        rst,
    output wire        outclk_0,
    input  wire [63:0] reconfig_to_pll,
    output wire [63:0] reconfig_from_pll
);
    wire locked_unused;

    n64_video_pll impl (
        .refclk_clk(refclk),
        .reset_reset(rst),
        .locked_export(locked_unused),
        .outclk0_clk(outclk_0)
    );

    assign reconfig_from_pll = 64'd0;
endmodule

// First synthesis uses a fixed NTSC-compatible video clock. PAL runtime
// switching moves to the platform clock service after the memory and resource
// gates are understood.
module pll_cfg_small #(
    parameter reconf_width = 64,
    parameter device_family = "Agilex 5"
) (
    input  wire                    mgmt_clk,
    input  wire                    mgmt_reset,
    output wire [reconf_width-1:0] reconfig_to_pll,
    input  wire [reconf_width-1:0] reconfig_from_pll,
    output wire                    mgmt_waitrequest,
    input  wire [5:0]              mgmt_address,
    input  wire                    mgmt_write,
    input  wire [31:0]             mgmt_writedata
);
    assign mgmt_waitrequest = 1'b0;
    assign reconfig_to_pll = {reconf_width{1'b0}};
endmodule
