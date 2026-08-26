
module l2_cache #(parameter ADDRBITS = 24)
(
   input         CLK,
   input         RESET,
	
   input         DISABLE,
   
   // CPU bus, master, 32bit
   input  [29:0] CPU_ADDR,
   input  [31:0] CPU_DIN,
   output [31:0] CPU_DOUT,
   output        CPU_DOUT_READY,
   input   [3:0] CPU_BE,
   input   [3:0] CPU_BURSTCNT,
   output        CPU_BUSY,
   input         CPU_RD,
   input         CPU_WE,
   
   // DDR3 RAM, slave, 64bit
   output [ADDRBITS:0] DDRAM_ADDR,
   output [63:0] DDRAM_DIN,
   input  [63:0] DDRAM_DOUT,
   input         DDRAM_DOUT_READY,
   output  [7:0] DDRAM_BE,
   output  [7:0] DDRAM_BURSTCNT,
   input         DDRAM_BUSY,
   output        DDRAM_RD,
   output        DDRAM_WE,
   
   // VGA bus, slave, 8bit
   output [16:0] VGA_ADDR,
   input   [7:0] VGA_DIN,
   output  [7:0] VGA_DOUT,
   input   [2:0] VGA_MODE,
   output        VGA_RD,
   output        VGA_WE,

	input   [5:0] VGA_WR_SEG,
	input   [5:0] VGA_RD_SEG,
	input         VGA_FB_EN,

	// IBM PC110 VL82C420 shadow-write state.  One bit per 16 KiB block
	// from C0000 through FFFFF.
	input  [15:0] PC110_SHADOW_WE,
	input   [7:0] PC110_ROMSET,

	// The 1 MiB font ROM is loaded at system DDR address 0x32000000 and
	// exposed as a 7-bit-banked 8 KiB window (normally DE000-DFFFF).
	input   [6:0] PC110_FONT_BANK,
	input   [7:0] PC110_FONT_SEG,
	input         PC110_FONT_EN,

	// VL82C420 RAMCFG0 (EC/ED index 02h).  POST's bank sizer relies on
	// physical DRAM aliasing: while the programmed row configuration does
	// not match the planar array (0Bh), accesses inside the 4 MiB planar
	// bank fold their row bits so a write at +400h reads back at the base
	// address, and the expansion region does not respond.
	input   [7:0] PC110_DRAM_CFG0,

	// Installed expansion module. Encoding is shared with the OSD:
	// 0 = 16 MB, 1 = none, 2 = 4 MB, 3 = 8 MB. The planar 4 MB is always
	// present, giving total capacities of 20, 4, 8 and 12 MB respectively.
	input   [1:0] PC110_RAM_OPTION,

	// PC110 debug: pulse when POST writes its error log in the EBDA
	// (count byte at phys 9FC17h, first code word at 9FC18h).  Fed to the
	// chipset post-logger so the exact moment an error is logged is
	// visible in the serial trace, interleaved with checkpoints and I/O.
	output reg        PC110_ERRLOG_WR,
	output reg  [7:0] PC110_ERRLOG_TAG,
	output reg  [7:0] PC110_ERRLOG_BYTE,

	// while high (Easy-Setup loader window, see pc110_chipset.sv), reads
	// of E0000h-FFFFFh alias to C0000h-DFFFFh - the DDR copy of the
	// flash's lower 128 KiB, which holds the Easy-Setup module.
	input             PC110_EASYSETUP,

	// while high (setup request armed), reads of EBDA:0xC5 return 01h so
	// the INT19 setup gate (F000:816A) routes into the Easy-Setup loader
	input             PC110_SETUP_FORCE
);
   

// cache settings
localparam LINES         = 128;
localparam LINESIZE      = 8;
localparam ASSOCIATIVITY = 4;	

// cache control
localparam ASSO_BITS     = $clog2(ASSOCIATIVITY);
localparam LINESIZE_BITS = $clog2(LINESIZE);
localparam LINE_BITS     = $clog2(LINES);
localparam RAMSIZEBITS   = $clog2(LINESIZE * LINES);

localparam LINEMASKLSB   = $clog2(LINESIZE);
localparam LINEMASKMSB   = LINEMASKLSB + $clog2(LINES) - 1;

reg    [ASSOCIATIVITY-1:0]      tags_dirty_in;
reg    [ASSOCIATIVITY-1:0]      tags_dirty_out;
wire   [ADDRBITS-RAMSIZEBITS:0] tags_read[0:ASSOCIATIVITY-1];
reg                             update_tag_we;
reg    [LINE_BITS-1:0]          update_tag_addr;

reg    [ASSO_BITS-1:0] LRU_in [0:ASSOCIATIVITY-1];
reg    [ASSO_BITS-1:0] LRU_out[0:ASSOCIATIVITY-1];
reg                             LRU_we;
reg    [LINE_BITS-1:0]          LRU_addr;

localparam [3:0]
   START         = 0,
	IDLE          = 1,
	WRITEONE      = 2,
	READONE       = 3,
	FILLCACHE     = 4,
	READCACHE_OUT = 5,
	VGAREAD       = 6,
	VGAWAIT       = 7,
	VGABYTECHECK  = 8,
	VGAWRITE      = 9;

// memory
wire              [31:0] readdata_cache[0:ASSOCIATIVITY-1];
reg      [ASSO_BITS-1:0] cache_mux;

reg    [RAMSIZEBITS-1:0] memory_addr_b;
reg               [63:0] memory_datain;
reg  [0:ASSOCIATIVITY-1] memory_we;
reg                [7:0] memory_be;
reg  [LINESIZE_BITS-1:0] fillcount;

reg   [3:0] state;

reg  [ADDRBITS:0] read_addr;
reg         [3:0] burst_left;

reg         force_fetch;
reg         force_next;

reg         data64_high;

// internal mux
reg         ram_dout_ready;
reg   [7:0] ram_burstcnt;
reg [ADDRBITS:0] ram_addr;
reg         ram_rd;
reg  [63:0] ram_din;
reg   [7:0] ram_be;
reg         ram_we;

reg         shr_rgn_en;
reg         read_behind;

reg         vga_ram;
reg  [31:0] vga_data;
reg  [31:0] vga_data_r;
reg   [3:0] vga_be;
reg   [2:0] vga_bcnt;
reg   [1:0] vga_ba;
reg         vga_wr;
reg         vga_re;
reg  [14:0] vga_wa;
reg   [1:0] vga_mask;
reg   [1:0] vga_cmp;
reg  [31:0] vga_next_data;
reg   [3:0] vga_next_be;
reg         vgabusy;

reg  [29:0] CPU_ADDR_1;
reg  [31:0] CPU_DIN_1;
reg         CPU_WE_1;

reg         RESET_1;
reg         RESET_2;

assign DDRAM_BURSTCNT = ram_burstcnt;
assign DDRAM_ADDR     = ram_addr;
assign DDRAM_RD       = ram_rd;
assign DDRAM_DIN      = ram_din;
assign DDRAM_BE       = ram_be;
assign DDRAM_WE       = ram_we;

assign CPU_BUSY       = (state == IDLE) ? DDRAM_BUSY : (vgabusy | ram_we);
// While the Easy-Setup request is armed, reads of EBDA:0xC5 (guest phys
// 9FCC5h = dword 27F31h byte lane 1) return 01h.  The INT19 setup gate
// (F000:816A) checks that byte - the BIOS itself never writes it - and
// routing it through the L2 read path makes the override cache-proof
// (an HPS-side DDR poke is invisible whenever the line sits dirty in
// this write-back cache).  Same arming window as the CMOS 7Bh divert.
wire setup_flag_rd = PC110_SETUP_FORCE && (CPU_ADDR_1 == 30'h0027F31);
assign CPU_DOUT       = vga_ram ? vga_data_r :
                        setup_flag_rd ? ((readdata_cache[cache_mux] & 32'hFFFF00FF) | 32'h00000100) :
                        readdata_cache[cache_mux];
assign CPU_DOUT_READY = ram_dout_ready;

assign VGA_DOUT       = vga_data[7:0];
assign VGA_WE         = vga_wr & vga_be[0];
assign VGA_RD         = vga_re & vga_be[0];
assign VGA_ADDR       = {vga_wa, vga_ba};

always @(posedge CLK) begin
	case (VGA_MODE)
		3'b100:		// 128K
			begin
				vga_mask <= 2'b00;
				vga_cmp  <= 2'b00;
			end
		
		3'b101:		// lower 64K
			begin
				vga_mask <= 2'b10;
				vga_cmp  <= 2'b00;
			end
		
		3'b110:		// 3rd 32K
			begin
				vga_mask <= 2'b11;
				vga_cmp  <= 2'b10;
			end
		
		3'b111:		// top 32K
			begin
				vga_mask <= 2'b11;
				vga_cmp  <= 2'b11;
			end
		
		default :	// disable VGA RAM
			begin
				vga_mask <= 2'b00;
				vga_cmp  <= 2'b11;
			end
	endcase
end
   
wire [1:0] pc110_shadow_segment = CPU_ADDR[17:14] - 4'hC;
wire [3:0] pc110_shadow_index =
	{pc110_shadow_segment, CPU_ADDR[13:12]};
wire pc110_upper_rgn =
	(CPU_ADDR[ADDRBITS+1:14] >= 'hC) &&
	(CPU_ADDR[ADDRBITS+1:14] <= 'hF);
// Upper memory is writable regardless of the per-16KiB xAXS write bits.
// The PC110 video BIOS stores its decompressor pointers into its own
// C-segment data area (C000:009F-02B7) while POST has those bits clear,
// so honoring them discards the pointers and the loader never completes.
// PC110-EMU, which runs this BIOS, likewise backs C0000-FFFFF with plain
// writable RAM.  PC110_SHADOW_WE is kept wired for future separation of
// the flash image from shadow RAM (see docs/STATUS.md debt item 1).
// Full upper-address compare: with only [17:11] compared the window
// aliased every 1 MiB, so extended-memory accesses at 1DE000h, 2DE000h,
// ... silently hit the font window instead of RAM.
wire pc110_font_rgn = PC110_FONT_EN &&
	(CPU_ADDR[29:11] == {12'h000, PC110_FONT_SEG[7:1]});
// The banked font window must be write-IGNORE like the real font ROM:
// $FONT.SYS's hardware probe (file offset 6618h) writes 55AAh over the
// AA55h signature and requires the readback to be UNCHANGED before it
// will register the hardware font sets.  With the window writable, that
// probe fails, no DBCS fonts register (the disk carries no $JPN*.FNT
// fallback), $DISP.SYS's INT15 AX=5000h font query gets AH=86h, V-text
// never installs, and Japanese text renders as garbage.
wire rom_rgn = pc110_font_rgn;
wire vga_rgn = (CPU_ADDR[ADDRBITS+1:15] == 'h5)  && ((CPU_ADDR[14:13] & vga_mask) == vga_cmp);
wire shr_rgn = (CPU_ADDR[ADDRBITS+1:11] == 'h67) && shr_rgn_en;
wire [ADDRBITS:0] pc110_font_addr =
	25'h0400000 + {8'h00, PC110_FONT_BANK, 10'h000} + CPU_ADDR[10:1];
// CPU_ADDR is a 32-bit-word address. Select the physical end of installed
// memory from the 4 MiB planar RAM and the chosen expansion module.
wire [29:0] pc110_ram_limit;
pc110_ram_config ram_config
(
	.ram_option(PC110_RAM_OPTION),
	.word_limit(pc110_ram_limit),
	.extmem_kb(),
	.above16_64k(),
	.checksum_sum()
);
// The upper-memory flash/shadow area and the banked font window remain
// backed by DDR even though they are outside installed conventional RAM.
//
// POST's DRAM bank sizer (F000:3889) programs candidate row codes into
// RAMCFG0 and detects the geometry from physical aliasing.  While the
// planar configuration is not the settled 0Bh, conventional-memory
// accesses below A0000h fold the +400h/+800h/+1000h row bits so the
// probe observes the 4 MiB planar's alias signature, and the expansion
// region does not respond (open bus).
wire pc110_cfg_settled = (PC110_DRAM_CFG0[3:0] == 4'hB);
wire pc110_fold = ~pc110_cfg_settled && (CPU_ADDR < 30'h00028000);
// ROMSET=19h is the PC110's normal split-ROM decode. In this mode the
// 64 KiB video option ROM physically stored at E0000h appears at C0000h.
// Alias writes as well because the C&T BIOS keeps private data in its
// otherwise ROM-addressed segment.
wire pc110_vga_rom_alias =
	(PC110_ROMSET == 8'h19) &&
	(CPU_ADDR[ADDRBITS+1:14] == 'hC);
// Easy-Setup loader window: E0000h-FFFFFh (words 38000h-3FFFFh) fetch the
// flash's lower 128 KiB, whose DDR copy sits at guest C0000h-DFFFFh
// (-8000h words).  That copy is pristine: C-segment writes alias away
// (pc110_vga_rom_alias) and nothing writes the D segment.
wire pc110_easysetup_alias = PC110_EASYSETUP &&
	(CPU_ADDR[29:15] == 15'h7);
wire [29:0] pc110_rom_addr =
	pc110_easysetup_alias ? (CPU_ADDR - 30'h00008000) :
	pc110_vga_rom_alias   ? (CPU_ADDR + 30'h00008000) : CPU_ADDR;
wire [29:0] cpu_addr_m = pc110_fold ?
	(pc110_rom_addr & ~30'h00000700) : pc110_rom_addr;

// CC000h-DBFFFh is open bus on the real PC110: the video option ROM
// decode ends below CC000h and nothing occupies the D segment (the font
// window sits at DE000h).  IBM's shipped CONFIG.SYS relies on that -
// EMM386 puts its EMS page frame at CC00h and scans it for ROM/RAM
// first.  Our ROMSET alias made the whole C segment readable (video
// BIOS image bytes at CC000h-CFFFFh), so EMM386 warned "Option ROM or
// RAM detected within page frame" and paused the boot.  Words 33000h-
// 36FFFh = bytes CC000h-DBFFFh; the CE000h unlock window (shr_rgn)
// stays mapped.
wire pc110_ems_open = (CPU_ADDR[29:12] >= 18'h33) && (CPU_ADDR[29:12] <= 18'h36) &&
	~shr_rgn;

wire ram_rgn = (((CPU_ADDR < 30'h00100000) ||
	((CPU_ADDR < pc110_ram_limit) && pc110_cfg_settled) ||
	pc110_upper_rgn) && ~pc110_ems_open) || pc110_font_rgn;

wire [7:0] be64 = CPU_ADDR[0] ? {CPU_BE, 4'h0} : {4'h0, CPU_BE};

always @(posedge CLK) begin
	reg [ASSO_BITS:0] i;
	reg [ASSO_BITS-1:0] match;
	
	ram_dout_ready <= 1'b0;
	memory_we      <= {ASSOCIATIVITY{1'b0}};
	
	RESET_1 <= RESET;
	RESET_2 <= RESET_1;

	if (RESET_1 && ~RESET_2) begin
		state           <= START;
		update_tag_addr <= {LINE_BITS{1'b0}};
		update_tag_we   <= 1'b1;
		tags_dirty_in   <= {ASSOCIATIVITY{1'b1}};
		shr_rgn_en      <= 1'b0;
		vgabusy         <= 1'b0;
	end
	else begin
		
		if (~DDRAM_BUSY) begin
			ram_rd <= 1'b0;
			ram_we <= 1'b0;
		end

		// LRU update after read
		LRU_we <= ram_dout_ready && ~LRU_we;
		for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
			LRU_in[i] <= LRU_out[i];
			if (cache_mux == i[ASSO_BITS-1:0]) begin
				match     = LRU_out[i];
				LRU_in[i] <= {ASSO_BITS{1'b0}};
			end
		end
		for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
			if (LRU_out[i] < match) begin
				LRU_in[i] <= LRU_out[i] + 1'd1;
			end
		end

		if (CPU_WE_1 && (CPU_ADDR_1 == 'h33800) && (CPU_DIN_1[15:0] == 'hA345)) shr_rgn_en <= 1'b1;
		
		case (state)
			
			START:
				begin
					update_tag_addr <= update_tag_addr + 1'd1;

					for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
						LRU_in[i]    <= i[ASSO_BITS-1:0]; 
					end
					LRU_addr        <= update_tag_addr;
					LRU_we          <= 1'b1; 

					if (update_tag_addr == {LINE_BITS{1'b1}}) begin
						state         <= IDLE;
						update_tag_we <= 1'b0;
					end
				end

			IDLE:
				begin
					vga_wr <= 1'b0;
					vga_re <= 1'b0;
					if (!DDRAM_BUSY) begin
						
						// for timing purposes, most registers are assigned without region checks
						CPU_ADDR_1    <= cpu_addr_m;
						CPU_DIN_1     <= CPU_DIN;
						CPU_WE_1      <= CPU_WE;

						ram_addr      <= cpu_addr_m[ADDRBITS+1:1];
						ram_burstcnt  <= 8'h01;
						read_addr     <= cpu_addr_m[ADDRBITS+1:1];
						burst_left    <= CPU_BURSTCNT;
						data64_high   <= cpu_addr_m[0];

						vga_wa        <= CPU_ADDR[14:0];
						vga_bcnt      <= 3;
						vga_next_data <= CPU_DIN;
						vga_next_be   <= CPU_BE;
						vga_ba        <= 2'b00;
						vga_be        <= CPU_BE;

						ram_din       <= {CPU_DIN, CPU_DIN};
						ram_be        <= be64;

						memory_datain <= {CPU_DIN, CPU_DIN};
						memory_be     <= be64;
						memory_addr_b <= cpu_addr_m[RAMSIZEBITS:1];

						if(pc110_font_rgn) begin
							ram_addr  <= pc110_font_addr;
							read_addr <= pc110_font_addr;
						end

						read_behind   <= ~ram_rgn;
						force_fetch   <= shr_rgn | DISABLE;
						force_next    <= shr_rgn | DISABLE;

						if (CPU_RD) begin
							state     <= READONE;
							if (vga_rgn) begin
								if(VGA_FB_EN) begin
									ram_addr[24:13]  <= {6'b111110, VGA_RD_SEG};
									read_addr[24:13] <= {6'b111110, VGA_RD_SEG};
								end
								else begin
									vga_re  <= 1'b1;
									state   <= VGAWAIT;
								end
							end
						end
						else if (CPU_WE & (~rom_rgn | shr_rgn) & ram_rgn) begin
							if (vga_rgn) begin
								if(VGA_FB_EN) begin
									ram_addr[24:13]  <= {6'b111110, VGA_WR_SEG};
									read_addr[24:13] <= {6'b111110, VGA_WR_SEG};
									ram_we  <= 1'b1;
									state   <= WRITEONE;
								end
								else begin
									vgabusy <= 1'b1;
									state   <= VGABYTECHECK;
								end
							end
							else begin
								ram_we  <= 1'b1;
								state   <= WRITEONE;
							end
						end
					end
				end
			
			WRITEONE:
				begin
					state <= IDLE;
					for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
						if (~tags_dirty_out[i]) begin
							if (tags_read[i] == read_addr[ADDRBITS:RAMSIZEBITS]) memory_we[i] <= 1'b1;
						end
					end
				end
			
			READONE:
				begin
					vga_ram         <= read_behind;		// use fake vga response for reading behind available ram
					vga_data_r      <= read_behind ? 32'hFFFFFFFF : 32'd0;	// open bus beyond installed RAM
					state           <= FILLCACHE;
					ram_rd          <= 1'b1;
					ram_addr        <= {read_addr[ADDRBITS:LINESIZE_BITS], {LINESIZE_BITS{1'b0}}};
					ram_be          <= 8'h00;
					ram_burstcnt    <= LINESIZE[7:0];
					fillcount       <= 0;
					memory_addr_b   <= {read_addr[RAMSIZEBITS - 1:LINESIZE_BITS], {LINESIZE_BITS{1'b0}}};
					tags_dirty_in   <= tags_dirty_out;
					update_tag_addr <= read_addr[LINEMASKMSB:LINEMASKLSB];
					update_tag_we   <= 1'b0;
					LRU_addr        <= read_addr[LINEMASKMSB:LINEMASKLSB];

					if (force_fetch) force_next <= ~force_next;

					if (~force_next) begin
						for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
							if (~tags_dirty_out[i]) begin
								if (tags_read[i] == read_addr[ADDRBITS:RAMSIZEBITS]) begin
									ram_rd         <= 1'b0;
									cache_mux      <= i[ASSO_BITS-1:0];
									ram_dout_ready <= 1'b1;
									if (burst_left > 1) begin
										state       <= READONE;
										burst_left  <= burst_left - 1'd1;
										data64_high <= ~data64_high;
										if (data64_high) read_addr <= read_addr + 1'd1;
									end
									else begin
										state <= IDLE;
									end
								end
							end
						end
					end
					else begin
						tags_dirty_in <= {ASSOCIATIVITY{1'b1}};
						update_tag_we <= 1'b1;
					end
				end
			
			FILLCACHE:
				begin
					for (i = 0; i < ASSOCIATIVITY; i = i + 1'd1) begin
						if (LRU_out[i] == {ASSO_BITS{1'b1}} ) cache_mux <= i[ASSO_BITS-1:0]; 
					end

					if (DDRAM_DOUT_READY) begin
						memory_datain        <= DDRAM_DOUT;
						memory_we[cache_mux] <= 1'b1;
						memory_be            <= 8'hFF;

						tags_dirty_in[cache_mux] <= 1'b0;

						if (fillcount > 0) memory_addr_b <= memory_addr_b + 1'd1;
						if (fillcount < LINESIZE - 1) fillcount <= fillcount + 1'd1;
						else begin 
							state         <= READCACHE_OUT;
							update_tag_we <= 1'b1;
						end
					end
				end
			
			VGAWAIT:
				state <= VGAREAD;
			
			VGAREAD:
				begin
					vga_ram  <= 1'b1;
					vga_bcnt <= vga_bcnt - 1'd1;
					vga_be   <= {1'b0, vga_be[3:1]};
					vga_ba   <= vga_ba + 1'd1;
					vga_data <= {VGA_DIN, vga_data[31:8]};
					state    <= VGAWAIT;

					if (!vga_bcnt) begin
						ram_dout_ready <= 1'b1;
						vga_data_r     <= {VGA_DIN, vga_data[31:8]};
						if (burst_left > 1) begin
							vga_wa      <= vga_wa + 1'd1;
							vga_ba      <= 2'b00;
							vga_bcnt    <= 3;
							vga_be      <= 4'b1111;
							burst_left  <= burst_left - 1'd1;
						end
						else begin
							state <= IDLE;
						end
					end
				end
			
			VGABYTECHECK:
				begin
					state  <= VGAWRITE;
					vga_wr <= 1'b1;
					if (!vga_next_be[2:0]) begin
						vga_data <= {24'h000000, vga_next_data[31:24]};
						vga_be   <= {3'b000, vga_next_be[3]};
						vga_ba   <= 2'b11;
					end
					else if (!vga_next_be[1:0]) begin
						vga_data <= {16'h0000, vga_next_data[31:16]};
						vga_be   <= {2'b00, vga_next_be[3:2]};
						vga_ba   <= 2'b10;
					end
					else if (!vga_next_be[0]) begin
						vga_data <= {8'h00, vga_next_data[31:8]};
						vga_be   <= {1'b0, vga_next_be[3:1]};
						vga_ba   <= 2'b01;
					end
					else begin
						vga_data <= vga_next_data;
						vga_be   <= vga_next_be;
						vga_ba   <= 2'b00;
					end
				end

			VGAWRITE:
				begin
					vga_bcnt   <= vga_bcnt - 1'd1;
					vga_be     <= {1'b0, vga_be[3:1]};
					vga_ba     <= vga_ba + 1'd1;
					vga_data   <= {8'h00, vga_data[31:8]};
					if (!vga_be[3:1]) begin
						state   <= IDLE;
						vgabusy <= 1'b0;
					end
				end

			READCACHE_OUT:
				begin
					state         <= READONE;
					update_tag_we <= 1'b0;
				end
		endcase
	end
end

altdpram #(
	.indata_aclr("OFF"),
	.indata_reg("INCLOCK"),
	.intended_device_family("Cyclone V"),
	.lpm_type("altdpram"),
	.outdata_aclr("OFF"),
	.outdata_reg("UNREGISTERED"),
	.ram_block_type("MLAB"),
	.rdaddress_aclr("OFF"),
	.rdaddress_reg("UNREGISTERED"),
	.rdcontrol_aclr("OFF"),
	.rdcontrol_reg("UNREGISTERED"),
	.read_during_write_mode_mixed_ports("CONSTRAINED_DONT_CARE"),
	.width(ASSOCIATIVITY),
	.widthad(LINE_BITS),
	.width_byteena(1),
	.wraddress_aclr("OFF"),
	.wraddress_reg("INCLOCK"),
	.wrcontrol_aclr("OFF"),
	.wrcontrol_reg("INCLOCK")
)
dirtyram (
	.inclock(CLK),
	.outclock(CLK),
	
	.data(tags_dirty_in),
	.rdaddress(read_addr[LINEMASKMSB:LINEMASKLSB]),
	.wraddress(update_tag_addr),
	.wren(update_tag_we),
	.q(tags_dirty_out)
);

generate
	genvar i;
	for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin : gcache
		altdpram #(
			.indata_aclr("OFF"),
			.indata_reg("INCLOCK"),
			.intended_device_family("Cyclone V"),
			.lpm_type("altdpram"),
			.outdata_aclr("OFF"),
			.outdata_reg("UNREGISTERED"),
			.ram_block_type("MLAB"),
			.rdaddress_aclr("OFF"),
			.rdaddress_reg("UNREGISTERED"),
			.rdcontrol_aclr("OFF"),
			.rdcontrol_reg("UNREGISTERED"),
			.read_during_write_mode_mixed_ports("CONSTRAINED_DONT_CARE"),
			.width(ADDRBITS - RAMSIZEBITS + 1),
			.widthad(LINE_BITS),
			.width_byteena(1),
			.wraddress_aclr("OFF"),
			.wraddress_reg("INCLOCK"),
			.wrcontrol_aclr("OFF"),
			.wrcontrol_reg("INCLOCK")
		)
		tagram (
			.inclock(CLK),
			.outclock(CLK),
			
			.data(read_addr[ADDRBITS:RAMSIZEBITS]),
			.rdaddress(read_addr[LINEMASKMSB:LINEMASKLSB]),
			.wraddress(read_addr[LINEMASKMSB:LINEMASKLSB]),
			.wren((state == READCACHE_OUT) && (cache_mux == i)),
			.q(tags_read[i])
		);

		altdpram #(
			.indata_aclr("OFF"),
			.indata_reg("INCLOCK"),
			.intended_device_family("Cyclone V"),
			.lpm_type("altdpram"),
			.outdata_aclr("OFF"),
			.outdata_reg("UNREGISTERED"),
			.ram_block_type("MLAB"),
			.rdaddress_aclr("OFF"),
			.rdaddress_reg("UNREGISTERED"),
			.rdcontrol_aclr("OFF"),
			.rdcontrol_reg("UNREGISTERED"),
			.read_during_write_mode_mixed_ports("CONSTRAINED_DONT_CARE"),
			.width(ASSO_BITS),
			.widthad(LINE_BITS),
			.width_byteena(1),
			.wraddress_aclr("OFF"),
			.wraddress_reg("INCLOCK"),
			.wrcontrol_aclr("OFF"),
			.wrcontrol_reg("INCLOCK")
		)
		LRUram (
			.inclock(CLK),
			.outclock(CLK),
			
			.data(LRU_in[i]),
			.rdaddress(LRU_addr),
			.wraddress(LRU_addr),
			.wren(LRU_we),
			.q(LRU_out[i])
		);
		
		altsyncram #(
			.address_aclr_b("NONE"),
			.address_reg_b("CLOCK0"),
			.byte_size(8),
			.clock_enable_input_a("BYPASS"),
			.clock_enable_input_b("BYPASS"),
			.clock_enable_output_b("BYPASS"),
			.intended_device_family("Cyclone V"),
			.lpm_type("altsyncram"),
			.numwords_a(2**RAMSIZEBITS),
			.numwords_b(2**(RAMSIZEBITS+1)),
			.operation_mode("DUAL_PORT"),
			.outdata_aclr_b("NONE"),
			.outdata_reg_b("UNREGISTERED"),
			.power_up_uninitialized("FALSE"),
			.read_during_write_mode_mixed_ports("DONT_CARE"),
			.widthad_a(RAMSIZEBITS),
			.widthad_b(RAMSIZEBITS+1),
			.width_a(64),
			.width_b(32),
			.width_byteena_a(8)
		)
		ram (
			.clock0 (CLK),

			.address_a(memory_addr_b),
			.byteena_a(memory_be),
			.data_a(memory_datain),
			.wren_a(memory_we[i]),

			.address_b({read_addr[RAMSIZEBITS - 1:0], data64_high}),
			.q_b(readdata_cache[i]),

			.aclr0(1'b0),
			.aclr1(1'b0),
			.addressstall_a(1'b0),
			.addressstall_b(1'b0),
			.byteena_b(1'b1),
			.clock1(1'b1),
			.clocken0(1'b1),
			.clocken1(1'b1),
			.clocken2(1'b1),
			.clocken3(1'b1),
			.data_b(32'b0),
			.eccstatus(),
			.q_a(),
			.rden_a(1'b1),
			.rden_b(1'b1),
			.wren_b(1'b0)
		);
	end
endgenerate 

// PC110 debug: EBDA error-log write snoop.  CPU_ADDR/cpu_addr_m are 32-bit
// -word addresses, so the EBDA error count byte (phys 9FC17h, EBDA:0x17
// with the EBDA at segment 9FC0h) is dword 27F05h byte lane 3, and the
// first logged code word (phys 9FC18h) is dword 27F06h lanes 0-1.  A write
// is accepted exactly when the state machine leaves IDLE with it, so gate
// on that cycle for a one-shot per write.  Tags: 'J' (4Ah) = count byte
// written (value = new count), 'j' (6Ah) = code word low byte.
always @(posedge CLK) begin
	PC110_ERRLOG_WR <= 1'b0;
	if (state == IDLE && !DDRAM_BUSY && CPU_WE) begin
		if (cpu_addr_m == 30'h27F05 && CPU_BE[3]) begin
			PC110_ERRLOG_WR   <= 1'b1;
			PC110_ERRLOG_TAG  <= 8'h4A;
			PC110_ERRLOG_BYTE <= CPU_DIN[31:24];
		end
		else if (cpu_addr_m == 30'h27F06 && CPU_BE[0]) begin
			PC110_ERRLOG_WR   <= 1'b1;
			PC110_ERRLOG_TAG  <= 8'h6A;
			PC110_ERRLOG_BYTE <= CPU_DIN[7:0];
		end
	end
end

endmodule
