// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

// Explicit Agilex 5 M20K simple-dual-port memory. Agilex permits independent
// write/read clocks in this mode, which is exactly what the framebuffer and
// mapper-0 cartridge banks require.
module de25_nes_m20k_dp #(
    parameter integer ADDRESS_WIDTH = 8,
    parameter integer DATA_WIDTH = 8
) (
    input  wire                     write_clock,
    input  wire [ADDRESS_WIDTH-1:0] write_address,
    input  wire [DATA_WIDTH-1:0]    write_data,
    input  wire                     write_enable,
    input  wire                     read_clock,
    input  wire [ADDRESS_WIDTH-1:0] read_address,
    output wire [DATA_WIDTH-1:0]    read_data
);
    localparam integer WORDS = 1 << ADDRESS_WIDTH;
    localparam integer BYTE_LANES = DATA_WIDTH / 8;

    altsyncram #(
        .address_reg_b("CLOCK1"),
        .byte_size(8),
        .clock_enable_input_a("BYPASS"),
        .clock_enable_input_b("BYPASS"),
        .clock_enable_output_b("BYPASS"),
        .intended_device_family("Agilex 5"),
        .lpm_type("altsyncram"),
        .numwords_a(WORDS),
        .numwords_b(WORDS),
        .operation_mode("DUAL_PORT"),
        .outdata_aclr_b("NONE"),
        .outdata_reg_b("UNREGISTERED"),
        .power_up_uninitialized("FALSE"),
        .ram_block_type("M20K"),
        // Loader verification and display reads never depend on the value
        // returned during a simultaneous mixed-port write.
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .widthad_a(ADDRESS_WIDTH),
        .widthad_b(ADDRESS_WIDTH),
        .width_a(DATA_WIDTH),
        .width_b(DATA_WIDTH),
        .width_byteena_a(BYTE_LANES),
        .width_byteena_b(BYTE_LANES)
    ) ram (
        .aclr0(1'b0),
        .aclr1(1'b0),
        .address_a(write_address),
        .address_b(read_address),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .byteena_a({BYTE_LANES{1'b1}}),
        .byteena_b({BYTE_LANES{1'b1}}),
        .clock0(write_clock),
        .clock1(read_clock),
        .clocken0(1'b1),
        .clocken1(1'b1),
        .clocken2(1'b1),
        .clocken3(1'b1),
        .data_a(write_data),
        .data_b({DATA_WIDTH{1'b0}}),
        .eccstatus(),
        .q_a(),
        .q_b(read_data),
        .rden_a(1'b1),
        .rden_b(1'b1),
        .wren_a(write_enable),
        .wren_b(1'b0)
    );
endmodule

`default_nettype wire
