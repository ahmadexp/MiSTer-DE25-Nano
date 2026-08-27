// Host-serviced PCMCIA transaction bridge.
//
// The PC110 guest still programs the Ricoh RB5C396 through its normal ExCA
// registers. pc110_chipset decodes those windows and supplies a card-relative
// address here. A request is held until MiSTer Main completes it through the
// F500h management mailbox. This is deliberately transport-only: the ARS
// firmware and API library remain user-supplied host software.

module pc110_pcmcia_bridge
(
	input  logic        clk,
	input  logic        reset,

	input  logic        io_cs,
	input  logic  [2:0] io_window,
	input  logic [15:0] io_card_address,
	input  logic        io_read,
	input  logic        io_write,
	input  logic  [1:0] io_size,
	input  logic [31:0] io_writedata,
	output logic [31:0] io_readdata,
	output logic        io_wait,

	input  logic        mem_cs,
	input  logic  [2:0] mem_window,
	input  logic [25:0] mem_card_address,
	input  logic        mem_attribute,
	input  logic        mem_read,
	input  logic        mem_write,
	input  logic [31:0] mem_writedata,
	input  logic  [3:0] mem_byteenable,
	input  logic  [3:0] mem_burstcount,
	output logic [31:0] mem_readdata,
	output logic        mem_waitrequest,
	output logic        mem_readdatavalid,
	output logic        mem_active,

	input  logic  [7:0] mgmt_address,
	input  logic        mgmt_read,
	input  logic        mgmt_write,
	input  logic [15:0] mgmt_writedata,
	output logic [15:0] mgmt_readdata,

	output logic        request,
	output logic        backend_online,
	output logic        card_present,
	output logic        card_irq
);

	localparam logic [2:0]
		S_IDLE     = 3'd0,
		S_IO_WAIT  = 3'd1,
		S_IO_DONE  = 3'd2,
		S_MEM_WAIT = 3'd3,
		S_MEM_DONE = 3'd4;

	logic [2:0]  state;
	logic [3:0]  request_sequence;
	logic        request_write;
	logic        request_memory;
	logic        request_attribute;
	logic [1:0]  request_size;
	logic [2:0]  request_window;
	logic [25:0] request_address;
	logic [31:0] request_writedata;
	logic [3:0]  request_byteenable;
	logic [31:0] response_data;
	logic        mem_accepted;
	logic        mem_local_response;
	logic  [3:0] mem_remaining;

	// F500 status layout:
	//  15 IRQ level       14 card present    13 backend online
	//  12:9 sequence      8:6 window         5:4 size (0/1/2 = 8/16/32)
	//   3 attribute       2 memory           1 write       0 pending/ack
	always_comb begin
		case(mgmt_address)
			8'h00: mgmt_readdata = {
				card_irq, card_present, backend_online, request_sequence,
				request_window, request_size, request_attribute,
				request_memory, request_write, request
			};
			8'h01: mgmt_readdata = request_address[15:0];
			8'h02: mgmt_readdata = {6'h00, request_address[25:16]};
			8'h03: mgmt_readdata = request_writedata[15:0];
			8'h04: mgmt_readdata = request_writedata[31:16];
			8'h05: mgmt_readdata = {12'h000, request_byteenable};
			8'h06: mgmt_readdata = 16'h5043; // "PC", mailbox v1
			default: mgmt_readdata = 16'hFFFF;
		endcase
	end

	assign io_wait = (state == S_IO_WAIT) ||
		((state == S_IDLE) && io_cs && (io_read || io_write));
	// Reads are accepted after their request has been latched, then return
	// data asynchronously through readdatavalid. Writes remain stalled until
	// the backend has actually completed them, preserving ordering.
	assign mem_waitrequest =
		((state == S_IDLE) && mem_cs && (mem_read || mem_write)) ||
		((state == S_MEM_WAIT) && (request_write || mem_accepted));
	assign mem_active = (state == S_MEM_WAIT) || (state == S_MEM_DONE) ||
		((state == S_IDLE) && mem_cs && (mem_read || mem_write));

	always_ff @(posedge clk) begin
		mem_readdatavalid <= 1'b0;

		if(reset) begin
			state                 <= S_IDLE;
			request_sequence      <= 4'h0;
			request               <= 1'b0;
			request_write         <= 1'b0;
			request_memory        <= 1'b0;
			request_attribute     <= 1'b0;
			request_size          <= 2'd0;
			request_window        <= 3'd0;
			request_address       <= 26'd0;
			request_writedata     <= 32'd0;
			request_byteenable    <= 4'd0;
			response_data         <= 32'hFFFFFFFF;
			mem_accepted          <= 1'b0;
			mem_local_response    <= 1'b0;
			mem_remaining         <= 4'd1;
			io_readdata           <= 32'hFFFFFFFF;
			mem_readdata          <= 32'hFFFFFFFF;
			backend_online        <= 1'b0;
			card_present          <= 1'b0;
			card_irq              <= 1'b0;
		end
		else begin
			// Main writes the current physical-backend state on every status
			// update. Bit 0 acknowledges the pending transaction after its
			// read result (if any) has been written to F503/F504.
			if(mgmt_write && mgmt_address == 8'h00) begin
				backend_online <= mgmt_writedata[13];
				card_present   <= mgmt_writedata[14];
				card_irq       <= mgmt_writedata[15];
				if(mgmt_writedata[0] && request) begin
					request <= 1'b0;
					if(state == S_IO_WAIT) begin
						io_readdata <= response_data;
						state <= S_IO_DONE;
					end
					else if(state == S_MEM_WAIT) begin
						mem_readdata <= response_data;
						mem_readdatavalid <= ~request_write;
						if(!request_write && mem_remaining > 1) begin
							request <= 1'b1;
							request_sequence <= request_sequence + 1'd1;
							request_address <= request_address + 3'd4;
							mem_remaining <= mem_remaining - 1'd1;
						end
						else begin
							state <= S_MEM_DONE;
						end
					end
				end
			end

			if(mgmt_write && mgmt_address == 8'h03)
				response_data[15:0] <= mgmt_writedata;
			if(mgmt_write && mgmt_address == 8'h04)
				response_data[31:16] <= mgmt_writedata;

			case(state)
				S_IDLE: begin
					if(mem_cs && (mem_read || mem_write)) begin
						request_write      <= mem_write;
						request_memory     <= 1'b1;
						request_attribute  <= mem_attribute;
						request_size       <= 2'd2;
						request_window     <= mem_window;
						request_address    <= mem_card_address;
						request_writedata  <= mem_writedata;
						request_byteenable <= mem_byteenable;
						mem_accepted       <= 1'b0;
						mem_local_response <= !(backend_online && card_present);
						mem_remaining      <= (mem_read && mem_burstcount != 0) ?
						                      mem_burstcount : 4'd1;
						request_sequence   <= request_sequence + 1'd1;
						if(backend_online && card_present) begin
							request <= 1'b1;
						end
						else request <= 1'b0;
						state <= S_MEM_WAIT;
					end
					else if(io_cs && (io_read || io_write)) begin
						request_write      <= io_write;
						request_memory     <= 1'b0;
						request_attribute  <= 1'b0;
						request_size       <= io_size;
						request_window     <= io_window;
						request_address    <= {10'h000, io_card_address};
						request_writedata  <= io_writedata;
						case(io_size)
							2'd0: request_byteenable <= 4'b0001;
							2'd1: request_byteenable <= 4'b0011;
							default: request_byteenable <= 4'b1111;
						endcase
						request_sequence   <= request_sequence + 1'd1;
						if(backend_online && card_present) begin
							request <= 1'b1;
							state <= S_IO_WAIT;
						end
						else begin
							io_readdata <= 32'hFFFFFFFF;
							state <= S_IO_DONE;
						end
					end
				end

				S_IO_DONE:
					if(!(io_read || io_write)) state <= S_IDLE;

				S_MEM_WAIT: begin
					if(request_write && mem_local_response) begin
						mem_local_response <= 1'b0;
						state <= S_MEM_DONE;
					end
					else if(!request_write && !mem_accepted) begin
						// The master sees waitrequest low for this cycle and accepts
						// the already-latched burst command at the next edge.
						mem_accepted <= 1'b1;
					end
					else if(!request_write && mem_local_response) begin
						mem_readdata <= 32'hFFFFFFFF;
						mem_readdatavalid <= 1'b1;
						if(mem_remaining > 1) begin
							request_address <= request_address + 3'd4;
							mem_remaining <= mem_remaining - 1'd1;
						end
						else begin
							mem_local_response <= 1'b0;
							state <= S_MEM_DONE;
						end
					end
				end

				S_MEM_DONE:
					if(!(mem_read || mem_write)) state <= S_IDLE;

				default: ; // I/O wait advances only on a management ack
			endcase
		end
	end

	// mgmt_read is intentionally unused: all mailbox registers are stable
	// throughout a management read and the host bridge supplies the strobe.
	wire _unused = &{1'b0, mgmt_read};

endmodule
