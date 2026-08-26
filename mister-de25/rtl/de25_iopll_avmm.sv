// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Converts one 32-bit register request into the fixed-cycle, byte-wide Avalon
// protocol exposed by an Agilex 5 HVIO IOPLL. The protocol has no waitrequest:
// five preamble cycles, five transfer cycles, then five idle cycles. Bytes are
// transferred least-significant first. During a write, the fourth byte stays
// driven for the fifth transfer cycle. During a read, the first returned byte
// is a pipeline value and the following four bytes contain the register word.
module de25_iopll_avmm (
    input  logic        clk,
    input  logic        reset,

    input  logic        start,
    input  logic        write_request,
    input  logic  [8:0] address,
    input  logic [31:0] writedata,
    output logic [31:0] readdata,
    output logic        busy,
    output logic        done,

    output logic  [8:0] core_avl_address,
    output logic        core_avl_read,
    input  logic  [7:0] core_avl_readdata,
    output logic        core_avl_write,
    output logic  [7:0] core_avl_writedata
);

    logic  [3:0] cycle;
    logic        request_write;
    logic  [8:0] request_address;
    logic [31:0] request_writedata;

    assign core_avl_address = request_address;

    always_comb begin
        core_avl_read      = 1'b0;
        core_avl_write     = 1'b0;
        core_avl_writedata = 8'h00;

        if (busy && (cycle < 4'd10)) begin
            core_avl_read  = ~request_write;
            core_avl_write =  request_write;

            if (request_write && (cycle >= 4'd5)) begin
                case (cycle)
                    4'd5: core_avl_writedata = request_writedata[7:0];
                    4'd6: core_avl_writedata = request_writedata[15:8];
                    4'd7: core_avl_writedata = request_writedata[23:16];
                    default: core_avl_writedata = request_writedata[31:24];
                endcase
            end
        end
    end

    always_ff @(posedge clk) begin
        done <= 1'b0;

        if (reset) begin
            cycle             <= 4'd0;
            request_write     <= 1'b0;
            request_address   <= 9'd0;
            request_writedata <= 32'd0;
            readdata          <= 32'd0;
            busy              <= 1'b0;
        end else if (!busy) begin
            if (start) begin
                cycle             <= 4'd0;
                request_write     <= write_request;
                request_address   <= address;
                request_writedata <= writedata;
                readdata          <= 32'd0;
                busy              <= 1'b1;
            end
        end else begin
            // Read cycle 5 is the documented pipeline byte. Capture the four
            // register bytes on cycles 6 through 9, least-significant first.
            if (!request_write) begin
                case (cycle)
                    4'd6: readdata[7:0]   <= core_avl_readdata;
                    4'd7: readdata[15:8]  <= core_avl_readdata;
                    4'd8: readdata[23:16] <= core_avl_readdata;
                    4'd9: readdata[31:24] <= core_avl_readdata;
                    default: ;
                endcase
            end

            if (cycle == 4'd14) begin
                cycle <= 4'd0;
                busy  <= 1'b0;
                done  <= 1'b1;
            end else begin
                cycle <= cycle + 1'b1;
            end
        end
    end

endmodule
