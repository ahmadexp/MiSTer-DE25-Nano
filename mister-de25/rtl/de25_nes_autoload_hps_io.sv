// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

// Minimal MiSTer HPS-I/O replacement for a self-contained NES diagnostic.
// It streams one user-supplied iNES image into the unmodified upstream loader
// after configuration. No HPS, SD card, or Linux service is required.
module hps_io #(
    parameter CONF_STR = ""
) (
    input  wire         clk_sys,
    inout  wire [45:0]  HPS_BUS,
    output logic [23:0] joystick_0 = '0,
    output logic [23:0] joystick_1 = '0,
    output logic [23:0] joystick_2 = '0,
    output logic [23:0] joystick_3 = '0,
    output logic [15:0] joystick_l_analog_0 = '0,
    output logic [15:0] joystick_l_analog_1 = '0,
    output logic  [7:0] paddle_0 = '0,
    output logic  [7:0] paddle_1 = '0,
    output logic  [7:0] paddle_2 = '0,
    output logic  [7:0] paddle_3 = '0,
    output wire   [1:0] buttons,
    output wire         forced_scandoubler,
    input  wire         new_vmode,
    output logic [127:0] status = '0,
    input  wire [127:0] status_in,
    input  wire         status_set,
    input  wire  [15:0] status_menumask,
    input  wire         info_req,
    input  wire   [7:0] info,
    inout  wire  [21:0] gamma_bus,
    output logic        ioctl_download = 1'b0,
    output logic [26:0] ioctl_addr = '0,
    output logic        ioctl_wr = 1'b0,
    output logic  [7:0] ioctl_dout = '0,
    input  wire         ioctl_wait,
    output logic [15:0] ioctl_index = '0,
    input  wire  [31:0] sd_lba [1],
    input  wire   [0:0] sd_rd,
    input  wire   [0:0] sd_wr,
    output logic  [0:0] sd_ack = '0,
    output logic [13:0] sd_buff_addr = '0,
    output logic  [7:0] sd_buff_dout = '0,
    input  wire   [7:0] sd_buff_din [1],
    output logic        sd_buff_wr = 1'b0,
    output logic  [0:0] img_mounted = '0,
    output logic        img_readonly = 1'b1,
    output logic [63:0] img_size = '0,
    output logic [10:0] ps2_key = '0,
    input  wire   [2:0] ps2_kbd_led_use,
    input  wire   [2:0] ps2_kbd_led_status,
    output logic [24:0] ps2_mouse = '0
);
    localparam integer ROM_SIZE = 40976;
    localparam integer LAST_ADDR = ROM_SIZE - 1;

    (* ramstyle = "M20K", ram_init_file =
       "../artifacts/private/nes_autoload.hex" *)
    logic [7:0] rom [0:ROM_SIZE-1];
    initial $readmemh("../artifacts/private/nes_autoload.hex", rom);

    typedef enum logic [2:0] {
        WAIT_CLOCKS,
        START_DOWNLOAD,
        PREFETCH,
        SEND_BYTE,
        WAIT_LAST_BUSY,
        WAIT_LAST_DONE,
        COMPLETE
    } load_state_t;

    load_state_t load_state = WAIT_CLOCKS;
    logic [9:0] startup_count = '0;
    logic [7:0] rom_q = '0;

    assign buttons = 2'b00;
    assign forced_scandoubler = 1'b0;
    assign gamma_bus[20:0] = 21'd0;
    assign gamma_bus[21] = 1'bz;

    // These are the only HPS_BUS fields consumed by the upstream hps_io
    // boundary. The remaining fields are video feedback driven by the top.
    assign HPS_BUS[37] = ioctl_wait;
    assign HPS_BUS[36] = clk_sys;
    assign HPS_BUS[32] = 1'b0;
    // Export loader progress through otherwise unused HPS_BUS inputs so the
    // standalone top can display diagnostics without SignalTap or an HPS.
    assign HPS_BUS[15:0] = {
        ioctl_addr[8:0],
        (load_state == COMPLETE),
        (ioctl_addr == LAST_ADDR),
        ioctl_wait,
        ioctl_download,
        load_state
    };

    always_ff @(posedge clk_sys) begin
        ioctl_wr <= 1'b0;
        sd_ack <= '0;
        sd_buff_wr <= 1'b0;

        case (load_state)
            WAIT_CLOCKS: begin
                // Do not rely on output-port declaration initializers. Older
                // source constructs are accepted by Quartus but are not a
                // portable power-up guarantee for an Agilex configuration.
                ioctl_download <= 1'b0;
                ioctl_addr <= '0;
                ioctl_wr <= 1'b0;
                ioctl_dout <= '0;
                ioctl_index <= '0;
                startup_count <= startup_count + 1'b1;
                if (&startup_count) begin
                    ioctl_download <= 1'b1;
                    // The NES wrapper encodes the selected extension in the
                    // upper two bits of ioctl_index[7:0]. 0x40 is an iNES
                    // cartridge; 0x00 would incorrectly select FDS BIOS.
                    ioctl_index <= 16'h0040;
                    ioctl_addr <= 27'd0;
                    startup_count <= '0;
                    load_state <= START_DOWNLOAD;
                end
            end

            // Give the NES wrapper several master-clock edges to observe the
            // download level and assert its loader reset before byte zero.
            START_DOWNLOAD: begin
                startup_count <= startup_count + 1'b1;
                if (startup_count[3:0] == 4'hf)
                    load_state <= PREFETCH;
            end

            PREFETCH: begin
                rom_q <= rom[ioctl_addr];
                load_state <= SEND_BYTE;
            end

            SEND_BYTE: begin
                if (!ioctl_wait) begin
                    ioctl_dout <= rom_q;
                    ioctl_wr <= 1'b1;
                    if (ioctl_addr == LAST_ADDR) begin
                        load_state <= WAIT_LAST_BUSY;
                    end else begin
                        ioctl_addr <= ioctl_addr + 1'b1;
                        load_state <= PREFETCH;
                    end
                end
            end

            WAIT_LAST_BUSY: begin
                if (ioctl_wait)
                    load_state <= WAIT_LAST_DONE;
            end

            WAIT_LAST_DONE: begin
                if (!ioctl_wait) begin
                    ioctl_download <= 1'b0;
                    load_state <= COMPLETE;
                end
            end

            default: begin
                ioctl_download <= 1'b0;
            end
        endcase

        // Keep the static status deterministic. The selected ROM is NTSC,
        // video dijitter remains enabled, and both audio paths remain on.
        if (status_set)
            status <= status_in;
    end

    wire unused = &{1'b0, new_vmode, status_menumask,
                    info_req, info, sd_lba[0], sd_rd, sd_wr,
                    sd_buff_din[0], ps2_kbd_led_use,
                    ps2_kbd_led_status};
endmodule

`default_nettype wire
