// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Converts one IOPLL register request into an AXI-Lite transaction for the
// Agilex 5 EMIF Calibration IP. Standalone PLL zero is selected by the base
// address field, and bits 23:21 select the IOPLL reconfiguration aperture.
module de25_iopll_axil #(
    parameter integer TRANSACTION_TIMEOUT_CYCLES = 500_000
) (
    input  logic        clk,
    input  logic        reset,

    input  logic        start,
    input  logic        write_request,
    input  logic  [8:0] address,
    input  logic [31:0] writedata,
    output logic [31:0] readdata,
    output logic        busy,
    output logic        done,
    output logic        response_error,
    output logic        timeout_error,

    output logic [26:0] axil_awaddr,
    output logic        axil_awvalid,
    input  logic        axil_awready,
    output logic [31:0] axil_wdata,
    output logic  [3:0] axil_wstrb,
    output logic        axil_wvalid,
    input  logic        axil_wready,
    input  logic  [1:0] axil_bresp,
    input  logic        axil_bvalid,
    output logic        axil_bready,
    output logic [26:0] axil_araddr,
    output logic        axil_arvalid,
    input  logic        axil_arready,
    input  logic [31:0] axil_rdata,
    input  logic  [1:0] axil_rresp,
    input  logic        axil_rvalid,
    output logic        axil_rready
);

    localparam logic [26:0] IOPLL_APERTURE = 27'h0A0_0000;

    typedef enum logic [2:0] {
        IDLE,
        WRITE_REQUEST,
        WRITE_RESPONSE,
        READ_REQUEST,
        READ_RESPONSE
    } state_t;

    state_t state;
    logic [31:0] timeout_count;

    assign busy         = state != IDLE;
    assign axil_awaddr  = IOPLL_APERTURE | {18'd0, address};
    assign axil_araddr  = IOPLL_APERTURE | {18'd0, address};
    assign axil_wstrb   = 4'hF;
    assign axil_bready  = state == WRITE_RESPONSE;
    assign axil_rready  = state == READ_RESPONSE;

    always_ff @(posedge clk) begin
        done <= 1'b0;

        if (reset) begin
            state          <= IDLE;
            axil_awvalid   <= 1'b0;
            axil_wvalid    <= 1'b0;
            axil_arvalid   <= 1'b0;
            axil_wdata     <= 32'd0;
            readdata       <= 32'd0;
            response_error <= 1'b0;
            timeout_error  <= 1'b0;
            timeout_count  <= 32'd0;
        end else begin
            if (state != IDLE) begin
                if (timeout_count == TRANSACTION_TIMEOUT_CYCLES - 1) begin
                    state          <= IDLE;
                    axil_awvalid   <= 1'b0;
                    axil_wvalid    <= 1'b0;
                    axil_arvalid   <= 1'b0;
                    response_error <= 1'b1;
                    timeout_error  <= 1'b1;
                    done           <= 1'b1;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end

            case (state)
                IDLE: begin
                    if (start) begin
                        axil_wdata     <= writedata;
                        readdata       <= 32'd0;
                        response_error <= 1'b0;
                        timeout_error  <= 1'b0;
                        timeout_count  <= 32'd0;
                        if (write_request) begin
                            axil_awvalid <= 1'b1;
                            axil_wvalid  <= 1'b1;
                            state        <= WRITE_REQUEST;
                        end else begin
                            axil_arvalid <= 1'b1;
                            state        <= READ_REQUEST;
                        end
                    end
                end

                WRITE_REQUEST: begin
                    if (axil_awvalid && axil_awready)
                        axil_awvalid <= 1'b0;
                    if (axil_wvalid && axil_wready)
                        axil_wvalid <= 1'b0;
                    if ((!axil_awvalid || axil_awready) &&
                        (!axil_wvalid || axil_wready))
                        state <= WRITE_RESPONSE;
                end

                WRITE_RESPONSE: begin
                    if (axil_bvalid) begin
                        response_error <= axil_bresp != 2'b00;
                        done           <= 1'b1;
                        timeout_error  <= 1'b0;
                        state          <= IDLE;
                    end
                end

                READ_REQUEST: begin
                    if (axil_arready) begin
                        axil_arvalid <= 1'b0;
                        state        <= READ_RESPONSE;
                    end
                end

                READ_RESPONSE: begin
                    if (axil_rvalid) begin
                        readdata       <= axil_rdata;
                        response_error <= axil_rresp != 2'b00;
                        done           <= 1'b1;
                        timeout_error  <= 1'b0;
                        state          <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
