// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

// Read-only Si5332B presence probe for the DE25-Nano rev-B board.
//
// The two external pins are strictly open drain: the fabric can pull a line
// low or release it, but can never drive it high.  After Reset Release and a
// settling delay, the controller performs one address-only transaction at
// 0x6a and one at 0x6b.  It sends no register or data bytes, so the Si5332B
// configuration and NVM cannot be modified by this image.
module de25_si5332_probe (
    input  wire       CLOCK0_50,
    input  wire [1:0] KEY,
    output logic [7:0] LED,
    inout  wire       SI5332_SDA,
    inout  wire       SI5332_SCL
);
    localparam integer TICK_DIV = 500; // 10 us at 50 MHz, 25 kHz I2C clock.

    typedef enum logic [4:0] {
        ST_WAIT_BUS,
        ST_START_RELEASE,
        ST_START_SDA_LOW,
        ST_START_SCL_LOW,
        ST_BIT_SETUP,
        ST_BIT_RISE,
        ST_BIT_HIGH,
        ST_BIT_FALL,
        ST_ACK_SETUP,
        ST_ACK_RISE,
        ST_ACK_HIGH,
        ST_ACK_FALL,
        ST_STOP_DATA_LOW,
        ST_STOP_CLOCK_HIGH,
        ST_STOP_DATA_HIGH,
        ST_INTER_PROBE,
        ST_DONE,
        ST_FAULT
    } state_t;

    logic ninit_done;
    logic [19:0] power_on_reset = '0;
    logic [8:0] tick_count = '0;
    logic [25:0] heartbeat = '0;
    logic [3:0] inter_probe_count = '0;
    logic [7:0] tx_byte = 8'hd4;
    logic [2:0] bit_index = 3'd7;
    logic probe_index = 1'b0;
    logic scl_low = 1'b0;
    logic sda_low = 1'b0;
    logic ack_6a = 1'b0;
    logic ack_6b = 1'b0;
    logic done = 1'b0;
    logic bus_fault = 1'b0;
    state_t state = ST_WAIT_BUS;

    wire reset_n = KEY[0] && (&power_on_reset) && !ninit_done;
    wire scl_in = SI5332_SCL;
    wire sda_in = SI5332_SDA;
    wire tick = (tick_count == TICK_DIV - 1);

    // Explicit open-drain behavior.  There is intentionally no assignment
    // that can drive either external line to logic one.
    assign SI5332_SCL = scl_low ? 1'b0 : 1'bz;
    assign SI5332_SDA = sda_low ? 1'b0 : 1'bz;

    ResetRelease reset_release (
        .ninit_done(ninit_done)
    );

    always_ff @(posedge CLOCK0_50) begin
        heartbeat <= heartbeat + 1'b1;

        if (ninit_done || !KEY[0])
            power_on_reset <= '0;
        else if (!(&power_on_reset))
            power_on_reset <= power_on_reset + 1'b1;

        if (!reset_n || tick)
            tick_count <= '0;
        else
            tick_count <= tick_count + 1'b1;

        if (!reset_n) begin
            state             <= ST_WAIT_BUS;
            inter_probe_count <= '0;
            tx_byte           <= 8'hd4;
            bit_index         <= 3'd7;
            probe_index       <= 1'b0;
            scl_low           <= 1'b0;
            sda_low           <= 1'b0;
            ack_6a            <= 1'b0;
            ack_6b            <= 1'b0;
            done              <= 1'b0;
            bus_fault         <= 1'b0;
        end else if (tick) begin
            case (state)
                ST_WAIT_BUS: begin
                    // Never attempt recovery clocks on an unexpectedly low
                    // bus.  Latch the fault and leave both pins released.
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    if (scl_in && sda_in)
                        state <= ST_START_RELEASE;
                    else begin
                        bus_fault <= 1'b1;
                        state <= ST_FAULT;
                    end
                end

                ST_START_RELEASE: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    if (!scl_in || !sda_in) begin
                        bus_fault <= 1'b1;
                        state <= ST_FAULT;
                    end else begin
                        state <= ST_START_SDA_LOW;
                    end
                end

                ST_START_SDA_LOW: begin
                    // I2C START: SDA falls while SCL remains released high.
                    sda_low <= 1'b1;
                    scl_low <= 1'b0;
                    state <= ST_START_SCL_LOW;
                end

                ST_START_SCL_LOW: begin
                    scl_low <= 1'b1;
                    state <= ST_BIT_SETUP;
                end

                ST_BIT_SETUP: begin
                    // Zero is driven low; one is represented by release.
                    scl_low <= 1'b1;
                    sda_low <= ~tx_byte[bit_index];
                    state <= ST_BIT_RISE;
                end

                ST_BIT_RISE: begin
                    scl_low <= 1'b0;
                    state <= ST_BIT_HIGH;
                end

                ST_BIT_HIGH: begin
                    if (!scl_in) begin
                        bus_fault <= 1'b1;
                        state <= ST_FAULT;
                    end else begin
                        state <= ST_BIT_FALL;
                    end
                end

                ST_BIT_FALL: begin
                    scl_low <= 1'b1;
                    if (bit_index == 0)
                        state <= ST_ACK_SETUP;
                    else begin
                        bit_index <= bit_index - 1'b1;
                        state <= ST_BIT_SETUP;
                    end
                end

                ST_ACK_SETUP: begin
                    // Release SDA for the slave ACK bit.
                    scl_low <= 1'b1;
                    sda_low <= 1'b0;
                    state <= ST_ACK_RISE;
                end

                ST_ACK_RISE: begin
                    scl_low <= 1'b0;
                    state <= ST_ACK_HIGH;
                end

                ST_ACK_HIGH: begin
                    if (!scl_in) begin
                        bus_fault <= 1'b1;
                        state <= ST_FAULT;
                    end else begin
                        if (!probe_index)
                            ack_6a <= ~sda_in;
                        else
                            ack_6b <= ~sda_in;
                        state <= ST_ACK_FALL;
                    end
                end

                ST_ACK_FALL: begin
                    scl_low <= 1'b1;
                    state <= ST_STOP_DATA_LOW;
                end

                ST_STOP_DATA_LOW: begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b1;
                    state <= ST_STOP_CLOCK_HIGH;
                end

                ST_STOP_CLOCK_HIGH: begin
                    scl_low <= 1'b0;
                    if (!scl_in) begin
                        bus_fault <= 1'b1;
                        state <= ST_FAULT;
                    end else begin
                        state <= ST_STOP_DATA_HIGH;
                    end
                end

                ST_STOP_DATA_HIGH: begin
                    // I2C STOP: SDA rises while SCL is released high.
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    if (!probe_index) begin
                        probe_index <= 1'b1;
                        tx_byte <= 8'hd6;
                        bit_index <= 3'd7;
                        inter_probe_count <= '0;
                        state <= ST_INTER_PROBE;
                    end else begin
                        done <= 1'b1;
                        state <= ST_DONE;
                    end
                end

                ST_INTER_PROBE: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    if (!scl_in || !sda_in) begin
                        bus_fault <= 1'b1;
                        state <= ST_FAULT;
                    end else if (&inter_probe_count) begin
                        state <= ST_START_RELEASE;
                    end else begin
                        inter_probe_count <= inter_probe_count + 1'b1;
                    end
                end

                ST_DONE: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    done <= 1'b1;
                end

                default: begin
                    // Fail safe: immediately release both wires.
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    bus_fault <= 1'b1;
                    state <= ST_FAULT;
                end
            endcase
        end
    end

    wire [31:0] status_word = {
        16'h5332,
        4'h0,
        state[3:0],
        bus_fault,
        done,
        ack_6b,
        ack_6a,
        sda_in,
        scl_in,
        sda_low,
        scl_low
    };

    // A probe-only In-System Sources and Probes node provides a JTAG-readable
    // status word.  There is no JTAG source capable of initiating writes.
    altsource_probe status_probe (
        .probe(status_word),
        .source()
    );
    defparam
        status_probe.enable_metastability = "YES",
        status_probe.instance_id = "S533",
        status_probe.probe_width = 32,
        status_probe.sld_auto_instance_index = "YES",
        status_probe.sld_instance_index = 0,
        status_probe.source_initial_value = "0",
        status_probe.source_width = 0;

    always_comb begin
        LED[0] = heartbeat[25];
        LED[1] = reset_n;
        LED[2] = scl_in;
        LED[3] = sda_in;
        LED[4] = ack_6a;
        LED[5] = ack_6b;
        LED[6] = done;
        LED[7] = bus_fault;
    end
endmodule

`default_nettype wire
