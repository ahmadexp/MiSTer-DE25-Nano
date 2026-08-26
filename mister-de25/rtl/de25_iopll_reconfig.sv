// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Applies a complete Agilex 5 HVIO IOPLL reconfiguration sequence. Counter and
// charge-pump values are precomputed from Quartus-generated legal profiles.
// Every partial register update is read-modify-write, as required by the guide.
module de25_iopll_reconfig #(
    parameter integer LOCK_TIMEOUT_CYCLES = 1_000_000
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [31:0] m_settings,
    input  logic [31:0] c0_settings,
    input  logic [31:0] c1_settings,
    input  logic [14:0] charge_pump_settings,
    input  logic        locked,
    output logic        busy,
    output logic        done,
    output logic        error,

    output logic  [8:0] core_avl_address,
    output logic        core_avl_read,
    input  logic  [7:0] core_avl_readdata,
    output logic        core_avl_write,
    output logic  [7:0] core_avl_writedata
);

    localparam logic [31:0] M_MASK = 32'h9FF3_FFFF;
    localparam logic [31:0] C_MASK = 32'hFFBF_F9FF;

    typedef enum logic [2:0] {
        IDLE,
        ISSUE_READ,
        WAIT_READ,
        ISSUE_WRITE,
        WAIT_WRITE,
        WAIT_LOCK
    } state_t;

    state_t state;
    logic [3:0] sequence_step;
    logic [31:0] saved_m_settings;
    logic [31:0] saved_c0_settings;
    logic [31:0] saved_c1_settings;
    logic [14:0] saved_charge_pump;
    logic [31:0] rmw_readdata;
    logic [31:0] lock_timeout;
    logic saw_unlock;

    logic avmm_start;
    logic avmm_write_request;
    logic [8:0] avmm_address;
    logic [31:0] avmm_writedata;
    logic [31:0] avmm_readdata;
    logic avmm_busy;
    logic avmm_done;

    logic [8:0] step_address;
    logic [31:0] step_mask;
    logic [31:0] step_value;

    always_comb begin
        step_address = 9'h000;
        step_mask    = 32'h0000_0000;
        step_value   = 32'h0000_0000;

        case (sequence_step)
            4'd0: begin // Permit divide-register access.
                step_address = 9'h010;
                step_mask    = 32'h0000_0001;
                step_value   = 32'h0000_0001;
            end
            4'd1: begin // Clear old calibration status bits 7 and 21.
                step_address = 9'h058;
                step_mask    = 32'h0020_0080;
            end
            4'd2: begin
                step_address = 9'h040;
                step_mask    = M_MASK;
                step_value   = saved_m_settings;
            end
            4'd3: begin
                step_address = 9'h044;
                step_mask    = 32'h0000_FFFE;
                step_value   = {16'd0, saved_charge_pump, 1'b0};
            end
            4'd4: begin
                step_address = 9'h05C;
                step_mask    = C_MASK;
                step_value   = saved_c0_settings;
            end
            4'd5: begin // Program the phase-shifted SDRAM clock output.
                step_address = 9'h060;
                step_mask    = C_MASK;
                step_value   = saved_c1_settings;
            end
            4'd6: begin // Assert PLL reset. One full transaction exceeds 10 ns.
                step_address = 9'h080;
                step_mask    = 32'h0000_0004;
                step_value   = 32'h0000_0004;
            end
            4'd7: begin
                step_address = 9'h080;
                step_mask    = 32'h0000_0004;
            end
            4'd8: begin // Enable HVIO recalibration.
                step_address = 9'h048;
                step_mask    = 32'h0000_4000;
                step_value   = 32'h0000_4000;
            end
            4'd9: begin // Request recalibration.
                step_address = 9'h088;
                step_mask    = 32'h0000_0800;
                step_value   = 32'h0000_0800;
            end
            default: begin // Clear recalibration enable after lock returns.
                step_address = 9'h048;
                step_mask    = 32'h0000_4000;
            end
        endcase
    end

    assign avmm_address   = step_address;
    assign avmm_writedata = (rmw_readdata & ~step_mask) |
                            (step_value & step_mask);

    de25_iopll_avmm transport (
        .clk,
        .reset,
        .start(avmm_start),
        .write_request(avmm_write_request),
        .address(avmm_address),
        .writedata(avmm_writedata),
        .readdata(avmm_readdata),
        .busy(avmm_busy),
        .done(avmm_done),
        .core_avl_address,
        .core_avl_read,
        .core_avl_readdata,
        .core_avl_write,
        .core_avl_writedata
    );

    always_ff @(posedge clk) begin
        avmm_start <= 1'b0;
        done       <= 1'b0;

        if (reset) begin
            state                <= IDLE;
            sequence_step        <= 4'd0;
            saved_m_settings     <= 32'd0;
            saved_c0_settings    <= 32'd0;
            saved_c1_settings    <= 32'd0;
            saved_charge_pump    <= 15'd0;
            rmw_readdata         <= 32'd0;
            lock_timeout         <= 32'd0;
            saw_unlock           <= 1'b0;
            avmm_write_request   <= 1'b0;
            busy                 <= 1'b0;
            error                <= 1'b0;
        end else begin
            if (busy && !locked)
                saw_unlock <= 1'b1;

            case (state)
                IDLE: begin
                    if (start) begin
                        saved_m_settings  <= m_settings;
                        saved_c0_settings <= c0_settings;
                        saved_c1_settings <= c1_settings;
                        saved_charge_pump <= charge_pump_settings;
                        sequence_step     <= 4'd0;
                        saw_unlock        <= ~locked;
                        error             <= 1'b0;
                        busy              <= 1'b1;
                        state             <= ISSUE_READ;
                    end
                end

                ISSUE_READ: begin
                    if (!avmm_busy) begin
                        avmm_write_request <= 1'b0;
                        avmm_start         <= 1'b1;
                        state              <= WAIT_READ;
                    end
                end

                WAIT_READ: begin
                    if (avmm_done) begin
                        rmw_readdata <= avmm_readdata;
                        state        <= ISSUE_WRITE;
                    end
                end

                ISSUE_WRITE: begin
                    if (!avmm_busy) begin
                        avmm_write_request <= 1'b1;
                        avmm_start         <= 1'b1;
                        state              <= WAIT_WRITE;
                    end
                end

                WAIT_WRITE: begin
                    if (avmm_done) begin
                        if (sequence_step == 4'd9) begin
                            lock_timeout <= 32'd0;
                            state        <= WAIT_LOCK;
                        end else if (sequence_step == 4'd10) begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= IDLE;
                        end else begin
                            sequence_step <= sequence_step + 1'b1;
                            state         <= ISSUE_READ;
                        end
                    end
                end

                WAIT_LOCK: begin
                    if (saw_unlock && locked) begin
                        sequence_step <= 4'd10;
                        state         <= ISSUE_READ;
                    end else if (lock_timeout == LOCK_TIMEOUT_CYCLES - 1) begin
                        busy  <= 1'b0;
                        error <= 1'b1;
                        state <= IDLE;
                    end else begin
                        lock_timeout <= lock_timeout + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
