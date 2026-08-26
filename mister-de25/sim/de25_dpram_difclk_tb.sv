`timescale 1ns/1ps

module de25_dpram_difclk_tb;

logic clk = 1'b0;
always #5 clk = ~clk;

logic [19:0] bit_address;
logic bit_data;
logic bit_write;
wire bit_q;
logic [15:0] word_address;
logic [15:0] word_data;
logic word_write;
wire [15:0] word_q;

dpram_difclk #(20, 1, 16, 16) mb128_ram (
    .clock0(clk), .clock1(clk),
    .address_a(bit_address), .data_a(bit_data),
    .enable_a(1'b1), .wren_a(bit_write), .q_a(bit_q), .cs_a(1'b1),
    .address_b(word_address), .data_b(word_data),
    .enable_b(1'b1), .wren_b(word_write), .q_b(word_q), .cs_b(1'b1)
);

logic [10:0] byte_address;
logic [7:0] byte_data;
logic byte_write;
wire [7:0] byte_q;
logic [9:0] half_address;
logic [15:0] half_data;
logic half_write;
wire [15:0] half_q;

dpram_difclk #(11, 8, 10, 16) backup_ram (
    .clock0(clk), .clock1(clk),
    .address_a(byte_address), .data_a(byte_data),
    .enable_a(1'b1), .wren_a(byte_write), .q_a(byte_q), .cs_a(1'b1),
    .address_b(half_address), .data_b(half_data),
    .enable_b(1'b1), .wren_b(half_write), .q_b(half_q), .cs_b(1'b1)
);

task automatic write_mb128_word(input [15:0] address, input [15:0] value);
begin
    @(negedge clk);
    word_address = address;
    word_data = value;
    word_write = 1'b1;
    @(negedge clk);
    word_write = 1'b0;
end
endtask

task automatic read_mb128_word(input [15:0] address, input [15:0] expected);
begin
    @(negedge clk);
    word_address = address;
    @(posedge clk);
    #1;
    if (word_q !== expected)
        $fatal(1, "MB128 word %h read %h, expected %h", address, word_q,
               expected);
end
endtask

task automatic write_backup_half(input [9:0] address, input [15:0] value);
begin
    @(negedge clk);
    half_address = address;
    half_data = value;
    half_write = 1'b1;
    @(negedge clk);
    half_write = 1'b0;
end
endtask

initial begin
    bit_address = '0;
    bit_data = '0;
    bit_write = 1'b0;
    word_address = '0;
    word_data = '0;
    word_write = 1'b0;
    byte_address = '0;
    byte_data = '0;
    byte_write = 1'b0;
    half_address = '0;
    half_data = '0;
    half_write = 1'b0;

    repeat (2) @(posedge clk);

    // Consecutive even and odd B words share one packed physical word. The
    // registered sub-word selector must follow Quartus's registered B address.
    write_mb128_word(16'h1234, 16'hA55A);
    write_mb128_word(16'h1235, 16'h3CC3);
    read_mb128_word(16'h1234, 16'hA55A);
    read_mb128_word(16'h1235, 16'h3CC3);
    read_mb128_word(16'h1234, 16'hA55A);

    // Verify the one-bit protocol port sees the same packed storage.
    for (integer bit_index = 0; bit_index < 16; bit_index = bit_index + 1) begin
        bit_address = {16'h1235, 4'b0000} + bit_index;
        #1;
        if (bit_q !== ((16'h3CC3 >> bit_index) & 1'b1))
            $fatal(1, "MB128 bit %0d mismatched", bit_index);
    end

    // Verify both lanes of the 8/16 backup-RAM mapping.
    write_backup_half(10'h12A, 16'hBEEF);
    byte_address = {10'h12A, 1'b0};
    #1;
    if (byte_q !== 8'hEF) $fatal(1, "backup low byte mismatched");
    byte_address = {10'h12A, 1'b1};
    #1;
    if (byte_q !== 8'hBE) $fatal(1, "backup high byte mismatched");

    @(negedge clk);
    byte_address = {10'h12B, 1'b1};
    byte_data = 8'h7D;
    byte_write = 1'b1;
    @(negedge clk);
    byte_write = 1'b0;
    half_address = 10'h12B;
    @(posedge clk);
    #1;
    if (half_q !== 16'h7D00)
        $fatal(1, "backup byte-to-halfword mapping read %h", half_q);

    $display("PASS: packed Agilex mixed-width RAM mapping");
    $finish;
end

endmodule
