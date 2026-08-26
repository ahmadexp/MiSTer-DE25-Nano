`timescale 1ns/1ps

module jaguar_sdram_pipeline_tb;

localparam real CONTROLLER_HALF_PERIOD = 4.705882;
localparam real CONTROLLER_PERIOD = 9.411764;

logic clk = 1'b1;
logic clk_physical = 1'b0;
logic clk_capture = 1'b0;
logic init = 1'b1;

logic [15:0] sdram_dq_in = 16'h0000;
wire  [15:0] sdram_dq_out;
wire         sdram_dq_oe;
wire [12:0] sdram_a;
wire [1:0]  sdram_ba;
wire        sdram_dqml;
wire        sdram_dqmh;
wire        sdram_ncs;
wire        sdram_nwe;
wire        sdram_nras;
wire        sdram_ncas;
wire        sdram_cke;
wire        sdram_clk;

logic [10:3] ch1_addr = '0;
logic [12:0] ch1_caddr = '0;
wire  [63:0] ch1_dout;
logic [63:0] ch1_din = '0;
logic        ch1_reqr = 1'b0;
logic        ch1_reqw = 1'b0;
logic        ch1_ref = 1'b0;
logic        ch1_act = 1'b0;
logic        ch1_pch = 1'b0;
logic        ch1_rnw = 1'b1;
logic [7:0]  ch1_be = 8'hff;
wire         ch1_ready;
logic        ch1_64 = 1'b1;

logic [23:1] ch2_addr = '0;
logic        ch2_addr_ext = 1'b0;
wire  [31:0] ch2_dout;
logic [15:0] ch2_din = '0;
logic        ch2_req = 1'b0;
logic        ch2_rnw = 1'b1;
logic [1:0]  ch2_be = 2'b11;
wire         ch2_ready;

logic [23:0] ch3_addr = '0;
wire  [31:0] ch3_dout;
logic [31:0] ch3_din = '0;
logic        ch3_req = 1'b0;
logic        ch3_rnw = 1'b1;
wire         ch3_ready;
wire         ram64;

sdram dut (
	.init(init),
	.clk(clk),
	.clk_physical(clk_physical),
	.clk_capture(clk_capture),
	.SDRAM_DQ_IN(sdram_dq_in),
	.SDRAM_DQ_OUT(sdram_dq_out),
	.SDRAM_DQ_OE(sdram_dq_oe),
	.SDRAM_A(sdram_a),
	.SDRAM_DQML(sdram_dqml),
	.SDRAM_DQMH(sdram_dqmh),
	.SDRAM_BA(sdram_ba),
	.SDRAM_nCS(sdram_ncs),
	.SDRAM_nWE(sdram_nwe),
	.SDRAM_nRAS(sdram_nras),
	.SDRAM_nCAS(sdram_ncas),
	.SDRAM_CKE(sdram_cke),
	.SDRAM_CLK(sdram_clk),
	.ch1_addr(ch1_addr),
	.ch1_caddr(ch1_caddr),
	.ch1_dout(ch1_dout),
	.ch1_din(ch1_din),
	.ch1_reqr(ch1_reqr),
	.ch1_reqw(ch1_reqw),
	.ch1_ref(ch1_ref),
	.ch1_act(ch1_act),
	.ch1_pch(ch1_pch),
	.ch1_rnw(ch1_rnw),
	.ch1_be(ch1_be),
	.ch1_ready(ch1_ready),
	.ch1_64(ch1_64),
	.ch2_addr(ch2_addr),
	.ch2_addr_ext(ch2_addr_ext),
	.ch2_dout(ch2_dout),
	.ch2_din(ch2_din),
	.ch2_req(ch2_req),
	.ch2_rnw(ch2_rnw),
	.ch2_be(ch2_be),
	.ch2_ready(ch2_ready),
	.ch3_addr(ch3_addr),
	.ch3_dout(ch3_dout),
	.ch3_din(ch3_din),
	.ch3_req(ch3_req),
	.ch3_rnw(ch3_rnw),
	.ch3_ready(ch3_ready),
	.ram64(ram64),
	.self_refresh(1'b0)
);

always #(CONTROLLER_HALF_PERIOD) clk = ~clk;

initial begin
	#5.5;
	clk_physical = 1'b1;
	forever #(CONTROLLER_HALF_PERIOD) clk_physical = ~clk_physical;
end

initial begin
	#7.5;
	clk_capture = 1'b1;
	forever #(CONTROLLER_HALF_PERIOD) clk_capture = ~clk_capture;
end

integer read_count = 0;

task automatic drive_read_burst(input integer request_number);
	logic [15:0] first_word;
	begin
		first_word = request_number == 1 ? 16'h0000 : 16'h1111;
		#(2.0 * CONTROLLER_PERIOD + 5.5);
		sdram_dq_in = first_word;
		#CONTROLLER_PERIOD sdram_dq_in = first_word + 16'h1111;
		#CONTROLLER_PERIOD sdram_dq_in = first_word + 16'h2222;
		#CONTROLLER_PERIOD sdram_dq_in = first_word + 16'h3333;
	end
endtask

always @(posedge sdram_clk) begin
	if (!sdram_ncs && sdram_nras && !sdram_ncas && sdram_nwe) begin
		read_count <= read_count + 1;
		fork
			drive_read_burst(read_count + 1);
		join_none
	end
end

initial begin
	repeat (4) @(posedge clk);
	init <= 1'b0;

	wait (ch1_ready === 1'b1);
	@(posedge clk);
	ch1_reqr <= 1'b1;
	@(posedge clk);
	ch1_reqr <= 1'b0;

	wait (ch1_dout === 64'h3333_4444_1111_2222);
	#1;
	if (ch1_dout !== 64'h3333_4444_1111_2222) begin
		$error("Jaguar SDRAM burst misaligned: got %016h", ch1_dout);
		$fatal(1);
	end

	$display("PASS: Jaguar SDRAM C4-to-C0 pipeline preserves burst order");
	$finish;
end

initial begin
	#500000;
	$fatal(1, "Jaguar SDRAM pipeline test timed out: refresh=%0d reads=%0d ready=%b data=%016h",
		dut.refresh_count, read_count, ch1_ready, ch1_dout);
end

endmodule
