`timescale 1ns/1ps

module de25_iopll_avmm_tb;
    logic clk = 0;
    logic reset = 1;
    logic start = 0;
    logic write_request = 0;
    logic [8:0] address = 0;
    logic [31:0] writedata = 0;
    logic [31:0] readdata;
    logic busy;
    logic done;
    logic [8:0] core_avl_address;
    logic core_avl_read;
    logic [7:0] core_avl_readdata = 0;
    logic core_avl_write;
    logic [7:0] core_avl_writedata;

    always #5 clk = ~clk;

    de25_iopll_avmm dut (.*);

    task automatic fail(input string message);
        $fatal(1, "FAIL: %s", message);
    endtask

    task automatic begin_request(
        input logic request_is_write,
        input logic [8:0] request_address,
        input logic [31:0] request_data
    );
        @(negedge clk);
        write_request = request_is_write;
        address = request_address;
        writedata = request_data;
        start = 1;
        @(negedge clk);
        start = 0;
    endtask

    integer transfer_cycle;
    logic [7:0] expected_write [0:9];

    initial begin
        expected_write[0] = 8'h00;
        expected_write[1] = 8'h00;
        expected_write[2] = 8'h00;
        expected_write[3] = 8'h00;
        expected_write[4] = 8'h00;
        expected_write[5] = 8'hD4;
        expected_write[6] = 8'hC3;
        expected_write[7] = 8'hB2;
        expected_write[8] = 8'hA1;
        expected_write[9] = 8'hA1;

        repeat (3) @(posedge clk);
        reset <= 0;

        begin_request(1'b1, 9'h05C, 32'hA1B2C3D4);
        transfer_cycle = 0;
        while (busy) begin
            if (transfer_cycle < 10) begin
                if (!core_avl_write || core_avl_read)
                    fail("write must remain asserted for ten cycles");
                if (core_avl_address != 9'h05C)
                    fail("write address was not held");
                if (core_avl_writedata != expected_write[transfer_cycle])
                    fail("write byte or preamble did not match protocol");
            end else begin
                if (core_avl_write || core_avl_read)
                    fail("bus must idle for five trailing cycles");
            end
            transfer_cycle = transfer_cycle + 1;
            @(negedge clk);
        end
        if (transfer_cycle != 15 || !done)
            fail("write transaction length or completion pulse");

        begin_request(1'b0, 9'h040, 32'd0);
        transfer_cycle = 0;
        while (busy) begin
            if (transfer_cycle < 10) begin
                if (!core_avl_read || core_avl_write)
                    fail("read must remain asserted for ten cycles");
                if (core_avl_address != 9'h040)
                    fail("read address was not held");
            end else if (core_avl_write || core_avl_read) begin
                fail("bus must idle after read transfer");
            end

            // Values are installed before the next active edge, where the
            // adapter captures cycles 6 through 9.
            case (transfer_cycle)
                6: core_avl_readdata = 8'h78;
                7: core_avl_readdata = 8'h56;
                8: core_avl_readdata = 8'h34;
                9: core_avl_readdata = 8'h12;
                default: core_avl_readdata = 8'h00;
            endcase
            transfer_cycle = transfer_cycle + 1;
            @(negedge clk);
        end
        if (transfer_cycle != 15 || !done)
            fail("read transaction length or completion pulse");
        if (readdata != 32'h12345678)
            fail("read bytes were not assembled least-significant first");

        $display("PASS: Agilex 5 IOPLL Avalon register transport");
        $finish;
    end
endmodule
