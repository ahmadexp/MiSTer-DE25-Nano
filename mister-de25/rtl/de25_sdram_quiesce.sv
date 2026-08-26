// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

// Safely stop an SDR SDRAM interface before changing its source clock.
//
// request_control is asynchronous to clk_sdram. The request crosses into the
// SDRAM domain, lowers sdram_active, and then advances through a second
// registered stage. The physical SDRAM clock is a phase-shifted output from
// the same IOPLL, so one physical rising edge occurs between consecutive
// clk_sdram rising edges. CKE is therefore sampled low before acknowledgement
// returns to clk_control.
module de25_sdram_quiesce (
    input  wire clk_control,
    input  wire reset_control,
    input  wire clk_sdram,
    input  wire pll_locked,
    input  wire request_control,
    input  wire hold_sdram,
    input  wire ready_sdram = 1'b1,
    output wire quiesced_control,
    output wire sdram_active
);
    wire ram_request_async = request_control | reset_control | ~pll_locked;

    (* ASYNC_REG = "TRUE" *) logic [1:0] ram_request_sync = 2'b11;
    (* preserve *) logic [1:0] ram_quiesce_pipe = 2'b11;

    always_ff @(posedge clk_sdram) begin
        ram_request_sync <= {ram_request_sync[0], ram_request_async};
        ram_quiesce_pipe <= {
            ram_quiesce_pipe[0],
            (ram_request_sync[1] & ready_sdram) | hold_sdram
        };
    end

    // An unexpected loss of lock disables the pins immediately. A requested
    // reconfiguration still waits for the registered acknowledgement below.
    assign sdram_active = pll_locked & ~ram_quiesce_pipe[0];

    (* ASYNC_REG = "TRUE" *) logic [1:0] ram_quiesced_sync = 2'b11;
    always_ff @(posedge clk_control) begin
        if (reset_control) begin
            ram_quiesced_sync <= 2'b11;
        end else begin
            ram_quiesced_sync <= {
                ram_quiesced_sync[0],
                ram_quiesce_pipe[1]
            };
        end
    end

    assign quiesced_control = ram_quiesced_sync[1];
endmodule

`default_nettype wire
