// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module de25_sms_pll (
    input  logic refclk,
    input  logic reset,
    input  logic pal_profile,
    input  logic start,
    output logic clk_system,
    output logic clk_sdram_physical,
    output logic clk_sdram_capture,
    output logic locked,
    output logic busy,
    output logic done,
    output logic error,
    output logic control_reset
);
    // RESET is produced outside the fixed 50 MHz calibration domain. Retiming
    // its release prevents the AXI-Lite state machine from leaving reset on a
    // metastable edge.
    (* ASYNC_REG = "TRUE" *) logic [2:0] control_reset_pipe = 3'b111;
    always_ff @(posedge refclk or posedge reset) begin
        if (reset)
            control_reset_pipe <= 3'b111;
        else
            control_reset_pipe <= {control_reset_pipe[1:0], 1'b0};
    end
    assign control_reset = control_reset_pipe[2];

    // Main holds the core RESET input while probing a newly loaded persona.
    // The IOPLL must still start so hps_io can answer, so its power-on reset is
    // independent of that handshake.
    logic [7:0] pll_por = 8'hFF;
    always_ff @(posedge refclk)
        pll_por <= {pll_por[6:0], 1'b0};

    logic [31:0] m_settings;
    logic [31:0] c0_settings;
    logic [31:0] c1_settings;
    logic [31:0] c2_settings;
    logic [14:0] charge_pump_settings;
    logic [26:0] axil_awaddr;
    logic axil_awvalid;
    logic axil_awready;
    logic [31:0] axil_wdata;
    logic [3:0] axil_wstrb;
    logic axil_wvalid;
    logic axil_wready;
    logic [1:0] axil_bresp;
    logic axil_bvalid;
    logic axil_bready;
    logic [26:0] axil_araddr;
    logic axil_arvalid;
    logic axil_arready;
    logic [31:0] axil_rdata;
    logic [1:0] axil_rresp;
    logic axil_rvalid;
    logic axil_rready;

    de25_sms_pll_profiles profiles (
        .pal(pal_profile),
        .m_settings,
        .c0_settings,
        .c1_settings,
        .c2_settings,
        .charge_pump_settings
    );

    de25_iopll_reconfig_axil #(.C_COUNTERS(3)) reconfigure (
        .clk(refclk),
        .reset(control_reset),
        .start,
        .m_settings,
        .c0_settings,
        .c1_settings,
        .c2_settings,
        .c3_settings(32'd0),
        .c4_settings(32'd0),
        .charge_pump_settings,
        .locked,
        .busy,
        .done,
        .error,
        .diagnostic_step(),
        .error_code(),
        .last_address(),
        .last_read_data(),
        .last_write_data(),
        .axil_awaddr,
        .axil_awvalid,
        .axil_awready,
        .axil_wdata,
        .axil_wstrb,
        .axil_wvalid,
        .axil_wready,
        .axil_bresp,
        .axil_bvalid,
        .axil_bready,
        .axil_araddr,
        .axil_arvalid,
        .axil_arready,
        .axil_rdata,
        .axil_rresp,
        .axil_rvalid,
        .axil_rready
    );

    sms_core_pll_cal pll (
        .refclk_clk(refclk),
        .reset_reset(pll_por[7]),
        .locked_export(locked),
        .outclk0_clk(clk_system),
        .outclk1_clk(clk_sdram_physical),
        .outclk2_clk(clk_sdram_capture),
        .s0_axil_clk_clk(refclk),
        .s0_axil_rst_n_reset_n(~control_reset),
        .s0_axil_awaddr(axil_awaddr),
        .s0_axil_awvalid(axil_awvalid),
        .s0_axil_awready(axil_awready),
        .s0_axil_wdata(axil_wdata),
        .s0_axil_wstrb(axil_wstrb),
        .s0_axil_wvalid(axil_wvalid),
        .s0_axil_wready(axil_wready),
        .s0_axil_bresp(axil_bresp),
        .s0_axil_bvalid(axil_bvalid),
        .s0_axil_bready(axil_bready),
        .s0_axil_araddr(axil_araddr),
        .s0_axil_arvalid(axil_arvalid),
        .s0_axil_arready(axil_arready),
        .s0_axil_rdata(axil_rdata),
        .s0_axil_rresp(axil_rresp),
        .s0_axil_rvalid(axil_rvalid),
        .s0_axil_rready(axil_rready),
        .s0_axil_awprot(3'b000),
        .s0_axil_arprot(3'b000)
    );
endmodule
