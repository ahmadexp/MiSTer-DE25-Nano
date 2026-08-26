// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Agilex 5 replacement for MemTest's Cyclone V PLL and pll_cfg pair.
module de25_memtest_pll (
    input  logic        refclk,
    input  logic        reset,
    input  logic  [5:0] profile_index,
    input  logic        start,
    output logic        outclk,
    output logic        sdram_clk,
    output logic        locked,
    output logic [11:0] frequency_bcd,
    output logic        busy,
    output logic        done,
    output logic        error,
    output logic        control_reset,
    output logic  [5:0] diagnostic_code
);
    (* ASYNC_REG = "TRUE" *) logic [2:0] control_reset_pipe = 3'b111;
    always_ff @(posedge refclk or posedge reset) begin
        if (reset)
            control_reset_pipe <= 3'b111;
        else
            control_reset_pipe <= {control_reset_pipe[1:0], 1'b0};
    end
    assign control_reset = control_reset_pipe[2];

    logic [31:0] m_settings;
    logic [31:0] c0_settings;
    logic [31:0] c1_settings;
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
    logic [4:0] diagnostic_step;
    logic [2:0] error_code;

    // Independently verify the resulting clock. A Gray counter crosses the
    // variable PLL domain safely into the fixed 50 MHz control domain. The
    // automatic hardware diagnostic expects 52 MHz after reconfiguration.
    logic [23:0] outclk_counter = 24'd0;
    logic [23:0] outclk_gray = 24'd0;
    (* ASYNC_REG = "TRUE" *) logic [23:0] outclk_gray_meta = 24'd0;
    (* ASYNC_REG = "TRUE" *) logic [23:0] outclk_gray_sync = 24'd0;
    logic [23:0] measure_start = 24'd0;
    logic [22:0] measure_window = 23'd0;
    logic measuring = 1'b0;

    function automatic logic [23:0] gray_to_binary(input logic [23:0] gray);
        integer bit_index;
        begin
            gray_to_binary[23] = gray[23];
            for (bit_index = 22; bit_index >= 0; bit_index = bit_index - 1)
                gray_to_binary[bit_index] = gray_to_binary[bit_index + 1] ^
                                            gray[bit_index];
        end
    endfunction

    wire [23:0] measured_counter = gray_to_binary(outclk_gray_sync);

    always_ff @(posedge outclk or posedge reset) begin
        if (reset) begin
            outclk_counter <= 24'd0;
            outclk_gray    <= 24'd0;
        end else begin
            outclk_counter <= outclk_counter + 1'b1;
            outclk_gray    <= ((outclk_counter + 1'b1) >> 1) ^
                              (outclk_counter + 1'b1);
        end
    end

    always_ff @(posedge refclk or posedge reset) begin
        if (reset) begin
            outclk_gray_meta <= 24'd0;
            outclk_gray_sync <= 24'd0;
            measure_start    <= 24'd0;
            measure_window   <= 23'd0;
            measuring        <= 1'b0;
            diagnostic_code  <= 6'd63;
        end else begin
            outclk_gray_meta <= outclk_gray;
            outclk_gray_sync <= outclk_gray_meta;

            if (busy) begin
                diagnostic_code <= 6'd62;
            end else if (error) begin
                // Codes 57 through 61 distinguish AXI response failures,
                // lock timeout, and AXI read/write transaction timeout.
                diagnostic_code <= 6'd56 + error_code;
                measuring       <= 1'b0;
            end else if (done) begin
                measure_start   <= measured_counter;
                measure_window  <= 23'd0;
                measuring       <= 1'b1;
                diagnostic_code <= 6'd62;
            end else if (measuring) begin
                if (measure_window == 23'd4_999_999) begin
                    measuring <= 1'b0;
                    // A 0.1 second window must contain about 5.2 million
                    // output edges. Code 52 is pass; 55 is wrong frequency.
                    if (locked &&
                        ((measured_counter - measure_start) >= 24'd5_100_000) &&
                        ((measured_counter - measure_start) <= 24'd5_300_000))
                        diagnostic_code <= 6'd52;
                    else
                        diagnostic_code <= 6'd55;
                end else begin
                    measure_window <= measure_window + 1'b1;
                end
            end
        end
    end

    de25_memtest_pll_profiles profiles (
        .index(profile_index),
        .frequency_bcd,
        .m_settings,
        .c0_settings,
        .c1_settings,
        .charge_pump_settings
    );

    de25_iopll_reconfig_axil reconfigure (
        .clk(refclk),
        .reset(control_reset),
        .start,
        .m_settings,
        .c0_settings,
        .c1_settings,
        .c2_settings(32'd0),
        .c3_settings(32'd0),
        .c4_settings(32'd0),
        .charge_pump_settings,
        .locked,
        .busy,
        .done,
        .error,
        .diagnostic_step,
        .error_code,
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

    memtest_core_pll_cal pll (
        .refclk_clk(refclk),
        // Give the Agilex IOPLL a real reset after each FPGA load. Leaving
        // this permanently deasserted can preserve an unlocked calibration
        // state across the HPS-first configuration handoff.
        .reset_reset(reset),
        .locked_export(locked),
        .outclk0_clk(outclk),
        .outclk1_clk(sdram_clk),
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

module de25_memtest_video_pll (
    input  logic refclk,
    input  logic reset,
    output logic outclk
);
    logic locked_unused;

    memtest_video_pll pll (
        .refclk_clk(refclk),
        .reset_reset(reset),
        .locked_export(locked_unused),
        .outclk0_clk(outclk)
    );
endmodule
