// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

// FPGA-only JTAG rescue persona. This deliberately omits the HPS so Quartus
// can take a stranded HPS-first device all the way to user mode. Once user
// mode is reached, the SDM accepts a remote QSPI image-update request.
module de25_remote_rescue (
    input  wire        CLOCK0_50,
    output wire [7:0]  LED
);
    logic [27:0] heartbeat = '0;

    always_ff @(posedge CLOCK0_50)
        heartbeat <= heartbeat + 1'b1;

    assign LED = {7'b0000000, heartbeat[24]};
endmodule

`default_nettype wire
