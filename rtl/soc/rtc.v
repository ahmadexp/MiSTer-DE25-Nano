/*
 * Copyright (c) 2014, Aleksander Osman
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * 
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

module rtc(
	input             clk,
	input             rst_n,

	output reg        irq,

	//io slave
	input             io_address,
	input             io_read,
	output reg  [7:0] io_readdata,
	input             io_write,
	input       [7:0] io_writedata,

	input       [1:0] ram_option,
	input       [5:0] bootcfg,

	// force CMOS 7Bh bit3 (enter setup on this boot) while held
	input             setup_req,
	// pulses when the guest reads CMOS 7Bh while setup_req is held, so the
	// requester can one-shot the request (INT19 reads it at F000:813E)
	output reg        setup_ack,

	//mgmt slave
	/*
	128.[26:0]: cycles in second
	129.[12:0]: cycles in 122.07031 us
	*/
	input       [7:0] mgmt_address,
	input             mgmt_write,
	input       [7:0] mgmt_writedata,

	input      [27:0] clock_rate
);

reg [27:0] clk_rate;
always @(posedge clk) clk_rate <= clock_rate;

reg ce_800hz;
always @(posedge clk) begin
	reg [27:0] sum = 0;

	ce_800hz = 0;
	sum = sum + 28'd800;
	if(sum >= clk_rate) begin
		sum = sum - clk_rate;
		ce_800hz = 1;
	end
end

reg ce_8192hz;
always @(posedge clk) begin
	reg [27:0] sum = 0;

	ce_8192hz = 0;
	sum = sum + 28'd8192;
	if(sum >= clk_rate) begin
		sum = sum - clk_rate;
		ce_8192hz = 1;
	end
end

//------------------------------------------------------------------------------

reg io_read_last;
always @(posedge clk) begin if(rst_n == 1'b0) io_read_last <= 1'b0; else if(io_read_last) io_read_last <= 1'b0; else io_read_last <= io_read; end 
wire io_read_valid = io_read && io_read_last == 1'b0;

reg [15:0] pc110_cmos_checksum = 16'h0000;
reg  [1:0] pc110_checksum_ram_option = 2'd0;
wire [15:0] pc110_extmem_kb;
wire [15:0] pc110_above16_64k;
wire [15:0] pc110_ram_checksum_sum;
wire [15:0] pc110_saved_ram_checksum_sum;
wire [15:0] pc110_cmos_checksum_adjusted = pc110_cmos_checksum -
    pc110_saved_ram_checksum_sum + pc110_ram_checksum_sum;

pc110_ram_config ram_config
(
    .ram_option(ram_option),
    .word_limit(),
    .extmem_kb(pc110_extmem_kb),
    .above16_64k(pc110_above16_64k),
    .checksum_sum(pc110_ram_checksum_sum)
);

pc110_ram_config saved_ram_config
(
    .ram_option(pc110_checksum_ram_option),
    .word_limit(),
    .extmem_kb(),
    .above16_64k(),
    .checksum_sum(pc110_saved_ram_checksum_sum)
);

always @(posedge clk) begin
    if(rst_n == 1'b0) setup_ack <= 1'b0;
    else              setup_ack <= io_read_valid && io_address == 1'b1 &&
                                   ram_address == 7'h7B && setup_req;
end

//------------------------------------------------------------------------------ io read

wire [7:0] io_readdata_next =
    (io_address == 1'b0)   ? 8'hFF :
    (ram_address == 7'h00) ? rtc_second :
    (ram_address == 7'h01) ? alarm_second :
    (ram_address == 7'h02) ? rtc_minute :
    (ram_address == 7'h03) ? alarm_second :
    (ram_address == 7'h04) ? rtc_hour :
    (ram_address == 7'h05) ? alarm_hour :
    (ram_address == 7'h06) ? rtc_dayofweek :
    (ram_address == 7'h07) ? rtc_dayofmonth :
    (ram_address == 7'h08) ? rtc_month :
    (ram_address == 7'h09) ? rtc_year :
    (ram_address == 7'h0A) ? { sec_state == SEC_UPDATE_IN_PROGRESS || sec_state == SEC_SECOND_START, divider, periodic_rate } :
    (ram_address == 7'h0B) ? { crb_freeze, crb_int_periodic_ena, crb_int_alarm_ena, crb_int_update_ena,
                               1'b0, crb_binarymode, crb_24hour, crb_daylightsaving } :
    (ram_address == 7'h0C) ? { irq, periodic_interrupt, alarm_interrupt, update_interrupt, 4'd0 } :
    (ram_address == 7'h0D) ? 8'h80 :
    // Diagnostic-status byte: force bits 7 (power lost) and 6 (checksum
    // bad) clear.  POST sets them from the fresh-CMOS config errors (dead
    // battery, bad date), and the INT19 boot-list builder at F000:8874
    // tests bits 6+7 - if either is set it ignores the CMOS boot order
    // (which we set to HDD-first) and falls back to a floppy-first list,
    // so the internal disk is never booted.  Masking them makes the BIOS
    // honor the configured boot order.
    (ram_address == 7'h0E) ? (ram_q & 8'h3F) :
    // Memory geometry is read directly from the OSD selection so changing a
    // module followed by the automatic core reset cannot leave stale CMOS.
    (ram_address == 7'h17) ? pc110_extmem_kb[7:0] :
    (ram_address == 7'h18) ? pc110_extmem_kb[15:8] :
    (ram_address == 7'h2E) ? pc110_cmos_checksum_adjusted[15:8] :
    (ram_address == 7'h2F) ? pc110_cmos_checksum_adjusted[7:0] :
    (ram_address == 7'h30) ? pc110_extmem_kb[7:0] :
    (ram_address == 7'h31) ? pc110_extmem_kb[15:8] :
    (ram_address == 7'h34) ? pc110_above16_64k[7:0] :
    (ram_address == 7'h35) ? pc110_above16_64k[15:8] :
    // CMOS B8h-BFh (aliased to 38h-3Fh on this 128-byte RTC) hold the PC110
    // extended-CMOS checksum block.  POST's 184 check (F000:8FDF) sums
    // B8h..BEh, stopping at the first zero: an empty block (B8h==0) is
    // skipped.  Return 0 for 38h/3Fh so no 184 error is logged (a logged
    // error blocks disk boot). The generic boot-config aliases are unused.
    (ram_address == 7'h38) ? 8'h00 :
    (ram_address == 7'h3D) ? 8'h00 :
    (ram_address == 7'h3F) ? 8'h00 :
    (ram_address == 7'h32) ? rtc_century :
    (ram_address == 7'h37) ? rtc_century :
    // CMOS 7Bh bit3 = "enter setup on this boot".  The INT19 boot decision
    // (F000:8143) tests it right before its F1 check; the F1 check itself
    // reads the system MCU through an SMI service this CPU cannot provide, so
    // this bit is the only workable Easy-Setup entry.  setup_req is held by
    // the OSD "Enter BIOS Setup" action (and by a real F1 press during
    // POST) and expires on its own.
    (ram_address == 7'h7B) ? (ram_q | (setup_req ? 8'h08 : 8'h00)) :
    // CMOS 7Eh/7Fh hold the PC110 system-control/EC mailbox address used by
    // the BIOS's private INT 15h AX=5380h service. The prepared Easy-Setup
    // loader opens EC/ED directly, so this can retain the real 15EEh value
    // used by diagnostics and other firmware callers.
    (ram_address == 7'h7E) ? 8'h15 :
    (ram_address == 7'h7F) ? 8'hEE :
                             ram_q;

always @(posedge clk) io_readdata <= io_readdata_next;

//------------------------------------------------------------------------------ irq

wire interrupt_start = irq == 1'b0 && (
    (crb_int_periodic_ena && periodic_interrupt) ||
    (crb_int_alarm_ena    && alarm_interrupt) ||
    (crb_int_update_ena   && update_interrupt) );

always @(posedge clk) begin
    if(rst_n == 1'b0)                                                       irq <= 1'b0;
    else if(io_read_valid && io_address == 1'b1 && ram_address == 7'h0C)    irq <= 1'b0;
    else if(interrupt_start)                                                irq <= 1'b1;
end

//------------------------------------------------------------------------------ once per second state machine

localparam [2:0] SEC_UPDATE_START       = 3'd0;
localparam [2:0] SEC_UPDATE_IN_PROGRESS = 3'd1;
localparam [2:0] SEC_SECOND_START       = 3'd2;
localparam [2:0] SEC_SECOND_IN_PROGRESS = 3'd3;
localparam [2:0] SEC_STOPPED            = 3'd4;

reg [2:0] sec_state;

always @(posedge clk) begin
    if(rst_n == 1'b0)                                                sec_state <= SEC_UPDATE_START;
    
    else if(crb_freeze || divider[2:1] == 2'b11)                     sec_state <= SEC_STOPPED;
    else if(sec_state == SEC_STOPPED)                                sec_state <= SEC_UPDATE_START;
    
    else if(sec_state == SEC_UPDATE_START)                           sec_state <= SEC_UPDATE_IN_PROGRESS;
    else if(sec_state == SEC_UPDATE_IN_PROGRESS && !sec_timeout)     sec_state <= SEC_SECOND_START;
    else if(sec_state == SEC_SECOND_START)                           sec_state <= SEC_SECOND_IN_PROGRESS;
    else if(sec_state == SEC_SECOND_IN_PROGRESS && sec_timeout == 1) sec_state <= SEC_UPDATE_START;
end

reg [10:0] sec_timeout;
always @(posedge clk) begin
    if(rst_n == 1'b0)                               sec_timeout <= 4;
    else if(crb_freeze || divider[2:1] == 2'b11)    sec_timeout <= 4;
    else if(!sec_timeout)                           sec_timeout <= 799;
    else if(ce_800hz)                               sec_timeout <= sec_timeout - 1'd1;
end

reg update_interrupt;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                                       update_interrupt <= 1'b0;
    else if(io_read_valid && io_address == 1'b1 && ram_address == 7'h0C)    update_interrupt <= 1'b0;
    else if(sec_state == SEC_SECOND_START)                                  update_interrupt <= 1'b1;
end

//------------------------------------------------------------------------------

wire max_second = 
    (crb_binarymode && rtc_second >= 8'd59) ||
    (~(crb_binarymode) && (rtc_second[7:4] >= 4'd6 || (rtc_second[7:4] == 4'd5 && rtc_second[3:0] >= 4'd9)));

wire [7:0] next_second =
    (max_second)?                                       8'd0 :
    (~(crb_binarymode) && rtc_second[3:0] >= 4'd9)?     { rtc_second[7:4] + 4'd1, 4'd0 } :
                                                        rtc_second + 8'd1;

wire max_minute = 
    (crb_binarymode && rtc_minute >= 8'd59) ||
    (~(crb_binarymode) && (rtc_minute[7:4] >= 4'd6 || (rtc_minute[7:4] == 4'd5 && rtc_minute[3:0] >= 4'd9)));

wire [7:0] next_minute =
    (max_minute)?                                       8'd0 :
    (~(crb_binarymode) && rtc_minute[3:0] >= 4'd9)?     { rtc_minute[7:4] + 4'd1, 4'd0 } :
                                                        rtc_minute + 8'd1;

wire dst_april   = crb_daylightsaving && rtc_dayofweek == 8'd1 && rtc_month == 8'd4 &&
    ((crb_binarymode && rtc_dayofmonth >= 8'd24) || (~(crb_binarymode) && rtc_dayofmonth[7:4] >= 4'd2 && rtc_dayofmonth[3:0] >= 4'd4)) &&
    rtc_hour == 8'd1;

wire dst_october = crb_daylightsaving && rtc_dayofweek == 8'd1 &&
    ((crb_binarymode && rtc_month == 8'd10) || (~(crb_binarymode) && rtc_month[7:4] == 4'd1 && rtc_month[3:0] == 4'd0)) &&
    ((crb_binarymode && rtc_dayofmonth >= 8'd25) || (~(crb_binarymode) && rtc_dayofmonth[7:4] >= 4'd2 && rtc_dayofmonth[3:0] >= 4'd5)) &&
    rtc_hour == 8'd1;
    
wire max_hour =
    (~(crb_24hour) && crb_binarymode    && rtc_hour[7] && rtc_hour[6:0] >= 7'd12) ||
    (crb_24hour    && crb_binarymode    && rtc_hour >= 8'd23) ||
    (~(crb_24hour) && ~(crb_binarymode) && rtc_hour[7] && (rtc_hour[6:4] >= 3'd2 || (rtc_hour[6:4] == 3'd1 && rtc_hour[3:0] >= 4'd2))) ||
    (crb_24hour    && ~(crb_binarymode) && (rtc_hour[7:4] >= 4'd3 || (rtc_hour[7:4] == 4'd2 && rtc_hour[3:0] >= 4'd3)));

wire [7:0] next_hour =
    (dst_april)?                                                                                8'd3 :
    (dst_october)?                                                                              8'd1 :
    (~(crb_24hour) && max_hour)?                                                                8'd1 :
    (crb_24hour    && max_hour)?                                                                8'd0 :
    (~(crb_24hour) && crb_binarymode    && rtc_hour[6:0] >= 7'd12)?                             8'h81 :
    (~(crb_24hour) && ~(crb_binarymode) && rtc_hour[6:4] == 3'd1 && rtc_hour[3:0] >= 4'd2)?     8'h81 :
    (~(crb_24hour) && ~(crb_binarymode) && rtc_hour[6:4] == 3'd0 && rtc_hour[3:0] >= 4'd9)?     { rtc_hour[7], 3'b1, 4'd0 }  :
    (crb_24hour    && ~(crb_binarymode) && rtc_hour[3:0] >= 4'd9)?                              { rtc_hour[7:4] + 4'd1, 4'd0 } :
                                                                                                rtc_hour + 8'd1;

wire max_dayofweek = rtc_dayofweek >= 8'd7;

wire [7:0] next_dayofweek =
    (max_dayofweek)?    8'd1 :
                        rtc_dayofweek + 8'd1;

//simplified leap year condition
wire leap_year =
    (crb_binarymode    && rtc_year[1:0] == 2'b00) ||
    (~(crb_binarymode) && ((rtc_year[1:0] == 2'b00 && rtc_year[4] == 1'b0) || (rtc_year[1:0] == 2'b10 && rtc_year[4] == 1'b1)));

wire max_dayofmonth = 
    (crb_binarymode && (
        (rtc_month <= 8'd1  && rtc_dayofmonth >= 8'd31) ||
        (rtc_month == 8'd2  && ((~(leap_year) && rtc_dayofmonth >= 8'd28) || (leap_year && rtc_dayofmonth >= 8'd29))) ||
        (rtc_month == 8'd3  && rtc_dayofmonth >= 8'd31) ||
        (rtc_month == 8'd4  && rtc_dayofmonth >= 8'd30) ||
        (rtc_month == 8'd5  && rtc_dayofmonth >= 8'd31) ||
        (rtc_month == 8'd6  && rtc_dayofmonth >= 8'd30) ||
        (rtc_month == 8'd7  && rtc_dayofmonth >= 8'd31) ||
        (rtc_month == 8'd8  && rtc_dayofmonth >= 8'd31) ||
        (rtc_month == 8'd9  && rtc_dayofmonth >= 8'd30) ||
        (rtc_month == 8'd10 && rtc_dayofmonth >= 8'd31) ||
        (rtc_month == 8'd11 && rtc_dayofmonth >= 8'd30) ||
        (rtc_month >= 8'd12 && rtc_dayofmonth >= 8'd31))
    ) ||
    (~(crb_binarymode) && (
        (rtc_month <= 8'h01 && (rtc_dayofmonth[7:4] >= 4'd4 || (rtc_dayofmonth[7:4] == 4'd3 && rtc_dayofmonth[3:0] >= 4'd1))) ||
        (rtc_month == 8'h02 && ((~(leap_year) && (rtc_dayofmonth[7:4] >= 4'd3 || (rtc_dayofmonth[7:4] == 4'd2 && rtc_dayofmonth[3:0] >= 4'd8))) ||
                               (leap_year    && (rtc_dayofmonth[7:4] >= 4'd3 || (rtc_dayofmonth[7:4] == 4'd2 && rtc_dayofmonth[3:0] >= 4'd9))))) ||
        (rtc_month == 8'h03 && (rtc_dayofmonth[7:4] >= 4'd4 || (rtc_dayofmonth[7:4] == 4'd3 && rtc_dayofmonth[3:0] >= 4'd1))) ||
        (rtc_month == 8'h04 && (rtc_dayofmonth[7:4] >= 4'd4 || (rtc_dayofmonth[7:4] == 4'd3))) ||
        (rtc_month == 8'h05 && (rtc_dayofmonth[7:4] >= 4'd4 || (rtc_dayofmonth[7:4] == 4'd3 && rtc_dayofmonth[3:0] >= 4'd1))) ||
        (rtc_month == 8'h06 && (rtc_dayofmonth[7:4] >= 4'd4 || (rtc_dayofmonth[7:4] == 4'd3))) ||
        (rtc_month == 8'h07 && (rtc_dayofmonth[7:4] >= 4'd4 || (rtc_dayofmonth[7:4] == 4'd3 && rtc_dayofmonth[3:0] >= 4'd1))) ||
        (rtc_month == 8'h08 && (rtc_dayofmonth[7:4] >= 4'd4 || (rtc_dayofmonth[7:4] == 4'd3 && rtc_dayofmonth[3:0] >= 4'd1))) ||
        (rtc_month == 8'h09 && (rtc_dayofmonth[7:4] >= 4'd4 || (rtc_dayofmonth[7:4] == 4'd3))) ||
        (rtc_month == 8'h10 && (rtc_dayofmonth[7:4] >= 4'd4 || (rtc_dayofmonth[7:4] == 4'd3 && rtc_dayofmonth[3:0] >= 4'd1))) ||
        (rtc_month == 8'h11 && (rtc_dayofmonth[7:4] >= 4'd4 || (rtc_dayofmonth[7:4] == 4'd3))) ||
        (rtc_month >= 8'h12 && (rtc_dayofmonth[7:4] >= 4'd4 || (rtc_dayofmonth[7:4] == 4'd3 && rtc_dayofmonth[3:0] >= 4'd1))))
    );

wire [7:0] next_dayofmonth =
    (max_dayofmonth)?                                       8'd1 :
    (~(crb_binarymode) && rtc_dayofmonth[3:0] >= 4'd9)?     { rtc_dayofmonth[7:4] + 4'd1, 4'd0 } :
                                                            rtc_dayofmonth + 8'd1;

wire max_month =
    (crb_binarymode && rtc_month >= 8'd12) || (~(crb_binarymode) && (rtc_month[7:4] >= 4'd2 || (rtc_month[7:4] == 4'd1 && rtc_month[3:0] >= 4'd2)));

wire [7:0] next_month =
    (max_month)?                                    8'd1 :
    (~(crb_binarymode) && rtc_month[3:0] >= 4'd9)?  { rtc_month[7:4] + 4'd1, 4'd0 } :
                                                    rtc_month + 8'd1;
    
wire max_year =
    (crb_binarymode && rtc_year >= 8'd99) || (~(crb_binarymode) && (rtc_year[7:4] >= 4'd10 || (rtc_year[7:4] == 4'd9 && rtc_year[3:0] >= 4'd9)));

wire [7:0] next_year =
    (max_year)?                                     8'd0 :
    (~(crb_binarymode) && rtc_year[3:0] >= 4'd9)?   { rtc_year[7:4] + 4'd1, 4'd0 } :
                                                    rtc_year + 8'd1;

wire max_century =
    (crb_binarymode && rtc_century >= 8'd99) || (~(crb_binarymode) && (rtc_century[7:4] >= 4'd10 || (rtc_century[7:4] == 4'd9 && rtc_century[3:0] >= 4'd9)));

wire [7:0] next_century =
    (max_century)?                                      8'd0 :
    (~(crb_binarymode) && rtc_century[3:0] >= 4'd9)?    { rtc_century[7:4] + 4'd1, 4'd0 } :
                                                        rtc_century + 8'd1;
    
//------------------------------------------------------------------------------

wire rtc_second_update = sec_state == SEC_SECOND_START;
wire rtc_minute_update = rtc_second_update && max_second;
wire rtc_hour_update   = rtc_minute_update && max_minute;
wire rtc_day_update    = rtc_hour_update   && max_hour;
wire rtc_month_update  = rtc_day_update    && max_dayofmonth;
wire rtc_year_update   = rtc_month_update  && max_month;
wire rtc_century_update= rtc_year_update   && max_year;

//------------------------------------------------------------------------------

reg [7:0] rtc_second;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h00)                             rtc_second <= mgmt_writedata[7:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h00)     rtc_second <= io_writedata;
    else if(rtc_second_update)                                          rtc_second <= next_second; 
end

reg [7:0] rtc_minute;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h02)                             rtc_minute <= mgmt_writedata[7:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h02)     rtc_minute <= io_writedata;
    else if(rtc_minute_update)                                          rtc_minute <= next_minute;
end

reg [7:0] rtc_hour;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h04)                             rtc_hour <= mgmt_writedata[7:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h04)     rtc_hour <= io_writedata;
    else if(rtc_hour_update)                                            rtc_hour <= next_hour;
end

reg [7:0] rtc_dayofweek;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h06)                             rtc_dayofweek <= mgmt_writedata[7:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h06)     rtc_dayofweek <= io_writedata;
    else if(rtc_day_update)                                             rtc_dayofweek <= next_dayofweek;
end

reg [7:0] rtc_dayofmonth;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h07)                             rtc_dayofmonth <= mgmt_writedata[7:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h07)     rtc_dayofmonth <= io_writedata;
    else if(rtc_day_update)                                             rtc_dayofmonth <= next_dayofmonth;
end

reg [7:0] rtc_month;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h08)                             rtc_month <= mgmt_writedata[7:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h08)     rtc_month <= io_writedata;
    else if(rtc_month_update)                                           rtc_month <= next_month;
end

reg [7:0] rtc_year;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h09)                             rtc_year <= mgmt_writedata[7:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h09)     rtc_year <= io_writedata;
    else if(rtc_year_update)                                            rtc_year <= next_year;
end

reg [7:0] rtc_century;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h32)                             rtc_century <= mgmt_writedata[7:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h32)     rtc_century <= io_writedata;
    else if(io_write && io_address == 1'b1 && ram_address == 7'h37)     rtc_century <= io_writedata;
    else if(rtc_century_update)                                         rtc_century <= next_century;
end

//------------------------------------------------------------------------------

reg [7:0] alarm_second;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h01)                             alarm_second <= mgmt_writedata[7:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h01)     alarm_second <= io_writedata;
end

reg [7:0] alarm_minute;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h03)                             alarm_minute <= mgmt_writedata[7:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h03)     alarm_minute <= io_writedata;
end

reg [7:0] alarm_hour;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h05)                             alarm_hour <= mgmt_writedata[7:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h05)     alarm_hour <= io_writedata;
end

wire alarm_interrupt_activate =
    (alarm_second[7:6] == 2'b11 || (rtc_second_update && next_second == alarm_second)) &&
    (alarm_minute[7:6] == 2'b11 || (rtc_minute_update && next_minute == alarm_minute) || (~(rtc_minute_update) && rtc_minute == alarm_minute)) &&
    (alarm_hour[7:6] == 2'b11   || (rtc_hour_update && next_hour == alarm_hour)       || (~(rtc_hour_update)   && rtc_hour == alarm_hour));

reg alarm_interrupt;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                                   alarm_interrupt <= 1'b0;
    else if(io_read_valid && io_address == 1'b1 && ram_address == 7'h0C)alarm_interrupt <= 1'b0;
    else if(sec_state == SEC_SECOND_START && alarm_interrupt_activate)  alarm_interrupt <= 1'b1;
end

//------------------------------------------------------------------------------

/*
crb_freeze 1: no update, no alarm
*/

reg crb_freeze;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h0B)                             crb_freeze <= mgmt_writedata[7];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h0B)     crb_freeze <= io_writedata[7];
end

reg crb_int_periodic_ena;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h0B)                             crb_int_periodic_ena <= mgmt_writedata[6];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h0B)     crb_int_periodic_ena <= io_writedata[6];
end

reg crb_int_alarm_ena;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h0B)                             crb_int_alarm_ena <= mgmt_writedata[5];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h0B)     crb_int_alarm_ena <= io_writedata[5];
end

reg crb_int_update_ena;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h0B)                             crb_int_update_ena <= ~(mgmt_writedata[7]) & mgmt_writedata[4];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h0B)     crb_int_update_ena <= ~(io_writedata[7]) & io_writedata[4];
end

reg crb_binarymode;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h0B)                             crb_binarymode <= mgmt_writedata[2];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h0B)     crb_binarymode <= io_writedata[2];
end

reg crb_24hour;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h0B)                             crb_24hour <= mgmt_writedata[1];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h0B)     crb_24hour <= io_writedata[1];
end

reg crb_daylightsaving;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h0B)                             crb_daylightsaving <= mgmt_writedata[0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h0B)     crb_daylightsaving <= io_writedata[0]; 
end

//------------------------------------------------------------------------------

/*
divider 00x : no periodic
divider 11x : no update, no alarm
*/

reg [2:0] divider;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h0A)                             divider <= mgmt_writedata[6:4];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h0A)     divider <= io_writedata[6:4];
end

reg [3:0] periodic_rate;
always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h0A)                             periodic_rate <= mgmt_writedata[3:0];
    else if(io_write && io_address == 1'b1 && ram_address == 7'h0A)     periodic_rate <= io_writedata[3:0];
end

wire periodic_enabled = divider[2:1] != 2'b00 && periodic_rate != 4'd0;
wire periodic_start   = periodic_enabled && (
                            (ce_8192hz && periodic_major == 13'd0) ||
                            (ce_8192hz && periodic_major == 13'd1));

wire [12:0] periodic_major_initial = {
    periodic_rate == 4'd15, periodic_rate == 4'd14, periodic_rate == 4'd13, periodic_rate == 4'd12,
    periodic_rate == 4'd11, periodic_rate == 4'd10, periodic_rate == 4'd9 || periodic_rate == 4'd2,  periodic_rate == 4'd8 || periodic_rate == 4'd1,  
    periodic_rate == 4'd7,  periodic_rate == 4'd6,  periodic_rate == 4'd5,  periodic_rate == 4'd4,
    periodic_rate == 4'd3 };

reg [12:0] periodic_major;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                         periodic_major <= 13'd0;
    else if(~periodic_enabled)                                periodic_major <= 13'd0;
    else if(periodic_start)                                   periodic_major <= periodic_major_initial;
    else if(periodic_enabled && periodic_major && ce_8192hz) periodic_major <= periodic_major - 13'd1;
end

reg periodic_interrupt;
always @(posedge clk) begin
    if(rst_n == 1'b0)                                                    periodic_interrupt <= 1'b0;
    else if(io_read_valid && io_address == 1'b1 && ram_address == 7'h0C) periodic_interrupt <= 1'b0;
    else if(periodic_enabled && ce_8192hz && periodic_major == 13'd1)    periodic_interrupt <= 1'b1;
end

//------------------------------------------------------------------------------

reg [6:0] ram_address;
always @(posedge clk) begin
    if(rst_n == 1'b0)                       ram_address <= 7'd0;
    else if(io_write && io_address == 1'b0) ram_address <= io_writedata[6:0];
end

//------------------------------------------------------------------------------

// MiSTer Main initializes a generic PC-compatible CMOS. Translate the
// machine-specific fields as they cross the management port so the IBM BIOS
// sees the real PC110 equipment and selected memory geometry. Recompute the
// standard 10h..2Dh checksum over the translated values.
reg  [7:0] pc110_mgmt_data;

always @* begin
    pc110_mgmt_data = mgmt_writedata;
    case(mgmt_address)
        8'h10: pc110_mgmt_data = 8'h40; // one 1.44 MB external floppy
        8'h12: pc110_mgmt_data = 8'hFF; // both fixed disks present, extended type
        8'h14: pc110_mgmt_data = 8'h25; // PC110 equipment byte
        8'h19: pc110_mgmt_data = 8'h7F; // drive 0 extended type (live capture)
        8'h1A: pc110_mgmt_data = 8'h7F; // drive 1 extended type (live capture)
        // Boot-order nibbles (BIOS logical 9Dh/9Eh).  The builder at
        // F000:887F does ror al,4 before extracting each device nibble, so
        // the FIRST boot device is the HIGH nibble of 1Dh.  Nibble 8 =
        // internal fixed disk (device 0080h); 80h -> HDD first, then floppy
        // (low nibble 0).  Without the HDD nibble the BIOS never issues
        // INT13 AH=02 for the disk and halts at I9990303.
        8'h1D: pc110_mgmt_data = 8'h80;
        8'h1E: pc110_mgmt_data = 8'h00;
        8'h15: pc110_mgmt_data = 8'h80; // 640 KiB base memory
        8'h16: pc110_mgmt_data = 8'h02;
        8'h17: pc110_mgmt_data = pc110_extmem_kb[7:0];
        8'h18: pc110_mgmt_data = pc110_extmem_kb[15:8];
        8'h2E: pc110_mgmt_data = pc110_cmos_checksum_adjusted[15:8];
        8'h2F: pc110_mgmt_data = pc110_cmos_checksum_adjusted[7:0];
        8'h30: pc110_mgmt_data = pc110_extmem_kb[7:0];
        8'h31: pc110_mgmt_data = pc110_extmem_kb[15:8];
        8'h34: pc110_mgmt_data = pc110_above16_64k[7:0];
        8'h35: pc110_mgmt_data = pc110_above16_64k[15:8];
        default: ;
    endcase
end

always @(posedge clk) begin
    if(mgmt_write && mgmt_address == 8'h00) begin
        pc110_cmos_checksum <= 16'h0000;
        pc110_checksum_ram_option <= ram_option;
    end
    else if(mgmt_write && mgmt_address >= 8'h10 && mgmt_address <= 8'h2D)
        pc110_cmos_checksum <= pc110_cmos_checksum + pc110_mgmt_data;
end

//------------------------------------------------------------------------------

wire [7:0] ram_q;

simple_ram #(
    .width      (8),
    .widthad    (7)
)
rtc_ram_inst(
    .clk                (clk),
    
    .wraddress          ((mgmt_write && mgmt_address[7] == 1'b0)?   mgmt_address[6:0] : ram_address),
    .wren               ((mgmt_write && mgmt_address[7] == 1'b0) || (io_write && io_address == 1'b1)),
    .data               ((mgmt_write && mgmt_address[7] == 1'b0)?   pc110_mgmt_data : io_writedata),
    
    .rdaddress          ((io_write && io_address == 1'b0)?  io_writedata[6:0] : ram_address),
    .q                  (ram_q)
);


//------------------------------------------------------------------------------

endmodule
