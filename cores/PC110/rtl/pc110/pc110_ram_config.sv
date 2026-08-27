module pc110_ram_config
(
	input  logic  [1:0] ram_option,
	output logic [29:0] word_limit,
	output logic [15:0] extmem_kb,
	output logic [15:0] above16_64k,
	output logic [15:0] checksum_sum
);
	always_comb begin
		above16_64k = 16'h0000;
		case(ram_option)
			2'd1: begin // no expansion module: 4 MiB total
				word_limit = 30'h00100000;
				extmem_kb = 16'h0C00;
				checksum_sum = 16'h000C;
			end
			2'd2: begin // 4 MiB expansion module: 8 MiB total
				word_limit = 30'h00200000;
				extmem_kb = 16'h1C00;
				checksum_sum = 16'h001C;
			end
			2'd3: begin // 8 MiB expansion module: 12 MiB total
				word_limit = 30'h00300000;
				extmem_kb = 16'h2C00;
				checksum_sum = 16'h002C;
			end
			default: begin // 16 MiB expansion module: 20 MiB total
				word_limit = 30'h00500000;
				extmem_kb = 16'h4C00;
				above16_64k = 16'h0040;
				checksum_sum = 16'h004C;
			end
		endcase
	end
endmodule
