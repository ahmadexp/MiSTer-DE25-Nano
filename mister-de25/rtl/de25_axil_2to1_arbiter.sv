// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

// Serializes two AXI-Lite masters onto one EMIF Calibration IP subordinate.
// A complete read or write transaction owns the subordinate until its response
// is accepted. This is deliberately small because PLL reconfiguration traffic
// is infrequent and throughput is irrelevant.
module de25_axil_2to1_arbiter #(
    parameter logic [26:0] M0_ADDRESS_OFFSET = 27'h0,
    parameter logic [26:0] M1_ADDRESS_OFFSET = 27'h000_2000
) (
    input  wire        clk,
    input  wire        reset,

    input  wire [26:0] m0_awaddr,
    input  wire        m0_awvalid,
    output logic       m0_awready,
    input  wire [31:0] m0_wdata,
    input  wire  [3:0] m0_wstrb,
    input  wire        m0_wvalid,
    output logic       m0_wready,
    output logic [1:0] m0_bresp,
    output logic       m0_bvalid,
    input  wire        m0_bready,
    input  wire [26:0] m0_araddr,
    input  wire        m0_arvalid,
    output logic       m0_arready,
    output logic [31:0] m0_rdata,
    output logic [1:0] m0_rresp,
    output logic       m0_rvalid,
    input  wire        m0_rready,

    input  wire [26:0] m1_awaddr,
    input  wire        m1_awvalid,
    output logic       m1_awready,
    input  wire [31:0] m1_wdata,
    input  wire  [3:0] m1_wstrb,
    input  wire        m1_wvalid,
    output logic       m1_wready,
    output logic [1:0] m1_bresp,
    output logic       m1_bvalid,
    input  wire        m1_bready,
    input  wire [26:0] m1_araddr,
    input  wire        m1_arvalid,
    output logic       m1_arready,
    output logic [31:0] m1_rdata,
    output logic [1:0] m1_rresp,
    output logic       m1_rvalid,
    input  wire        m1_rready,

    output logic [26:0] s_awaddr,
    output logic       s_awvalid,
    input  wire        s_awready,
    output logic [31:0] s_wdata,
    output logic  [3:0] s_wstrb,
    output logic       s_wvalid,
    input  wire        s_wready,
    input  wire  [1:0] s_bresp,
    input  wire        s_bvalid,
    output logic       s_bready,
    output logic [26:0] s_araddr,
    output logic       s_arvalid,
    input  wire        s_arready,
    input  wire [31:0] s_rdata,
    input  wire  [1:0] s_rresp,
    input  wire        s_rvalid,
    output logic       s_rready
);
    typedef enum logic [3:0] {
        IDLE,
        M0_WRITE,
        M0_WRITE_RESPONSE,
        M1_WRITE,
        M1_WRITE_RESPONSE,
        M0_READ,
        M0_READ_RESPONSE,
        M1_READ,
        M1_READ_RESPONSE
    } state_t;

    state_t state;
    logic   aw_complete;
    logic   w_complete;

    always_comb begin
        m0_awready = 1'b0;
        m0_wready  = 1'b0;
        m0_bresp   = s_bresp;
        m0_bvalid  = 1'b0;
        m0_arready = 1'b0;
        m0_rdata   = s_rdata;
        m0_rresp   = s_rresp;
        m0_rvalid  = 1'b0;

        m1_awready = 1'b0;
        m1_wready  = 1'b0;
        m1_bresp   = s_bresp;
        m1_bvalid  = 1'b0;
        m1_arready = 1'b0;
        m1_rdata   = s_rdata;
        m1_rresp   = s_rresp;
        m1_rvalid  = 1'b0;

        s_awaddr  = 27'd0;
        s_awvalid = 1'b0;
        s_wdata   = 32'd0;
        s_wstrb   = 4'd0;
        s_wvalid  = 1'b0;
        s_bready  = 1'b0;
        s_araddr  = 27'd0;
        s_arvalid = 1'b0;
        s_rready  = 1'b0;

        case (state)
            M0_WRITE: begin
                s_awaddr  = m0_awaddr + M0_ADDRESS_OFFSET;
                s_awvalid = m0_awvalid && !aw_complete;
                m0_awready = s_awready && !aw_complete;
                s_wdata   = m0_wdata;
                s_wstrb   = m0_wstrb;
                s_wvalid  = m0_wvalid && !w_complete;
                m0_wready = s_wready && !w_complete;
            end
            M0_WRITE_RESPONSE: begin
                m0_bvalid = s_bvalid;
                s_bready  = m0_bready;
            end
            M1_WRITE: begin
                s_awaddr  = m1_awaddr + M1_ADDRESS_OFFSET;
                s_awvalid = m1_awvalid && !aw_complete;
                m1_awready = s_awready && !aw_complete;
                s_wdata   = m1_wdata;
                s_wstrb   = m1_wstrb;
                s_wvalid  = m1_wvalid && !w_complete;
                m1_wready = s_wready && !w_complete;
            end
            M1_WRITE_RESPONSE: begin
                m1_bvalid = s_bvalid;
                s_bready  = m1_bready;
            end
            M0_READ: begin
                s_araddr   = m0_araddr + M0_ADDRESS_OFFSET;
                s_arvalid  = m0_arvalid;
                m0_arready = s_arready;
            end
            M0_READ_RESPONSE: begin
                m0_rvalid = s_rvalid;
                s_rready  = m0_rready;
            end
            M1_READ: begin
                s_araddr   = m1_araddr + M1_ADDRESS_OFFSET;
                s_arvalid  = m1_arvalid;
                m1_arready = s_arready;
            end
            M1_READ_RESPONSE: begin
                m1_rvalid = s_rvalid;
                s_rready  = m1_rready;
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state            <= IDLE;
            aw_complete      <= 1'b0;
            w_complete       <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    aw_complete      <= 1'b0;
                    w_complete       <= 1'b0;
                    if (m0_awvalid || m0_wvalid)
                        state <= M0_WRITE;
                    else if (m1_awvalid || m1_wvalid)
                        state <= M1_WRITE;
                    else if (m0_arvalid)
                        state <= M0_READ;
                    else if (m1_arvalid)
                        state <= M1_READ;
                end
                M0_WRITE, M1_WRITE: begin
                    if (s_awvalid && s_awready)
                        aw_complete <= 1'b1;
                    if (s_wvalid && s_wready)
                        w_complete <= 1'b1;
                    if ((aw_complete || (s_awvalid && s_awready)) &&
                        (w_complete || (s_wvalid && s_wready))) begin
                        if (state == M0_WRITE)
                            state <= M0_WRITE_RESPONSE;
                        else
                            state <= M1_WRITE_RESPONSE;
                    end
                end
                M0_WRITE_RESPONSE: begin
                    if (s_bvalid && m0_bready)
                        state <= IDLE;
                end
                M1_WRITE_RESPONSE: begin
                    if (s_bvalid && m1_bready)
                        state <= IDLE;
                end
                M0_READ: begin
                    if (s_arvalid && s_arready)
                        state <= M0_READ_RESPONSE;
                end
                M0_READ_RESPONSE: begin
                    if (s_rvalid && m0_rready)
                        state <= IDLE;
                end
                M1_READ: begin
                    if (s_arvalid && s_arready)
                        state <= M1_READ_RESPONSE;
                end
                M1_READ_RESPONSE: begin
                    if (s_rvalid && m1_rready)
                        state            <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
