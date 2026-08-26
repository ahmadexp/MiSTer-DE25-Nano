// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

// Shared clock service compiled into each complete MiSTer core image.
//
// One four-output bank provides stable semantic clock lanes, while its
// AXI-Lite calibration port allows core logic to apply exact, characterized
// profiles at runtime. Keeping this service in the common source shell lets
// Quartus place the IOPLL legally for each complete image.
module de25_mister_clock_service (
    input  wire        refclk,
    input  wire        reset,
    output wire [3:0]  bank0_clocks,
    output wire        bank0_locked,

    input  wire [26:0] bank0_awaddr,
    input  wire        bank0_awvalid,
    output wire        bank0_awready,
    input  wire [31:0] bank0_wdata,
    input  wire  [3:0] bank0_wstrb,
    input  wire        bank0_wvalid,
    output wire        bank0_wready,
    output wire  [1:0] bank0_bresp,
    output wire        bank0_bvalid,
    input  wire        bank0_bready,
    input  wire [26:0] bank0_araddr,
    input  wire        bank0_arvalid,
    output wire        bank0_arready,
    output wire [31:0] bank0_rdata,
    output wire  [1:0] bank0_rresp,
    output wire        bank0_rvalid,
    input  wire        bank0_rready
);

    // One physical four-output IOPLL supplies the complete core. Each core
    // gives these four lanes semantic names locally. A single calibration
    // channel avoids duplicate aliases and clock ports.

    de25_core_clock_banks clocks (
        .bank0_refclk_clk(refclk),
        .bank0_reset_reset(reset),
        .bank0_locked_export(bank0_locked),
        .bank0_outclk0_clk(bank0_clocks[0]),
        .bank0_outclk1_clk(bank0_clocks[1]),
        .bank0_outclk2_clk(bank0_clocks[2]),
        .bank0_outclk3_clk(bank0_clocks[3]),
        .cal_s0_axil_clk_clk(refclk),
        .cal_s0_axil_rst_n_reset_n(~reset),
        .cal_s0_axil_awaddr(bank0_awaddr),
        .cal_s0_axil_awvalid(bank0_awvalid),
        .cal_s0_axil_awready(bank0_awready),
        .cal_s0_axil_wdata(bank0_wdata),
        .cal_s0_axil_wstrb(bank0_wstrb),
        .cal_s0_axil_wvalid(bank0_wvalid),
        .cal_s0_axil_wready(bank0_wready),
        .cal_s0_axil_bresp(bank0_bresp),
        .cal_s0_axil_bvalid(bank0_bvalid),
        .cal_s0_axil_bready(bank0_bready),
        .cal_s0_axil_araddr(bank0_araddr),
        .cal_s0_axil_arvalid(bank0_arvalid),
        .cal_s0_axil_arready(bank0_arready),
        .cal_s0_axil_rdata(bank0_rdata),
        .cal_s0_axil_rresp(bank0_rresp),
        .cal_s0_axil_rvalid(bank0_rvalid),
        .cal_s0_axil_rready(bank0_rready),
        .cal_s0_axil_awprot(3'b000),
        .cal_s0_axil_arprot(3'b000)
    );
endmodule

`default_nettype wire
