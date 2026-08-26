// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

// Mapper-0-focused on-chip replacement for the MiSTer NES SDRAM controller.
// The upstream loader and CPU/PPU buses remain unchanged. Program ROM, CHR
// ROM, CPU RAM, and nametable RAM occupy separate M20K banks, eliminating the
// external SDRAM read-capture path while preserving its request protocol.
module sdram (
    input  wire [15:0] SDRAM_DQ_IN,
    output logic [15:0] SDRAM_DQ_OUT = '0,
    output logic        SDRAM_DQ_OE = 1'b0,
    output wire  [12:0] SDRAM_A,
    output logic        SDRAM_DQML = 1'b1,
    output logic        SDRAM_DQMH = 1'b1,
    output logic  [1:0] SDRAM_BA = '0,
    output logic        SDRAM_nCS = 1'b1,
    output logic        SDRAM_nWE = 1'b1,
    output logic        SDRAM_nRAS = 1'b1,
    output logic        SDRAM_nCAS = 1'b1,
    output wire         SDRAM_CLK,
    output wire         SDRAM_CKE,
    input  wire         init,
    input  wire         clk,
    input  wire         clk_capture,
    input  wire         clk_physical,
    input  wire         active,
    input  wire         quiesce,
    output wire         quiesced,
    input  wire [24:0]  ch0_addr,
    input  wire         ch0_rd,
    input  wire         ch0_wr,
    input  wire  [7:0]  ch0_din,
    output wire  [7:0]  ch0_dout,
    output logic        ch0_busy = 1'b0,
    input  wire [24:0]  ch1_addr,
    input  wire         ch1_rd,
    input  wire         ch1_wr,
    input  wire  [7:0]  ch1_din,
    output wire  [7:0]  ch1_dout,
    output logic        ch1_busy = 1'b0,
    input  wire [24:0]  ch2_addr,
    input  wire         ch2_rd,
    input  wire         ch2_wr,
    input  wire  [7:0]  ch2_din,
    output logic [7:0]  ch2_dout = 8'h00,
    output logic        ch2_busy = 1'b0,
    input  wire         refresh,
    input  wire [15:0]  ss_in,
    input  wire         ss_load,
    output wire [15:0]  ss_out
);
    localparam logic [24:0] CHR_BASE = 25'h0200000;
    localparam logic [24:0] CPU_RAM_BASE = 25'h0380000;
    localparam logic [24:0] NT_RAM_BASE = 25'h03a0000;

    logic ch0_seen = 1'b0;
    logic ch1_seen = 1'b0;
    logic ch2_seen = 1'b0;
    wire ch0_req = ch0_rd | ch0_wr;
    wire ch1_req = ch1_rd | ch1_wr;
    wire ch2_req = ch2_rd | ch2_wr;
    wire ch0_accept = ch0_req & ~ch0_seen;
    wire ch1_accept = ch1_req & ~ch1_seen;

    wire ch0_is_prg = ch0_addr < 25'h08000;
    wire ch0_is_chr = (ch0_addr >= CHR_BASE) &&
                      (ch0_addr < CHR_BASE + 25'h02000);
    wire ch0_is_nt = (ch0_addr >= NT_RAM_BASE) &&
                     (ch0_addr < NT_RAM_BASE + 25'h00800);
    wire ch1_is_prg = ch1_addr < 25'h08000;
    wire ch1_is_cpu = (ch1_addr >= CPU_RAM_BASE) &&
                      (ch1_addr < CPU_RAM_BASE + 25'h00800);

    wire [7:0] prg_ch0_q;
    wire [7:0] prg_ch1_q;
    wire [7:0] chr_ch0_q;
    wire [7:0] cpu_ch1_q;
    wire [7:0] nt_ch0_q;

    logic ch1_request_pipe = 1'b0;
    logic [14:0] ch1_address_pipe = '0;
    logic reset_low_seen = 1'b0;
    logic reset_low_correct = 1'b0;
    logic reset_high_seen = 1'b0;
    logic reset_high_correct = 1'b0;
    logic first_opcode_seen = 1'b0;
    logic first_opcode_correct = 1'b0;

    // Loader verification and CPU execution must not multiplex a registered
    // M20K read address. Keep two identical PRG banks so each consumer owns a
    // physical read port while loader writes update both copies atomically.
    de25_nes_m20k_dp #(.ADDRESS_WIDTH(15), .DATA_WIDTH(8)) prg_verify_memory (
        .write_clock(clk),
        .write_address(ch0_addr[14:0]),
        .write_data(ch0_din),
        .write_enable(ch0_accept & ch0_wr & ch0_is_prg),
        .read_clock(clk),
        .read_address(ch0_addr[14:0]),
        .read_data(prg_ch0_q)
    );

    de25_nes_m20k_dp #(.ADDRESS_WIDTH(15), .DATA_WIDTH(8)) prg_cpu_memory (
        .write_clock(clk),
        .write_address(ch0_addr[14:0]),
        .write_data(ch0_din),
        .write_enable(ch0_accept & ch0_wr & ch0_is_prg),
        .read_clock(clk),
        .read_address(ch1_addr[14:0]),
        .read_data(prg_ch1_q)
    );

    de25_nes_m20k_dp #(.ADDRESS_WIDTH(13), .DATA_WIDTH(8)) chr_memory (
        .write_clock(clk),
        .write_address(ch0_addr[12:0]),
        .write_data(ch0_din),
        .write_enable(ch0_accept & ch0_wr & ch0_is_chr),
        .read_clock(clk),
        .read_address(ch0_addr[12:0]),
        .read_data(chr_ch0_q)
    );

    de25_nes_m20k_dp #(.ADDRESS_WIDTH(11), .DATA_WIDTH(8)) cpu_memory (
        .write_clock(clk),
        .write_address(ch1_addr[10:0]),
        .write_data(ch1_din),
        .write_enable(ch1_accept & ch1_wr & ch1_is_cpu),
        .read_clock(clk),
        .read_address(ch1_addr[10:0]),
        .read_data(cpu_ch1_q)
    );

    de25_nes_m20k_dp #(.ADDRESS_WIDTH(11), .DATA_WIDTH(8)) nametable_memory (
        .write_clock(clk),
        .write_address(ch0_addr[10:0]),
        .write_data(ch0_din),
        .write_enable(ch0_accept & ch0_wr & ch0_is_nt),
        .read_clock(clk),
        .read_address(ch0_addr[10:0]),
        .read_data(nt_ch0_q)
    );

    assign ch0_dout = ch0_is_prg ? prg_ch0_q :
                       ch0_is_chr ? chr_ch0_q :
                       ch0_is_nt  ? nt_ch0_q  : 8'h00;
    assign ch1_dout = ch1_is_prg ? prg_ch1_q :
                       ch1_is_cpu ? cpu_ch1_q : 8'h00;

    assign SDRAM_CLK = 1'b0;
    assign SDRAM_CKE = 1'b0;
    // The standalone top does not connect these logical SDRAM pins to the
    // physical device. Reuse SDRAM_A as a sticky debug conduit.
    assign SDRAM_A = {7'd0, first_opcode_correct, first_opcode_seen,
                      reset_high_correct, reset_high_seen,
                      reset_low_correct, reset_low_seen};
    assign quiesced = 1'b1;
    assign ss_out = 16'd0;

    always_ff @(posedge clk) begin
        ch0_busy <= 1'b0;
        ch1_busy <= 1'b0;
        ch2_busy <= 1'b0;

        ch1_request_pipe <= ch1_req & ch1_is_prg;
        ch1_address_pipe <= ch1_addr[14:0];
        if (ch1_request_pipe) begin
            if (ch1_address_pipe == 15'h7ffc) begin
                reset_low_seen <= 1'b1;
                if (prg_ch1_q == 8'h00)
                    reset_low_correct <= 1'b1;
            end
            if (ch1_address_pipe == 15'h7ffd) begin
                reset_high_seen <= 1'b1;
                if (prg_ch1_q == 8'h80)
                    reset_high_correct <= 1'b1;
            end
            if (ch1_address_pipe == 15'h0000) begin
                first_opcode_seen <= 1'b1;
                if (prg_ch1_q == 8'h78)
                    first_opcode_correct <= 1'b1;
            end
        end

        if (!ch0_req)
            ch0_seen <= 1'b0;
        else if (!ch0_seen) begin
            ch0_seen <= 1'b1;
            ch0_busy <= 1'b1;
        end

        if (!ch1_req)
            ch1_seen <= 1'b0;
        else if (!ch1_seen) begin
            ch1_seen <= 1'b1;
            ch1_busy <= 1'b1;
        end

        if (!ch2_req)
            ch2_seen <= 1'b0;
        else if (!ch2_seen) begin
            ch2_seen <= 1'b1;
            ch2_busy <= 1'b1;
            ch2_dout <= 8'h00;
        end
    end

    wire unused = &{1'b0, SDRAM_DQ_IN, init, clk_capture, clk_physical,
                    active, quiesce, ch2_addr, ch2_wr, ch2_din, refresh,
                    ss_in, ss_load};
endmodule

`default_nettype wire
