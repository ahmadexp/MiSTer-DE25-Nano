// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
`default_nettype none

module de25_i2c_register_master_tb;
    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic command_valid = 1'b0;
    wire command_ready;
    logic command_write = 1'b0;
    logic [6:0] device_address = 7'h6a;
    logic [7:0] register_address = 8'h0d;
    logic [7:0] write_data = 8'h00;
    wire [7:0] read_data;
    wire busy;
    wire done;
    wire error;
    wire [2:0] error_code;
    tri1 scl;
    tri1 sda;
    logic [7:0] slave_read_data = 8'h53;

    // ACK all transmitted bytes. During the read byte, drive zeroes and
    // release ones from the requested test value.
    assign sda = (dut.state >= 9 && dut.state <= 12) ? 1'b0 :
                 (dut.state >= 18 && dut.state <= 21) ?
                    (slave_read_data[dut.bit_index] ? 1'bz : 1'b0) : 1'bz;

    de25_i2c_register_master #(
        .CLOCK_HZ(1_000_000),
        .I2C_HZ(50_000)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .command_valid(command_valid),
        .command_ready(command_ready),
        .command_write(command_write),
        .device_address(device_address),
        .register_address(register_address),
        .write_data(write_data),
        .read_data(read_data),
        .busy(busy),
        .done(done),
        .error(error),
        .error_code(error_code),
        .scl(scl),
        .sda(sda)
    );

    always #5 clk = ~clk;

    task automatic issue_command(input logic write_command);
        begin
            while (!command_ready)
                @(posedge clk);
            command_write <= write_command;
            command_valid <= 1'b1;
            @(posedge clk);
            command_valid <= 1'b0;
            while (!done)
                @(posedge clk);
            if (error)
                $fatal(1, "I2C command failed with code %0d", error_code);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset_n <= 1'b1;

        issue_command(1'b0);
        if (read_data != 8'h53)
            $fatal(1, "read returned %02x instead of 53", read_data);

        register_address <= 8'h06;
        write_data <= 8'h01;
        issue_command(1'b1);

        if (busy || scl !== 1'b1 || sda !== 1'b1)
            $fatal(1, "master did not release the bus after commands");
        $display("PASS: platform-v2 I2C register read/write and bus release");
        $finish;
    end
endmodule

`default_nettype wire
