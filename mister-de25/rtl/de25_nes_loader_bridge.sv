`timescale 1ns/1ps

// Verified bridge for the NES byte loader. The source holds address and data
// until SDRAM accepts the write, reads the byte back, and completes the
// transaction. A failed comparison is retried before it becomes a sticky
// diagnostic error.
module de25_nes_loader_bridge
(
	input              src_clk,
	input              src_reset,
	input              src_write,
	input       [24:0] src_addr,
	input        [7:0] src_data,
	output             src_wait,
	output reg  [24:0] dst_addr = 25'd0,
	output reg   [7:0] dst_data = 8'd0,

	input              dst_clk,
	input              dst_busy,
	input        [7:0] dst_read_data,
	output             dst_write,
	output             dst_read,

	output             src_request_seen,
	output             src_accept_seen,
	output             src_complete_seen,
	output             src_verify_error
);

reg src_pending = 1'b0;
reg request_seen = 1'b0;
reg accept_seen = 1'b0;
reg complete_seen = 1'b0;
reg verify_error_seen = 1'b0;

(* ASYNC_REG = "TRUE" *) reg [1:0] done_sync = 2'b00;
(* ASYNC_REG = "TRUE" *) reg [1:0] accepted_sync = 2'b00;
(* ASYNC_REG = "TRUE" *) reg [1:0] verify_error_sync = 2'b00;

(* ASYNC_REG = "TRUE" *) reg [1:0] request_sync = 2'b00;
reg dst_accepted = 1'b0;
reg dst_done = 1'b0;
reg dst_verify_error = 1'b0;
reg dst_write_reg = 1'b0;
reg dst_read_reg = 1'b0;
reg [1:0] retry_count = 2'd0;
reg [2:0] dst_state = 3'd0;

localparam DST_IDLE       = 3'd0;
localparam DST_WRITE_BUSY = 3'd1;
localparam DST_WRITE_DONE = 3'd2;
localparam DST_WRITE_DROP = 3'd3;
localparam DST_READ_BUSY  = 3'd4;
localparam DST_READ_DONE  = 3'd5;
localparam DST_READ_DROP  = 3'd6;
localparam DST_RELEASE    = 3'd7;

assign src_wait = src_pending | done_sync[1];
assign dst_write = dst_write_reg;
assign dst_read = dst_read_reg;
assign src_request_seen = request_seen;
assign src_accept_seen = accept_seen;
assign src_complete_seen = complete_seen;
assign src_verify_error = verify_error_seen;

always @(posedge src_clk) begin
	done_sync <= {done_sync[0], dst_done};
	accepted_sync <= {accepted_sync[0], dst_accepted};
	verify_error_sync <= {verify_error_sync[0], dst_verify_error};

	if(accepted_sync[1])
		accept_seen <= 1'b1;
	if(done_sync[1])
		complete_seen <= 1'b1;
	if(verify_error_sync[1])
		verify_error_seen <= 1'b1;

	if(src_reset) begin
		src_pending <= 1'b0;
	end
	else begin
		if(src_pending) begin
			if(done_sync[1])
				src_pending <= 1'b0;
		end
		else if(!done_sync[1] && src_write) begin
			dst_addr <= src_addr;
			dst_data <= src_data;
			src_pending <= 1'b1;
			request_seen <= 1'b1;
		end
	end
end

always @(posedge dst_clk) begin
	request_sync <= {request_sync[0], src_pending};

	case(dst_state)
		DST_IDLE: begin
			dst_accepted <= 1'b0;
			dst_done <= 1'b0;
			dst_write_reg <= 1'b0;
			dst_read_reg <= 1'b0;
			retry_count <= 2'd0;
			if(request_sync[1]) begin
				dst_write_reg <= 1'b1;
				dst_state <= DST_WRITE_BUSY;
			end
		end
		DST_WRITE_BUSY: begin
			if(dst_busy) begin
				dst_accepted <= 1'b1;
				dst_state <= DST_WRITE_DONE;
			end
		end
		DST_WRITE_DONE: begin
			if(!dst_busy) begin
				dst_write_reg <= 1'b0;
				dst_state <= DST_WRITE_DROP;
			end
		end
		DST_WRITE_DROP: begin
			dst_read_reg <= 1'b1;
			dst_state <= DST_READ_BUSY;
		end
		DST_READ_BUSY: begin
			if(dst_busy)
				dst_state <= DST_READ_DONE;
		end
		DST_READ_DONE: begin
			if(!dst_busy) begin
				dst_read_reg <= 1'b0;
				if(dst_read_data == dst_data) begin
					dst_done <= 1'b1;
					dst_state <= DST_RELEASE;
				end
				else if(retry_count != 2'd3) begin
					retry_count <= retry_count + 1'b1;
					dst_state <= DST_READ_DROP;
				end
				else begin
					dst_verify_error <= 1'b1;
					dst_done <= 1'b1;
					dst_state <= DST_RELEASE;
				end
			end
		end
		DST_READ_DROP: begin
			dst_write_reg <= 1'b1;
			dst_state <= DST_WRITE_BUSY;
		end
		DST_RELEASE: begin
			if(!request_sync[1])
				dst_state <= DST_IDLE;
		end
		default: dst_state <= DST_IDLE;
	endcase

	if(!request_sync[1] && dst_state != DST_RELEASE &&
	   dst_state != DST_IDLE) begin
		dst_write_reg <= 1'b0;
		dst_read_reg <= 1'b0;
		dst_state <= DST_IDLE;
	end
end

endmodule
