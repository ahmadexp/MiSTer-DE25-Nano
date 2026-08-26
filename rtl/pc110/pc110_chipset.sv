// IBM Palm Top PC 110 board-specific I/O.
//
// This module models state outside the shared PC/AT-compatible devices.
// Defaults come from the read-only 2026 hardware captures in
// Open-Source-PC110/Discovery/Chipset and Discovery/Pluto.  The EC/ED bank is
// the VL82C420 shadow/cache bank, not the power MCU mailbox used by older
// PC110-EMU revisions.

module pc110_chipset
#(
	// The byte-pair UART trace is useful during hardware bring-up, but its
	// 512-entry FIFO is not part of the PC110 model. Keep it out of release
	// builds unless explicitly enabled by a developer.
	parameter POSTLOG_ENABLE = 1'b0
)
(
	input  logic        clk,
	input  logic        reset,

	input  logic [15:0] io_address,
	input  logic        io_read,
	input  logic        io_write,
	input  logic  [7:0] io_writedata,
	output logic  [7:0] io_readdata,
	output logic        io_cs,

	// Decoded socket-A windows. The host-serviced bridge consumes card-
	// relative addresses while the guest continues to program normal ExCA
	// system windows.
	input  logic        pcmcia_present,
	input  logic        pcmcia_backend_irq,
	output logic        pcmcia_irq_10,
	output logic        pcmcia_io_cs,
	output logic  [2:0] pcmcia_io_window,
	output logic [15:0] pcmcia_io_card_address,
	input  logic [31:0] pcmcia_mem_address,
	output logic        pcmcia_mem_cs,
	output logic  [2:0] pcmcia_mem_window,
	output logic [25:0] pcmcia_mem_card_address,
	output logic        pcmcia_mem_attribute,

	// One bit per 16 KiB block, C0000 first and FFFFF last.  In each
	// VL82C420 AXS two-bit field, bit 0 controls writes to shadow RAM and
	// bit 1 selects shadow RAM for reads.
	output logic [15:0] shadow_write_enable,
	output logic [15:0] shadow_read_enable,
	output logic  [7:0] romset,

	output logic  [6:0] font_bank_select,
	output logic  [7:0] font_window_segment,
	output logic        font_window_enable,

	// VL82C420 EC/ED RAMCFG0 (index 02h).  POST's DRAM bank sizer writes
	// candidate row-configuration codes here and expects the array's
	// aliasing behavior to follow; 0Bh is the settled planar value
	// captured from live hardware.
	output logic  [7:0] dram_cfg0,

	// Optional POST diagnostic UART. Idle high when POSTLOG_ENABLE is off.
	output logic        postlog_tx,

	// value returned on the shared I/O read bus, for the ATA trace
	input  logic  [7:0] io_snoop,

	// EBDA POST-error-log write snoop from the L2 cache: pulses with a
	// preformed {tag, byte} pair ('J' = error count written, 'j' = first
	// logged code word's low byte) so the exact instant an error is
	// logged appears in the serial trace.
	input  logic        errlog_wr,
	input  logic  [7:0] errlog_tag,
	input  logic  [7:0] errlog_byte,

	// asserted while POST is inside its EARLY keyboard test (checkpoint
	// 56h on port 190h); the 8042 reports the keyboard inhibited (status
	// bit4 = 0) during this window so the test - whose pass path needs an
	// SMM service the current CPU cannot provide - is skipped. See the checkpoint
	// tracker below.
	output logic        kbd_hide,

	// asserted once POST reaches the boot phase (checkpoint 6Eh onward):
	// gates the CMOS-7Bh setup-request acknowledge so only the INT19
	// boot-decision read consumes the request.
	output logic        ckpt_boot,

	// asserted while the BIOS's Easy-Setup loader stub (F000:DDE6,
	// relocated to 3000:0000) holds the flash window open: it zeroes the
	// E/F-segment shadow read-enables (eced 11h/12h) AND toggles planar
	// control (port 98h) bit2, then block-copies E0000h-FFFFFh expecting
	// the LOWER 128 KiB of flash (the Easy-Setup module) there.  The L2
	// aliases those reads to the module's DDR copy while this is high.
	// planar_control bit2 is the disambiguator: POST also zeroes eced
	// 11h/12h transiently during shadow configuration, but never with
	// bit2 set.
	output logic        easysetup_remap
);

	// clk_sys is 30 MHz; 30e6 / 115200 = 260.42
	localparam int unsigned POSTLOG_DIV = 260;

	// These register files are far smaller than an Agilex 5 M20K.  Keeping
	// them in MLABs avoids consuming five whole block-RAM instances in the
	// DE25 PC110 build while preserving their inferred dual-port behavior.
	(* ramstyle = "MLAB" *) logic [7:0] scamp [0:127];
	(* ramstyle = "MLAB" *) logic [7:0] block2[0:255];
	logic [7:0] eced [0:63];
	logic [7:0] pcic [0:255];
	(* ramstyle = "MLAB" *) logic [7:0] ecb [0:31];
	(* ramstyle = "MLAB" *) logic [7:0] pos [0:7];
	(* ramstyle = "MLAB" *) logic [7:0] xr [0:127];
	logic [6:0] xr_index;

	logic [6:0] scamp_index;
	logic [7:0] block2_index;
	logic [5:0] eced_index;
	logic [7:0] pcic_index;
	logic [4:0] ecb_index;
	logic [7:0] font_bank;
	logic [7:0] font_segment;
	logic       font_enable;
	logic [7:0] ink_control;
	logic [7:0] lpt_data;
	logic [4:0] lpt_control;
	logic       lpt_ack_pending;
	logic       lpt_status_read_d;
	logic [7:0] planar_setup;
	logic [7:0] planar_control;
	logic [7:0] cfg22;
	logic [7:0] cfg23;
	logic       scamp_gate;
	logic       block2_gate;
	logic       eced_gate;
	logic [2:0] block2_unlock_step;
	logic       pcmcia_present_d;

	assign font_bank_select = font_bank[6:0];
	assign font_window_segment = font_segment;
	assign font_window_enable = font_enable;
	assign dram_cfg0 = eced[8'h02];
	assign easysetup_remap = (eced[8'h11] == 8'h00) && (eced[8'h12] == 8'h00) &&
	                         planar_control[2];
	assign pcmcia_irq_10 = pcmcia_present && pcmcia_backend_irq &&
	                        (pcic[8'h03][3:0] == 4'hA);

	// Socket A I/O-window decode. ExCA map-enable bits 6 and 7 correspond
	// to I/O windows 0 and 1. The address handed to Main is relative to the
	// card resource, so a host-side base assigned by the ARS enumerator can
	// differ from the port chosen by the PC110 guest.
	always_comb begin
		pcmcia_io_cs = 1'b0;
		pcmcia_io_window = 3'd0;
		pcmcia_io_card_address = 16'h0000;
		if(pcic[8'h06][6] &&
		   io_address >= {pcic[8'h09], pcic[8'h08]} &&
		   io_address <= {pcic[8'h0B], pcic[8'h0A]}) begin
			pcmcia_io_cs = 1'b1;
			pcmcia_io_window = 3'd0;
			pcmcia_io_card_address = io_address - {pcic[8'h09], pcic[8'h08]};
		end
		else if(pcic[8'h06][7] &&
		        io_address >= {pcic[8'h0D], pcic[8'h0C]} &&
		        io_address <= {pcic[8'h0F], pcic[8'h0E]}) begin
			pcmcia_io_cs = 1'b1;
			pcmcia_io_window = 3'd1;
			pcmcia_io_card_address = io_address - {pcic[8'h0D], pcic[8'h0C]};
		end
	end

	// Five 4 KiB-granular ExCA memory windows. The 14-bit card-offset field
	// is a signed page displacement; adding its shifted two's-complement
	// representation yields the card byte address used by the host API.
	integer pcmcia_mw;
	logic [11:0] pcmcia_start_page;
	logic [11:0] pcmcia_stop_page;
	logic  [7:0] pcmcia_mem_reg;
	always_comb begin
		pcmcia_mem_cs = 1'b0;
		pcmcia_mem_window = 3'd0;
		pcmcia_mem_card_address = 26'd0;
		pcmcia_mem_attribute = 1'b0;
		pcmcia_start_page = 12'd0;
		pcmcia_stop_page = 12'd0;
		pcmcia_mem_reg = 8'h10;
		for(pcmcia_mw = 0; pcmcia_mw < 5; pcmcia_mw = pcmcia_mw + 1) begin
			pcmcia_mem_reg = 8'h10 + (pcmcia_mw * 8);
			pcmcia_start_page = {
				pcic[pcmcia_mem_reg + 1'b1][3:0], pcic[pcmcia_mem_reg]
			};
			pcmcia_stop_page = {
				pcic[pcmcia_mem_reg + 3'd3][3:0], pcic[pcmcia_mem_reg + 2'd2]
			};
			if(!pcmcia_mem_cs && (pcmcia_mem_address[31:24] == 8'h00) &&
			   pcic[8'h06][pcmcia_mw] &&
			   pcmcia_mem_address[23:12] >= pcmcia_start_page &&
			   pcmcia_mem_address[23:12] <= pcmcia_stop_page) begin
				pcmcia_mem_cs = 1'b1;
				pcmcia_mem_window = pcmcia_mw[2:0];
				pcmcia_mem_card_address = {2'b00, pcmcia_mem_address[23:0]} +
					{pcic[pcmcia_mem_reg + 3'd5][5:0],
					 pcic[pcmcia_mem_reg + 3'd4], 12'h000};
				pcmcia_mem_attribute = pcic[pcmcia_mem_reg + 3'd5][6];
			end
		end
	end

	integer i;
	initial begin
		for(i = 0; i < 128; i = i + 1) scamp[i] = 8'h00;
		for(i = 0; i < 256; i = i + 1) block2[i] = 8'hFF;
		for(i = 0; i < 64;  i = i + 1) eced[i] = 8'h00;
		for(i = 0; i < 256; i = i + 1) pcic[i] = 8'h00;
		for(i = 0; i < 32;  i = i + 1) ecb[i] = 8'hFF;
		for(i = 0; i < 8;   i = i + 1) pos[i] = 8'h00;

		// VL82C420 runtime view, captured through 74h/76h.
		scamp[8'h00] = 8'h00; scamp[8'h01] = 8'hBB;
		scamp[8'h02] = 8'h80; scamp[8'h03] = 8'h00;
		for(i = 4; i < 13; i = i + 1) scamp[i] = 8'hFF;
		scamp[8'h0D] = 8'h6F; scamp[8'h0E] = 8'h7E;
		scamp[8'h0F] = 8'h50; scamp[8'h10] = 8'h80;
		scamp[8'h13] = 8'h90; scamp[8'h14] = 8'hF0;
		scamp[8'h15] = 8'hE4; scamp[8'h16] = 8'hA1;
		scamp[8'h20] = 8'h8E; scamp[8'h21] = 8'h02;
		scamp[8'h2E] = 8'h98; scamp[8'h2F] = 8'h8A;
		scamp[8'h30] = 8'h10; scamp[8'h31] = 8'h14;
		scamp[8'h32] = 8'h10; scamp[8'h33] = 8'h20;
		scamp[8'h34] = 8'h08; scamp[8'h35] = 8'hBA;
		scamp[8'h36] = 8'h9E; scamp[8'h37] = 8'hF1;
		scamp[8'h38] = 8'h5A; scamp[8'h39] = 8'h50;
		scamp[8'h3A] = 8'hF1; scamp[8'h3B] = 8'h3C;
		scamp[8'h3C] = 8'h0A; scamp[8'h3D] = 8'h1E;
		scamp[8'h3E] = 8'h2C; scamp[8'h3F] = 8'h01;
		scamp[8'h40] = 8'h02; scamp[8'h41] = 8'h05;
		scamp[8'h42] = 8'h01; scamp[8'h43] = 8'h88;
		scamp[8'h44] = 8'h03;
		scamp[8'h49] = 8'h0A; scamp[8'h4A] = 8'h03;
		scamp[8'h4B] = 8'h88; scamp[8'h4C] = 8'h05;
		scamp[8'h50] = 8'h08; scamp[8'h51] = 8'h1E;
		scamp[8'h52] = 8'h11; scamp[8'h53] = 8'h88;
		scamp[8'h54] = 8'h11;
		scamp[8'h58] = 8'h0C; scamp[8'h5B] = 8'h88;
		scamp[8'h76] = 8'h10; scamp[8'h77] = 8'h4F;
		scamp[8'h78] = 8'h0F; scamp[8'h79] = 8'h10;
		scamp[8'h7A] = 8'h53; scamp[8'h7B] = 8'h4C;
		scamp[8'h7D] = 8'h10; scamp[8'h7E] = 8'h15;
		scamp[8'h7F] = 8'hEE;

		// VL82C420 POST/programming view, captured through 24h/25h.
		for(i = 0; i < 8; i = i + 1) block2[i] = 8'hAA;
		block2[8'h08] = 8'h40; block2[8'h09] = 8'h41;
		block2[8'h0A] = 8'h42; block2[8'h0B] = 8'h43;
		block2[8'h0E] = 8'h00; block2[8'h0F] = 8'h0F;
		for(i = 8'h10; i <= 8'h15; i = i + 1) block2[i] = 8'h00;
		block2[8'h22] = 8'h11; block2[8'h23] = 8'h08;
		block2[8'h24] = 8'h04; block2[8'h25] = 8'h01;
		block2[8'h26] = 8'h00; block2[8'h27] = 8'h20;
		block2[8'h28] = 8'h0B; block2[8'h29] = 8'h0C;
		block2[8'h2A] = 8'h00; block2[8'h2B] = 8'h08;
		block2[8'h2E] = 8'h80;
		block2[8'h40] = 8'h00; block2[8'h41] = 8'h00;
		block2[8'h42] = 8'h12; block2[8'h43] = 8'h00;
		block2[8'h44] = 8'h50; block2[8'h45] = 8'h05;
		block2[8'h4E] = 8'h00;
		block2[8'h60] = 8'h00; block2[8'h61] = 8'h01;
		block2[8'h62] = 8'h00; block2[8'h65] = 8'h00;
		block2[8'h66] = 8'h00; block2[8'h70] = 8'h02;
		block2[8'h84] = 8'hEE; block2[8'h85] = 8'h15;
		for(i = 8'h90; i <= 8'h97; i = i + 1) block2[i] = 8'hAA;
		block2[8'h98] = 8'hC0; block2[8'h99] = 8'h41;
		block2[8'h9A] = 8'h42; block2[8'h9B] = 8'h43;
		block2[8'h9C] = 8'hAA; block2[8'h9D] = 8'hAA;
		block2[8'h9E] = 8'h00; block2[8'h9F] = 8'h0E;
		block2[8'hA2] = 8'h11; block2[8'hA3] = 8'h70;
		block2[8'hA4] = 8'h02; block2[8'hA5] = 8'h01;
		block2[8'hA6] = 8'h00; block2[8'hA7] = 8'h20;
		block2[8'hA8] = 8'h0B;
		block2[8'hB0] = 8'hBA; block2[8'hB1] = 8'h9E;
		block2[8'hB2] = 8'hF0; block2[8'hB3] = 8'h5A;
		block2[8'hB4] = 8'h50; block2[8'hB5] = 8'hF5;
		block2[8'hB6] = 8'hDA; block2[8'hB7] = 8'h00;
		block2[8'hB8] = 8'h00; block2[8'hB9] = 8'h40;
		block2[8'hBA] = 8'h00; block2[8'hBB] = 8'h00;
		block2[8'hBC] = 8'h02; block2[8'hBE] = 8'h10;
		block2[8'hBF] = 8'h14;
		block2[8'hC0] = 8'h00; block2[8'hC1] = 8'h00;
		block2[8'hC2] = 8'h00; block2[8'hC8] = 8'hF2;
		block2[8'hC9] = 8'h03; block2[8'hCA] = 8'hA1;
		block2[8'hCB] = 8'h02;
		block2[8'hD0] = 8'h60; block2[8'hD1] = 8'h00;
		block2[8'hD2] = 8'h24; block2[8'hD3] = 8'h00;
		block2[8'hD8] = 8'h00; block2[8'hD9] = 8'h00;
		block2[8'hDA] = 8'h20; block2[8'hDB] = 8'h00;
		block2[8'hE0] = 8'h00; block2[8'hE1] = 8'h00;
		block2[8'hE2] = 8'h00; block2[8'hE8] = 8'hF4;
		block2[8'hE9] = 8'h03; block2[8'hEA] = 8'hA1;
		block2[8'hEB] = 8'h02;
		block2[8'hF0] = 8'h80; block2[8'hF1] = 8'h00;
		block2[8'hF2] = 8'h00; block2[8'hF3] = 8'h00;
		block2[8'hF4] = 8'h10; block2[8'hF5] = 8'h20;
		block2[8'hF6] = 8'h08; block2[8'hF7] = 8'h07;
		block2[8'hF8] = 8'h0E; block2[8'hFB] = 8'h18;
		block2[8'hFC] = 8'hE0; block2[8'hFE] = 8'h3F;
		block2[8'hFF] = 8'h00;

		// VL82C420 shadow/cache/ROM-decode bank, EC/ED.
		eced[8'h00] = 8'h42; eced[8'h01] = 8'hD5;
		eced[8'h02] = 8'h0B; eced[8'h03] = 8'h00;
		eced[8'h04] = 8'h06; eced[8'h05] = 8'hA8;
		eced[8'h06] = 8'h1A; eced[8'h07] = 8'hEC;
		eced[8'h08] = 8'h38; eced[8'h0A] = 8'h03;
		eced[8'h0C] = 8'h29; eced[8'h0F] = 8'h2A;
		eced[8'h12] = 8'hAA; eced[8'h13] = 8'h55;
		eced[8'h14] = 8'h55; eced[8'h15] = 8'h6A;
		eced[8'h16] = 8'h55; eced[8'h17] = 8'h55;
		eced[8'h18] = 8'hAA; eced[8'h19] = 8'h1A;
		eced[8'h1A] = 8'h04; eced[8'h1B] = 8'h08;
		eced[8'h1C] = 8'h74; eced[8'h24] = 8'hFF;
		eced[8'h25] = 8'hFF; eced[8'h26] = 8'hFF;
		eced[8'h27] = 8'hFF; eced[8'h28] = 8'hFF;
		eced[8'h29] = 8'hFF; eced[8'h2A] = 8'hFF;
		eced[8'h2B] = 8'hFF; eced[8'h37] = 8'h10;

		// C&T F65535 extension registers (XR), index/data at 3D6h/3D7h.
		// Live text-mode capture from the running PC110; XR00 = C1h is the
		// chip identity (chipcode Ch = F65535, revision 1) and XR70 = 00h
		// keeps the 3C3/46E8 enable path accessible.
		for(i = 0; i < 128; i = i + 1) xr[i] = 8'h00;
		xr[8'h00] = 8'hC1; xr[8'h01] = 8'hDE;
		xr[8'h02] = 8'h01; xr[8'h03] = 8'h02;
		xr[8'h04] = 8'h81; xr[8'h06] = 8'hC2;
		xr[8'h08] = 8'hF8; xr[8'h0E] = 8'h80;
		xr[8'h0F] = 8'h01; xr[8'h18] = 8'hFF;
		xr[8'h19] = 8'h56; xr[8'h1A] = 8'h13;
		xr[8'h1B] = 8'h5F; xr[8'h1C] = 8'h4F;
		xr[8'h1D] = 8'h7F; xr[8'h1E] = 8'hFF;
		xr[8'h1F] = 8'h02; xr[8'h28] = 8'h80;
		xr[8'h29] = 8'h4C; xr[8'h2B] = 8'h03;
		xr[8'h2C] = 8'h04; xr[8'h2D] = 8'h50;
		xr[8'h2E] = 8'h50; xr[8'h30] = 8'h05;
		xr[8'h31] = 8'h14; xr[8'h32] = 8'h13;
		xr[8'h33] = 8'h40; xr[8'h51] = 8'hC4;
		xr[8'h52] = 8'h42; xr[8'h54] = 8'hC0;
		xr[8'h55] = 8'hE5; xr[8'h57] = 8'h23;
		xr[8'h60] = 8'h88; xr[8'h61] = 8'h2E;

		// Ricoh RB5C396 / 82365-compatible controller: live post-boot ExCA
		// register image captured from both sockets with no test card.
		pcic[8'h00] = 8'h83; pcic[8'h01] = 8'h3F;
		pcic[8'h1F] = 8'h80; pcic[8'h2F] = 8'h08;
		pcic[8'h3A] = 8'hB2;
		pcic[8'h40] = 8'h83; pcic[8'h41] = 8'h33;
		pcic[8'h5F] = 8'h80; pcic[8'h6F] = 8'h08;
		pcic[8'h7A] = 8'hB2;

		// EC-B live defaults.  Index is masked to five bits.
		ecb[8'h00] = 8'h00; ecb[8'h02] = 8'hF5;
		ecb[8'h04] = 8'h84; ecb[8'h05] = 8'hF3;
		ecb[8'h06] = 8'h6C; ecb[8'h07] = 8'hFD;
		ecb[8'h09] = 8'hF7; ecb[8'h0B] = 8'hFC;
		ecb[8'h13] = 8'hE8; ecb[8'h14] = 8'h35;
		ecb[8'h15] = 8'h04;

		// POS register 2 bit 0 enables the planar VGA.
		pos[2] = 8'h01;
	end

	// ROMSET (EC/ED index 0Ch) value 00h opens the whole upper-memory
	// shadow window for writes; POST wraps its C-segment copy and the
	// video BIOS decompression in ROMSET open/relock.  Any other value
	// defers to the per-16KiB xAXS write bits.
	wire shadow_open_all = (eced[8'h0C] == 8'h00);
	assign romset = eced[8'h0C];

	generate
		genvar g;
		for(g = 0; g < 4; g = g + 1) begin : g_shadow_decode
			assign shadow_write_enable[(g*4)+0] = shadow_open_all | eced[8'h0F+g][0];
			assign shadow_write_enable[(g*4)+1] = shadow_open_all | eced[8'h0F+g][2];
			assign shadow_write_enable[(g*4)+2] = shadow_open_all | eced[8'h0F+g][4];
			assign shadow_write_enable[(g*4)+3] = shadow_open_all | eced[8'h0F+g][6];
			assign shadow_read_enable[(g*4)+0]  = eced[8'h0F+g][1];
			assign shadow_read_enable[(g*4)+1]  = eced[8'h0F+g][3];
			assign shadow_read_enable[(g*4)+2]  = eced[8'h0F+g][5];
			assign shadow_read_enable[(g*4)+3]  = eced[8'h0F+g][7];
		end
	endgenerate

	always_comb begin
		io_cs = 1'b1;
		case(io_address)
			16'h0022, 16'h0023: io_readdata = (io_address[0] ? cfg23 : cfg22);
			16'h0024: io_readdata = 8'hFF;
			16'h0025: io_readdata = block2_gate ? block2[block2_index] : 8'hFF;
			16'h004F: io_readdata = 8'hFF; // confirmed I/O-delay port
			16'h0074: io_readdata = 8'hFF;
			// Index 0 (and 1) of this bank are readable even while the
			// SCAMP config gate is locked: POST's memory-config check at
			// F000:4347 reads index 0 (bits[1:0] must be clear) and the
			// memory sizer reads index 1 without opening the 22h/23h gate.
			// Returning 0xFF there makes bits[1:0]=1 -> spurious 221 error,
			// which then blocks disk boot.  scamp[0]=00h, scamp[1]=BBh.
			16'h0076: io_readdata = (scamp_gate || scamp_index <= 7'h01) ?
			                        scamp[scamp_index] : 8'hFF;
			16'h0094: io_readdata = planar_setup;
			16'h0098: io_readdata = planar_control;
			16'h00EC: io_readdata = 8'hFF;
			16'h00ED: io_readdata = eced_gate ? eced[eced_index] : 8'hFF;
			16'h00F9, 16'h00FB: io_readdata = 8'hFF;
			16'h0100, 16'h0101, 16'h0102, 16'h0103,
			16'h0104, 16'h0105, 16'h0106, 16'h0107:
				io_readdata = (planar_setup == 8'hDF) ? pos[io_address[2:0]] : 8'hFF;
			16'h03D6: io_readdata = {1'b0, xr_index};
			16'h03D7: io_readdata = xr[xr_index];
			// Input Status 1 (3DAh/3BAh) is NO LONGER shimmed here: the
			// former toggle-bit3/force-bit0 shim satisfied the video BIOS
			// retrace waits during bring-up, but $DISP.SYS's adapter
			// detection sets mode 12h and then spins with interrupts off
			// until (3DA & 09h) == 0 (active display area) - a condition
			// the shim could never produce, leaving the freshly-cleared
			// mode-12h screen solid black. The VGA implementation free-runs and
			// returns genuine {vretrace, display} status (vga.v drives the
			// data when the chipset does not claim the address), which
			// terminates every poll polarity with real frame timing.
			16'h03E0: io_readdata = 8'hFF;
			16'h03E1: begin
				// Software Card Detect (register 16h bit5) is a write-only
				// event source and always reads as zero. Socket A's status
				// follows the 82365 polarity: both CD bits mean inserted,
				// POWERON follows a nonzero VCC selection, and I/O cards use
				// bit 0 for the inactive STSCHG level rather than BVD1/BVD2.
				if(pcic_index == 8'h01)
					io_readdata = (pcic[pcic_index] & 8'hB0) |
					                  (pcic[8'h03][5] ? 8'h01 : 8'h03) |
					                  (pcmcia_present ? 8'h0C : 8'h00) |
					                  ((pcmcia_present && |pcic[8'h02][4:3]) ?
					                   8'h40 : 8'h00);
				else if(pcic_index[5:0] == 6'h16)
					io_readdata = pcic[pcic_index] & 8'hDF;
				else
					io_readdata = pcic[pcic_index];
			end
			// The PC110 BIOS publishes LPT1 at 03BCh in the BDA. Model the
			// SPP data/control latches and an attached, ready virtual sink.
			// INT 17h reports 90h for the ready/selected state expected by
			// Easy-Setup's output test.
			16'h03BC: io_readdata = lpt_data;
			16'h03BD: io_readdata = lpt_ack_pending ? 8'h90 : 8'hD0;
			16'h03BE: io_readdata = {3'b111, lpt_control};
			16'h1160: io_readdata = {1'b0, font_bank[6:0]};
			16'h1161: io_readdata = 8'hFF;
			16'h1162: io_readdata = font_segment;
			16'h1163: io_readdata = {7'h00, font_enable};
			16'h15E0: io_readdata = 8'h00;
			16'h15E1: io_readdata = (ink_control == 8'h38) ? 8'h7F : 8'hFF;
			16'h15E2: io_readdata = ink_control;
			16'h15E3, 16'h15E4, 16'h15E5, 16'h15E6, 16'h15E7:
				io_readdata = 8'hFF;
			16'h15E8: io_readdata = 8'h64;
			16'h15E9, 16'h15EA, 16'h15EB: io_readdata = 8'hFF;
			16'h15EC: io_readdata = 8'h48;
			16'h15ED: io_readdata = 8'hFF;
			16'h15EE: io_readdata = 8'h80;
			16'h15EF: io_readdata = 8'h00;
			16'h35EA: io_readdata = 8'hFF;
			16'h35EB: io_readdata = ecb[ecb_index];
			16'hFC23, 16'hF023, 16'hC023: io_readdata = 8'hFF;
			default: begin
				io_readdata = 8'hFF;
				io_cs = 1'b0;
			end
		endcase
	end

	always_ff @(posedge clk) begin
		if(reset) begin
			scamp_index       <= 7'h00;
			block2_index      <= 8'h00;
			eced_index        <= 6'h00;
			pcic_index        <= 8'h00;
			ecb_index         <= 5'h00;
			font_bank         <= 8'h00;
			font_segment      <= 8'hDE;
			font_enable       <= 1'b1;
			ink_control       <= 8'hC0;
			lpt_data          <= 8'hFF;
			lpt_control       <= 5'h0C;
			lpt_ack_pending   <= 1'b0;
			lpt_status_read_d <= 1'b0;
			planar_setup      <= 8'hFF;
			planar_control    <= 8'h00;
			cfg22             <= 8'h00;
			cfg23             <= 8'h01;
			scamp_gate        <= 1'b0;
			block2_gate       <= 1'b0;
			eced_gate         <= 1'b0;
			block2_unlock_step <= 3'd0;
			pcmcia_present_d  <= 1'b0;
		end
		else begin
			pcmcia_present_d <= pcmcia_present;
			if(pcmcia_present != pcmcia_present_d)
				pcic[8'h04] <= pcic[8'h04] | 8'h08;
			lpt_status_read_d <= io_read && (io_address == 16'h03BD);
			// Hold ACK through the complete bus read. Clearing it on the
			// first clock with io_read high made the CPU sample only D0h.
			if(lpt_status_read_d &&
			   !(io_read && io_address == 16'h03BD))
				lpt_ack_pending <= 1'b0;
			if(io_read) begin
				if(io_address == 16'h03E1 && pcic_index[5:0] == 6'h04)
					pcic[pcic_index] <= 8'h00;
				case(block2_unlock_step)
					3'd0: block2_unlock_step <= (io_address == 16'hFC23) ? 3'd1 : 3'd0;
					3'd1: block2_unlock_step <= (io_address == 16'hF023) ? 3'd2 :
					                            (io_address == 16'hFC23) ? 3'd1 : 3'd0;
					3'd2: block2_unlock_step <= (io_address == 16'hC023) ? 3'd3 : 3'd0;
					3'd3: begin
						block2_unlock_step <= 3'd0;
						if(io_address == 16'h0023) block2_gate <= 1'b1;
					end
					default: block2_unlock_step <= 3'd0;
				endcase
			end

			if(io_write) begin
				case(io_address)
					16'h0022: begin
						cfg22 <= io_writedata;
						if((io_writedata == 8'h80) && (cfg23 == 8'h00))
							scamp_gate <= 1'b1;
					end
					16'h0023: begin
						cfg23 <= io_writedata;
						if(io_writedata[0]) begin
							scamp_gate  <= 1'b0;
							block2_gate <= 1'b0;
						end
					end
					16'h0024: block2_index <= io_writedata;
					16'h0025: if(block2_gate) block2[block2_index] <= io_writedata;
					16'h0074: scamp_index <= io_writedata[6:0];
					16'h0076: if(scamp_gate) scamp[scamp_index] <= io_writedata;
					16'h0094: planar_setup <= io_writedata;
					16'h0098: planar_control <= io_writedata;
					16'h00EC: eced_index <= io_writedata[5:0];
					16'h00ED: if(eced_gate) eced[eced_index] <= io_writedata;
					16'h00FB: eced_gate <= 1'b1;
					16'h00F9: eced_gate <= 1'b0;
					16'h0100, 16'h0101, 16'h0102, 16'h0103,
					16'h0104, 16'h0105, 16'h0106, 16'h0107:
						if(planar_setup == 8'hDF) pos[io_address[2:0]] <= io_writedata;
					16'h03D6: xr_index <= io_writedata[6:0];
					16'h03D7: if(xr_index != 7'h00) xr[xr_index] <= io_writedata;
					// Ricoh extended ExCA registers use index bit 7.
					// Easy-Setup explicitly walks registers 82h-96h.
					16'h03E0: pcic_index <= io_writedata;
					16'h03E1: begin
						if(pcic_index[5:0] == 6'h16) begin
							pcic[pcic_index] <= io_writedata & 8'hDF;
							// Writing Software Card Detect raises the Card
							// Detect Change latch for the selected socket.
							if(io_writedata[5])
								pcic[{pcic_index[6], 6'h04}] <=
									pcic[{pcic_index[6], 6'h04}] | 8'h08;
						end
						else if(pcic_index[5:0] != 6'h00 &&
						        pcic_index[5:0] != 6'h3A)
							pcic[pcic_index] <= io_writedata;
					end
					16'h03BC: lpt_data <= io_writedata;
					16'h03BE: begin
						if(lpt_control[0] && !io_writedata[0])
							lpt_ack_pending <= 1'b1;
						lpt_control <= io_writedata[4:0];
					end
					16'h1160: font_bank <= {1'b0, io_writedata[6:0]};
					16'h1162: font_segment <= io_writedata;
					16'h1163: font_enable <= io_writedata[0];
					16'h15E2: ink_control <= io_writedata;
					16'h35EA: ecb_index <= io_writedata[4:0];
					16'h35EB: ecb[ecb_index] <= io_writedata;
					default: ;
				endcase
			end
		end
	end

	// POST checkpoint tracking (port 190h).  The BIOS's EARLY keyboard test
	// runs exactly between checkpoint 56h (F000:4FEC) and 5Ah (F000:4FF4).
	// Its 6477h entry gate skips the whole test when 8042 status bit4 reads
	// 0 (keyboard inhibited).  We assert kbd_hide during that window so the
	// early test is skipped: its pass path ends in a stuck-key check that
	// consults the system MCU through an SMI API (AX=5380h) - the result
	// comes back in CPU registers rewritten by SMM, which this CPU does not
	// implement, so the check would read the routine's own CL=ABh and log
	// POST error 301 deterministically (nonzero error count -> I9990303 ->
	// no disk boot).  The MAIN keyboard test (checkpoint 6Dh) runs with
	// bit4=1 as before and fully passes, so the keyboard still works.
	logic [7:0] ckpt_last;
	assign kbd_hide  = (ckpt_last == 8'h56);
	// Boot-decision window ONLY: 6Eh (pre-INT19, F000:52B5), 6Fh (INT19
	// entry, 7DE4) and the boot-retry codes up to 7Fh.  POST also emits
	// HIGH checkpoint values early (F0h-FAh, BEh/BFh during the memory
	// phase), so a plain >= 6Eh comparison let an early CMOS 7Bh read
	// consume the setup request tens of seconds before INT19 sampled it.
	assign ckpt_boot = (ckpt_last >= 8'h6E) && (ckpt_last < 8'h80);

	logic io_write_d;
	always_ff @(posedge clk) begin
		if(reset) begin
			io_write_d <= 1'b0;
			ckpt_last <= 8'h00;
		end
		else begin
			io_write_d <= io_write;
			if(io_write && !io_write_d && io_address == 16'h0190)
				ckpt_last <= io_writedata;
		end
	end

	// ------------------------------------------------------------------
	// Optional hardware bring-up trace. Snoops BIOS, ATA, keyboard, CMOS,
	// and EBDA activity into a small FIFO drained at 115200 baud.
	generate if(POSTLOG_ENABLE) begin : g_postlog
		logic       io_read_d;
		logic [7:0] ata_status_reads;
		logic [7:0] ata_last_status = 8'hDE;
		logic [7:0] ata_last_err = 8'hDE;
		logic [7:0] kbc_last_status = 8'hDE;
		logic [6:0] cmos_sel;
		logic [15:0] plog_fifo [0:511];
		logic  [8:0] plog_head, plog_tail;

		always_ff @(posedge clk) begin
			io_read_d <= io_read;
			if(reset) begin
				ata_status_reads <= 8'd0;
				cmos_sel <= 7'd0;
			end
			else begin
				if(io_read && !io_read_d && io_address == 16'h01F7)
					ata_status_reads <= ata_status_reads + 1'd1;
				if(io_write && !io_write_d && io_address == 16'h0070)
					cmos_sel <= io_writedata[6:0];
			end
		end

		always_ff @(posedge clk) begin
			if(reset)
				plog_tail <= 9'd0;
			else if(io_write && !io_write_d) begin
			case(io_address)
				16'h03BC: begin plog_fifo[plog_tail] <= {8'h50, io_writedata}; plog_tail <= plog_tail + 1'd1; end // 'P' progress
				16'h0190: begin plog_fifo[plog_tail] <= {8'h45, io_writedata}; plog_tail <= plog_tail + 1'd1; end // 'E' failure hi
				16'h0191: begin plog_fifo[plog_tail] <= {8'h65, io_writedata}; plog_tail <= plog_tail + 1'd1; end // 'e' failure lo
				// video BIOS progress: C&T extension index writes ('X') mean
				// the 32 KiB runtime image decompressed and init body started
				16'h03D6: begin plog_fifo[plog_tail] <= {8'h58, io_writedata}; plog_tail <= plog_tail + 1'd1; end
				// ATA task-file trace: command bytes ('D'), device control
				// ('d'), and every 1F1h-1F6h register write (tag C1h-C6h)
				// reconstruct the BIOS's drive-detection conversation.
				16'h01F7: begin plog_fifo[plog_tail] <= {8'h44, io_writedata}; plog_tail <= plog_tail + 1'd1; end
				16'h03F6: begin plog_fifo[plog_tail] <= {8'h64, io_writedata}; plog_tail <= plog_tail + 1'd1; end
				16'h01F1, 16'h01F2, 16'h01F3,
				16'h01F4, 16'h01F5, 16'h01F6: begin
					plog_fifo[plog_tail] <= {5'b11000, io_address[2:0], io_writedata};
					plog_tail <= plog_tail + 1'd1;
				end
				// shadow/ROM decode config as POST programs it: tag 80h|index
				16'h00ED: if(eced_gate && eced_index >= 6'h0C && eced_index <= 6'h12) begin
					plog_fifo[plog_tail] <= {{2'b10, eced_index}, io_writedata};
					plog_tail <= plog_tail + 1'd1;
				end
				// 8042 keyboard conversation (diagnostic): keyboard-device
				// command writes to 60h (tag 'W'=57h) and controller command
				// writes to 64h (tag 'M'=4Dh), so the BIOS's exact 8042
				// command stream is visible alongside the 60h read stream.
				16'h0060: begin plog_fifo[plog_tail] <= {8'h57, io_writedata}; plog_tail <= plog_tail + 1'd1; end
				16'h0064: begin plog_fifo[plog_tail] <= {8'h4D, io_writedata}; plog_tail <= plog_tail + 1'd1; end
				// Device-diagnostic trace ranges. Tags encode the port:
				// A0-AF = 15E0h-15EFh writes, C0/C1 = PCIC index/data,
				// C8-CA = PC110 LPT 3BCh-3BEh (the 378h aliases are also
				// traced), D8-DF = COM2 2F8h-2FFh, E8-EF = COM1
				// 3F8h-3FFh.
				16'h15E0, 16'h15E1, 16'h15E2, 16'h15E3,
				16'h15E4, 16'h15E5, 16'h15E6, 16'h15E7,
				16'h15E8, 16'h15E9, 16'h15EA, 16'h15EB,
				16'h15EC, 16'h15ED, 16'h15EE, 16'h15EF: begin
					plog_fifo[plog_tail] <= {{4'hA, io_address[3:0]}, io_writedata};
					plog_tail <= plog_tail + 1'd1;
				end
				16'h03E0, 16'h03E1: begin
					plog_fifo[plog_tail] <= {{7'b1100000, io_address[0]}, io_writedata};
					plog_tail <= plog_tail + 1'd1;
				end
				16'h0378, 16'h0379, 16'h037A, 16'h037B,
				16'h037C, 16'h037D, 16'h037E, 16'h037F: begin
					plog_fifo[plog_tail] <= {{5'b11001, io_address[2:0]}, io_writedata};
					plog_tail <= plog_tail + 1'd1;
				end
				16'h03BC, 16'h03BD, 16'h03BE: begin
					plog_fifo[plog_tail] <= {{6'b110010, io_address[1:0]}, io_writedata};
					plog_tail <= plog_tail + 1'd1;
				end
				16'h02F8, 16'h02F9, 16'h02FA, 16'h02FB,
				16'h02FC, 16'h02FD, 16'h02FE, 16'h02FF: begin
					plog_fifo[plog_tail] <= {{5'b11011, io_address[2:0]}, io_writedata};
					plog_tail <= plog_tail + 1'd1;
				end
				16'h03F8, 16'h03F9, 16'h03FA, 16'h03FB,
				16'h03FC, 16'h03FD, 16'h03FE, 16'h03FF: begin
					plog_fifo[plog_tail] <= {{5'b11101, io_address[2:0]}, io_writedata};
					plog_tail <= plog_tail + 1'd1;
				end
				default: ;
			endcase
		end
		// log the value of every 1F7h status read when it changes (tag
		// 'v'), plus every 16th poll count (tag 'r'): reconstructs both
		// what the BIOS saw and how long it polled
		else if(io_read_d && !io_read && io_address == 16'h01F7 &&
		        io_snoop != ata_last_status) begin
			ata_last_status <= io_snoop;
			plog_fifo[plog_tail] <= {8'h76, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
		else if(io_read && !io_read_d && io_address == 16'h01F7 &&
		        ata_status_reads[3:0] == 4'hF) begin
			plog_fifo[plog_tail] <= {8'h72, ata_status_reads};
			plog_tail <= plog_tail + 1'd1;
		end
		// error register (1F1h) reads (tag 'x'): the reset-signature detect
		// at F000:D1E0 requires 01h here; log its value when it changes
		else if(io_read_d && !io_read && io_address == 16'h01F1 &&
		        io_snoop != ata_last_err) begin
			ata_last_err <= io_snoop;
			plog_fifo[plog_tail] <= {8'h78, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
		// signature register reads after reset (1F2 count, 1F4/1F5 cyl):
		// tag 's' with {addr[2:0], value nibble} so CHS signature is visible
		else if(io_read_d && !io_read &&
		        (io_address == 16'h01F2 || io_address == 16'h01F4 || io_address == 16'h01F5)) begin
			plog_fifo[plog_tail] <= {8'h73, io_address[3:0], io_snoop[3:0]};
			plog_tail <= plog_tail + 1'd1;
		end
		// keyboard data port 60h reads (tag 'K'): shows the scancodes the
		// guest receives from the 8042, proving keystrokes reach the core
		else if(io_read_d && !io_read && io_address == 16'h0060) begin
			plog_fifo[plog_tail] <= {8'h4B, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
		// 8042 status port 64h reads (tag 'S'), logged when the value
		// changes: reconstructs the OBF/AUXOBF/IBF sequence the BIOS polls,
		// so we can see whether OBF re-asserts for the identify's 2nd byte.
		else if(io_read_d && !io_read && io_address == 16'h0064 &&
		        io_snoop != kbc_last_status) begin
			kbc_last_status <= io_snoop;
			plog_fifo[plog_tail] <= {8'h53, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
		// Matching device-diagnostic reads: B0-BF = 15E0h-15EFh,
		// C2/C3 = PCIC, D0-D3 = LPT, E0-E7 = COM2, F0-F7 = COM1.
		else if(io_read_d && !io_read &&
		        io_address >= 16'h15E0 && io_address <= 16'h15EF) begin
			plog_fifo[plog_tail] <= {{4'hB, io_address[3:0]}, io_readdata};
			plog_tail <= plog_tail + 1'd1;
		end
		else if(io_read_d && !io_read &&
		        (io_address == 16'h03E0 || io_address == 16'h03E1)) begin
			plog_fifo[plog_tail] <= {{7'b1100001, io_address[0]}, io_readdata};
			plog_tail <= plog_tail + 1'd1;
		end
		else if(io_read_d && !io_read &&
		        io_address >= 16'h0378 && io_address <= 16'h037F) begin
			plog_fifo[plog_tail] <= {{5'b11010, io_address[2:0]}, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
		else if(io_read_d && !io_read &&
		        io_address >= 16'h03BC && io_address <= 16'h03BE) begin
			plog_fifo[plog_tail] <= {{6'b110100, io_address[1:0]}, io_readdata};
			plog_tail <= plog_tail + 1'd1;
		end
		else if(io_read_d && !io_read &&
		        io_address >= 16'h02F8 && io_address <= 16'h02FF) begin
			plog_fifo[plog_tail] <= {{5'b11100, io_address[2:0]}, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
		else if(io_read_d && !io_read &&
		        io_address >= 16'h03F8 && io_address <= 16'h03FF) begin
			plog_fifo[plog_tail] <= {{5'b11110, io_address[2:0]}, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
		// CMOS reads (port 71h) of the boot-order/diagnostic bytes: tag
		// 'C'=0Eh diag, 'c'=1Dh order-lo, 'i'=1Eh order-hi, plus 'B'=7Bh
		// (the INT19 enter-setup flag read at F000:813E - the logged value
		// shows whether the forced bit3 actually reached the BIOS)
		else if(io_read_d && !io_read && io_address == 16'h0071 &&
		        (cmos_sel == 7'h0E || cmos_sel == 7'h1D || cmos_sel == 7'h1E || cmos_sel == 7'h7B)) begin
			plog_fifo[plog_tail] <= {(cmos_sel==7'h0E)?8'h43:(cmos_sel==7'h1D)?8'h63:(cmos_sel==7'h1E)?8'h69:8'h42, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
		// EBDA POST-error-log writes (from the L2 snoop): the moment an
		// error is recorded, in stream order with checkpoints and I/O
		else if(errlog_wr) begin
			plog_fifo[plog_tail] <= {errlog_tag, errlog_byte};
			plog_tail <= plog_tail + 1'd1;
		end
		end

		logic [9:0]  plog_div;
		logic [3:0]  plog_bit;
		logic [9:0]  plog_shift;
		logic        plog_second;
		logic [7:0]  plog_code;

		always_ff @(posedge clk) begin
			if(reset) begin
				plog_head   <= 9'd0;
				plog_bit    <= 4'd0;
				plog_div    <= 10'd0;
				plog_second <= 1'b0;
				postlog_tx  <= 1'b1;
			end
			else if(plog_bit == 4'd0) begin
				postlog_tx <= 1'b1;
				if(plog_head != plog_tail || plog_second) begin
					if(plog_second) begin
						plog_shift <= {1'b1, plog_code, 1'b0};
					end
					else begin
						plog_shift <= {1'b1, plog_fifo[plog_head][15:8], 1'b0};
						plog_code  <= plog_fifo[plog_head][7:0];
						plog_head  <= plog_head + 1'd1;
					end
					plog_second <= ~plog_second;
					plog_bit    <= 4'd10;
					plog_div    <= 10'd0;
				end
			end
			else begin
				postlog_tx <= plog_shift[0];
				if(plog_div == POSTLOG_DIV[9:0] - 10'd1) begin
					plog_div   <= 10'd0;
					plog_shift <= {1'b1, plog_shift[9:1]};
					plog_bit   <= plog_bit - 4'd1;
				end
				else plog_div <= plog_div + 10'd1;
			end
		end
	end
	else begin : g_no_postlog
		assign postlog_tx = 1'b1;
	end
	endgenerate

endmodule
