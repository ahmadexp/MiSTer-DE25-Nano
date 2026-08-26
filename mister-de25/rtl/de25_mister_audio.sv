// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// 48 kHz, 16-bit stereo I2S from MiSTer's fixed 24.576 MHz audio clock.
module de25_mister_audio (
    input  logic        clk_audio,
    input  logic        reset,
    input  logic [15:0] core_left,
    input  logic [15:0] core_right,
    input  logic        core_signed,
    output logic        bit_clock,
    output logic        word_clock,
    output logic        serial_data
);
    logic [2:0] divider = '0;
    logic [5:0] bit_index = '0;
    logic [31:0] samples = '0;

    wire [15:0] left_sample  = core_signed ? core_left  : {~core_left[15], core_left[14:0]};
    wire [15:0] right_sample = core_signed ? core_right : {~core_right[15], core_right[14:0]};

    always_ff @(posedge clk_audio) begin
        if (reset) begin
            divider    <= '0;
            bit_index  <= '0;
            samples    <= '0;
            bit_clock  <= 1'b0;
            word_clock <= 1'b0;
            serial_data <= 1'b0;
        end else begin
            divider <= divider + 1'b1;

            // A transition every four master-clock cycles produces a
            // 3.072 MHz BCLK. Data changes on BCLK falling edges.
            if (divider[1:0] == 2'b11) begin
                bit_clock <= ~bit_clock;
                if (bit_clock) begin
                    if (bit_index == 6'd31) begin
                        bit_index <= '0;
                        samples <= {left_sample, right_sample};
                    end else begin
                        bit_index <= bit_index + 1'b1;
                    end

                    word_clock <= (bit_index >= 6'd15);
                    serial_data <= samples[6'd31 - bit_index];
                end
            end
        end
    end
endmodule
