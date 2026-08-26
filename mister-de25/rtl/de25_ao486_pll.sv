// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Agilex 5 replacement for ao486's Cyclone V PLL and legacy reconfiguration
// controller. CPU clock profiles use the IOSSM Calibration IP path. The
// platform PLL supplies video; deterministic fabric dividers supply the slow
// legacy baud clocks without consuming another Agilex 5 IOPLL.
module de25_ao486_pll (
    input  logic       refclk,
    input  logic       clk_audio,
    input  logic       clk_vga_platform,
    input  logic       reset,
    input  logic [2:0] speed,
    input  logic       uart_slow,
    output logic       clk_sys,
    output logic       clk_sdram_physical,
    output logic       clk_uart1,
    output logic       clk_uart2,
    output logic       clk_mpu,
    output logic       clk_vga,
    output logic       locked,
    output logic       busy,
    output logic       error
);
    // Keep the CPU IOPLL independent from Main's persona RESET handshake.
    logic [7:0] pll_por = 8'hff;
    always_ff @(posedge refclk)
        pll_por <= {pll_por[6:0], 1'b0};

    // RESET belongs to a generated clock domain. Synchronize release before
    // using it in the fixed 50 MHz AXI-Lite control domain.
    (* ASYNC_REG = "TRUE" *) logic [2:0] control_reset_pipe = 3'b111;
    always_ff @(posedge refclk or posedge reset) begin
        if (reset)
            control_reset_pipe <= 3'b111;
        else
            control_reset_pipe <= {control_reset_pipe[1:0], 1'b0};
    end
    wire control_reset = control_reset_pipe[2];

    logic [2:0] applied_speed = 3'd0;
    logic profile_start;
    wire [2:0] bounded_speed = speed > 3'd4 ? 3'd4 : speed;

    always_ff @(posedge refclk) begin
        profile_start <= 1'b0;
        if (!control_reset && !busy && bounded_speed != applied_speed) begin
            applied_speed <= bounded_speed;
            profile_start <= 1'b1;
        end
    end

    logic [31:0] m_settings;
    logic [31:0] c0_settings;
    logic [31:0] c1_settings;
    logic [14:0] charge_pump_settings;
    de25_ao486_pll_profiles profiles (
        .speed(bounded_speed),
        .m_settings,
        .c0_settings,
        .c1_settings,
        .charge_pump_settings
    );

    logic cpu_locked;
    logic reconfig_done;
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

    de25_iopll_reconfig_axil #(.C_COUNTERS(2)) reconfigure (
        .clk(refclk),
        .reset(control_reset),
        .start(profile_start),
        .m_settings,
        .c0_settings,
        .c1_settings,
        .c2_settings(32'd0),
        .c3_settings(32'd0),
        .c4_settings(32'd0),
        .charge_pump_settings,
        .locked(cpu_locked),
        .busy,
        .done(reconfig_done),
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

    ao486_core_pll_cal pll (
        .refclk_clk(refclk),
        .cpu_reset_reset(pll_por[7]),
        .cpu_locked_export(cpu_locked),
        .cpu_outclk_clk(clk_sys),
        .cpu_sdram_outclk_clk(clk_sdram_physical),
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

    // 24.576 MHz * 3 / 40 = 1.8432 MHz. Alternating half-periods of
    // 7, 7, and 6 source clocks gives the exact long-term UART frequency and
    // keeps both halves within one audio-clock period of 50 percent duty.
    logic [2:0] uart_half_count = 3'd0;
    logic [1:0] uart_half_phase = 2'd0;
    (* altera_attribute = "-name GLOBAL_SIGNAL GLOBAL_CLOCK" *)
    logic clk_uart_slow = 1'b0;
    always_ff @(posedge clk_audio or posedge pll_por[7]) begin
        if (pll_por[7]) begin
            uart_half_count <= 3'd0;
            uart_half_phase <= 2'd0;
            clk_uart_slow <= 1'b0;
        end else if (uart_half_count ==
                     (uart_half_phase == 2'd2 ? 3'd5 : 3'd6)) begin
            uart_half_count <= 3'd0;
            uart_half_phase <= uart_half_phase == 2'd2
                ? 2'd0 : uart_half_phase + 1'b1;
            clk_uart_slow <= ~clk_uart_slow;
        end else begin
            uart_half_count <= uart_half_count + 1'b1;
        end
    end

    // 24.576 MHz * 125 / 1024 = exactly 3 MHz. The accumulator MSB is a
    // bounded-jitter baud clock suitable for the asynchronous MPU UART.
    logic [9:0] mpu_phase = 10'd0;
    always_ff @(posedge clk_audio or posedge pll_por[7]) begin
        if (pll_por[7]) begin
            mpu_phase <= 10'd0;
        end else begin
            mpu_phase <= mpu_phase + 10'd125;
        end
    end

    (* altera_attribute = "-name GLOBAL_SIGNAL GLOBAL_CLOCK" *)
    wire clk_mpu_nco = mpu_phase[9];
    assign clk_uart1 = uart_slow ? clk_uart_slow : refclk;
    assign clk_uart2 = clk_uart_slow;
    assign clk_mpu = clk_mpu_nco;
    assign clk_vga = clk_vga_platform;
    assign locked = cpu_locked && !busy && !error;

    wire unused_reconfig_done = reconfig_done;
endmodule
