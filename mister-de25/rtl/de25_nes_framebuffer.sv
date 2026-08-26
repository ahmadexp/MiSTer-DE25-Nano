// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

// Two-frame, clock-crossing 256x240 to 640x480 scaler. The completed NES
// frame bank changes only during HDMI vertical blank, so the authentic NES
// cadence cannot produce rolling, split frames, or mid-frame bank changes.
module de25_nes_framebuffer (
    input  wire        in_reset,
    input  wire        out_reset,
    input  wire        in_clk,
    input  wire        in_ce,
    input  wire [23:0] in_rgb,
    input  wire        in_de,
    input  wire        in_vs,
    input  wire        out_clk,
    input  wire  [7:0] diagnostic,
    output logic [23:0] out_rgb = '0,
    output logic        out_de = 1'b0,
    output logic        out_hs = 1'b1,
    output logic        out_vs = 1'b1,
    output logic        input_frame_seen = 1'b0
);
    logic write_bank = 1'b0;
    logic completed_bank = 1'b0;
    logic completed_toggle = 1'b0;
    logic last_in_de = 1'b0;
    logic last_in_vs = 1'b0;
    logic [7:0] in_x = '0;
    logic [7:0] in_y = '0;
    wire [16:0] write_addr = {write_bank, in_y, in_x};

    always_ff @(posedge in_clk) begin
        if (in_reset) begin
            write_bank <= 1'b0;
            completed_bank <= 1'b0;
            completed_toggle <= 1'b0;
            last_in_de <= 1'b0;
            last_in_vs <= 1'b0;
            in_x <= '0;
            in_y <= '0;
            input_frame_seen <= 1'b0;
        end else if (in_ce) begin
            last_in_de <= in_de;
            last_in_vs <= in_vs;

            if (in_vs != last_in_vs) begin
                if (in_y >= 8'd200) begin
                    completed_bank <= write_bank;
                    completed_toggle <= ~completed_toggle;
                    write_bank <= ~write_bank;
                    input_frame_seen <= 1'b1;
                end
                in_x <= '0;
                in_y <= '0;
            end else if (in_de) begin
                if (!last_in_de)
                    in_x <= '0;
                if (in_x != 8'hff)
                    in_x <= in_x + 1'b1;
            end else if (last_in_de) begin
                in_x <= '0;
                if (in_y != 8'hff)
                    in_y <= in_y + 1'b1;
            end
        end
    end

    (* ASYNC_REG = "TRUE" *) logic [1:0] completed_toggle_sync = '0;
    (* ASYNC_REG = "TRUE" *) logic [1:0] completed_bank_sync = '0;
    logic last_completed_toggle = 1'b0;
    logic pending_bank = 1'b0;
    logic read_bank = 1'b0;
    logic [9:0] h_count = '0;
    logic [9:0] v_count = '0;
    logic [23:0] pixel_q = '0;
    (* ASYNC_REG = "TRUE" *) logic [7:0] diagnostic_sync0 = '0;
    (* ASYNC_REG = "TRUE" *) logic [7:0] diagnostic_sync1 = '0;
    logic [2:0] diagnostic_index_pipe = '0;
    logic active_pipe = 1'b0;
    logic hs_pipe = 1'b1;
    logic vs_pipe = 1'b1;

    wire active_now = (h_count >= 10'd64) && (h_count < 10'd576) &&
                      (v_count < 10'd480);
    wire hs_now = !((h_count >= 10'd656) && (h_count < 10'd752));
    wire vs_now = !((v_count >= 10'd490) && (v_count < 10'd492));
    wire [7:0] source_x = (h_count - 10'd64) >> 1;
    wire [7:0] source_y = v_count[8:1];
    wire [16:0] read_addr = {read_bank, source_y, source_x};
    wire [23:0] frame_q;

    de25_nes_m20k_dp #(.ADDRESS_WIDTH(17), .DATA_WIDTH(24)) frame_memory (
        .write_clock(in_clk),
        .write_address(write_addr),
        .write_data(in_rgb),
        .write_enable(in_ce & in_de & ~in_reset),
        .read_clock(out_clk),
        .read_address(read_addr),
        .read_data(frame_q)
    );

    always_ff @(posedge out_clk) begin
        completed_toggle_sync <= {completed_toggle_sync[0], completed_toggle};
        completed_bank_sync <= {completed_bank_sync[0], completed_bank};

        if (out_reset) begin
            h_count <= '0;
            v_count <= '0;
            last_completed_toggle <= 1'b0;
            pending_bank <= 1'b0;
            read_bank <= 1'b0;
            pixel_q <= '0;
            diagnostic_sync0 <= '0;
            diagnostic_sync1 <= '0;
            diagnostic_index_pipe <= '0;
            active_pipe <= 1'b0;
            hs_pipe <= 1'b1;
            vs_pipe <= 1'b1;
            out_rgb <= '0;
            out_de <= 1'b0;
            out_hs <= 1'b1;
            out_vs <= 1'b1;
        end else begin
            diagnostic_sync0 <= diagnostic;
            diagnostic_sync1 <= diagnostic_sync0;

            if (completed_toggle_sync[1] != last_completed_toggle) begin
                last_completed_toggle <= completed_toggle_sync[1];
                pending_bank <= completed_bank_sync[1];
            end

            // Select a completed source frame only at the start of an HDMI
            // frame. The output frame is therefore internally coherent.
            if ((h_count == 0) && (v_count == 0))
                read_bank <= pending_bank;

            pixel_q <= active_now ? frame_q : 24'd0;
            // The active picture begins at h_count 64. Index from that
            // origin so the eight status blocks are bit 0 through bit 7
            // from left to right, without the previous one-block rotation.
            diagnostic_index_pipe <= (h_count - 10'd64) >> 6;
            active_pipe <= active_now;
            hs_pipe <= hs_now;
            vs_pipe <= vs_now;
            // Until the first complete NES frame arrives, show eight
            // left-to-right red/green state blocks instead of stale RAM.
            // Once video starts, preserve a 16-line diagnostic band at the
            // top so loader/core status remains visible during bring-up.
            if (active_pipe &&
                (!diagnostic_sync1[7] || (v_count < 10'd16)))
                out_rgb <= diagnostic_sync1[diagnostic_index_pipe] ?
                           24'h00ff00 : 24'hff0000;
            else
                out_rgb <= active_pipe ? pixel_q : 24'd0;
            out_de <= active_pipe;
            out_hs <= hs_pipe;
            out_vs <= vs_pipe;

            if (h_count == 10'd799) begin
                h_count <= '0;
                if (v_count == 10'd524)
                    v_count <= '0;
                else
                    v_count <= v_count + 1'b1;
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
