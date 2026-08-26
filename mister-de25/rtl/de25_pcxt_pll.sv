// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Agilex 5 replacement for PCXT's two Cyclone V PLLs. A single native
// IOPLL preserves the original six clock outputs and the 90-degree video
// retiming phase relationship.
module de25_pcxt_pll (
    input  logic refclk,
    input  logic reset,
    output logic clk_100,
    output logic clk_chipset,
    output logic clk_28_636,
    output logic clk_57_272,
    output logic clk_114_544,
    output logic clk_video_out_ps,
    output logic locked
);
    logic [7:0] pll_por = 8'hff;
    always_ff @(posedge refclk)
        pll_por <= {pll_por[6:0], 1'b0};

    pcxt_core_pll impl (
        .refclk_clk(refclk),
        // Main may hold the persona RESET input while probing hps_io. Keep
        // PLL startup independent so that handshake can complete.
        .reset_reset(pll_por[7]),
        .locked_export(locked),
        .outclk0_clk(clk_100),
        .outclk1_clk(clk_chipset),
        .outclk2_clk(clk_28_636),
        .outclk3_clk(clk_57_272),
        .outclk4_clk(clk_114_544),
        .outclk5_clk(clk_video_out_ps)
    );
endmodule
