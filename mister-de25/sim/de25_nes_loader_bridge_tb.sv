`timescale 1ns/1ps

module de25_nes_loader_bridge_tb;
	logic src_clk = 1'b0;
	logic dst_clk = 1'b0;
	logic src_reset = 1'b1;
	logic src_write = 1'b0;
	logic [24:0] src_addr = 25'd0;
	logic [7:0] src_data = 8'd0;
	wire src_wait;
	wire [24:0] dst_addr;
	wire [7:0] dst_data;
	logic dst_busy = 1'b0;
	logic [7:0] dst_read_data = 8'd0;
	wire dst_write;
	wire dst_read;
	wire request_seen;
	wire accept_seen;
	wire complete_seen;
	wire verify_error;

	logic controller_ready = 1'b0;
	logic old_write = 1'b0;
	logic old_read = 1'b0;
	logic [7:0] stored_data = 8'd0;
	integer busy_count = 0;
	integer accepted_count = 0;
	integer read_count = 0;
	logic [24:0] accepted_addr [0:3];
	logic [7:0] accepted_data [0:3];

	always #23.28 src_clk = ~src_clk;
	initial begin
		#3.7;
		forever #5.82 dst_clk = ~dst_clk;
	end

	de25_nes_loader_bridge dut (
		.src_clk(src_clk),
		.src_reset(src_reset),
		.src_write(src_write),
		.src_addr(src_addr),
		.src_data(src_data),
		.src_wait(src_wait),
		.dst_addr(dst_addr),
		.dst_data(dst_data),
		.dst_clk(dst_clk),
		.dst_busy(dst_busy),
		.dst_read_data(dst_read_data),
		.dst_write(dst_write),
		.dst_read(dst_read),
		.src_request_seen(request_seen),
		.src_accept_seen(accept_seen),
		.src_complete_seen(complete_seen),
		.src_verify_error(verify_error)
	);

	// Model the controller's level-sensitive request and busy response.  The
	// first request is deliberately issued before controller_ready.
	always @(posedge dst_clk) begin
		if(!dst_write)
			old_write <= 1'b0;
		if(!dst_read)
			old_read <= 1'b0;

		if(dst_busy) begin
			if(busy_count == 0)
				dst_busy <= 1'b0;
			else
				busy_count <= busy_count - 1;
		end
		else if(controller_ready && dst_write && !old_write) begin
			if(accepted_count >= 4)
				$fatal(1, "unexpected extra loader write");
			accepted_addr[accepted_count] <= dst_addr;
			accepted_data[accepted_count] <= dst_data;
			accepted_count <= accepted_count + 1;
			stored_data <= dst_data;
			old_write <= 1'b1;
			dst_busy <= 1'b1;
			busy_count <= 5;
		end
		else if(controller_ready && dst_read && !old_read) begin
			dst_read_data <= stored_data;
			read_count <= read_count + 1;
			old_read <= 1'b1;
			dst_busy <= 1'b1;
			busy_count <= 5;
		end
	end

	task automatic send_byte(input [24:0] addr, input [7:0] data);
		integer timeout;
		begin
			timeout = 0;
			while(src_wait && timeout < 100) begin
				@(posedge src_clk);
				timeout = timeout + 1;
			end
			if(timeout == 100)
				$fatal(1, "bridge never became ready");
			@(negedge src_clk);
			src_addr <= addr;
			src_data <= data;
			src_write <= 1'b1;
			@(negedge src_clk);
			src_write <= 1'b0;

			timeout = 0;
			while(!src_wait && timeout < 20) begin
				@(posedge src_clk);
				timeout = timeout + 1;
			end
			while(src_wait && timeout < 100) begin
				@(posedge src_clk);
				timeout = timeout + 1;
			end
			if(timeout == 100)
				$fatal(1, "loader write did not complete");
		end
	endtask

	initial begin
		integer i;
		repeat(3) @(posedge src_clk);
		src_reset <= 1'b0;

		fork
			begin
				repeat(35) @(posedge dst_clk);
				controller_ready <= 1'b1;
			end
			send_byte(25'h0000123, 8'h11);
		join
		send_byte(25'h0004567, 8'h22);
		send_byte(25'h1abcdef, 8'h33);

		repeat(10) @(posedge src_clk);
		if(accepted_count != 3)
			$fatal(1, "accepted %0d writes instead of 3", accepted_count);
		if(read_count != 3)
			$fatal(1, "completed %0d verification reads instead of 3", read_count);
		if(!request_seen || !accept_seen || !complete_seen)
			$fatal(1, "diagnostic handshake flags incomplete: %b%b%b",
			       request_seen, accept_seen, complete_seen);
		if(accepted_addr[0] != 25'h0000123 || accepted_data[0] != 8'h11 ||
		   accepted_addr[1] != 25'h0004567 || accepted_data[1] != 8'h22 ||
		   accepted_addr[2] != 25'h1abcdef || accepted_data[2] != 8'h33)
			$fatal(1, "loader address/data sequence was corrupted");
		if(verify_error)
			$fatal(1, "matching readback raised the verification error");

		$display("PASS: NES loader holds and verifies every SDRAM byte");
		$finish;
	end
endmodule
