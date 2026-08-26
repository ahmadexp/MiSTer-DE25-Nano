// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// MiSTer sync-polarity normalizer, factored out of the Cyclone V sys_top so
// cores that instantiate arcade_video can use it with the DE25 shell.
module sync_fix (
    input  wire clk,
    input  wire sync_in,
    output wire sync_out
);
    logic pol = 1'b0;
    logic [31:0] count = '0;
    logic sync_meta = 1'b0;
    logic sync_last = 1'b0;

    assign sync_out = sync_in ^ pol;

    always_ff @(posedge clk) begin
        sync_meta <= sync_in;
        sync_last <= sync_meta;
        count <= sync_last ? count - 1'b1 : count + 1'b1;

        if (!sync_last && sync_meta) begin
            count <= '0;
            pol <= count[31];
        end
    end
endmodule
