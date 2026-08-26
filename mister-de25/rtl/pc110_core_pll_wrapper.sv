// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module de25_pc110_core_clocks (
    input  wire refclk,
    input  wire reset,
    output wire clk_sys,
    output wire clk_uart1,
    output wire clk_mpu,
    output wire clk_uart2,
    output wire clk_vga,
    output wire clk_scanout,
    output wire locked
);
    wire core_locked;
    wire vga_locked;

    pc110_core_pll impl (
        .refclk_clk(refclk),
        .reset_reset(reset),
        .vga_refclk_clk(refclk),
        .vga_reset_reset(reset),
        .locked_export(core_locked),
        .vga_locked_export(vga_locked),
        .outclk0_clk(clk_sys),
        .outclk1_clk(clk_uart1),
        .outclk2_clk(clk_mpu),
        .outclk3_clk(clk_uart2),
        .outclk4_clk(clk_vga),
        .outclk5_clk(clk_scanout)
    );

    assign locked = core_locked & vga_locked;
endmodule
