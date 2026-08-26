// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Applies the MemTest frequency profile through the EMIF Calibration IP.
module de25_iopll_reconfig_axil #(
    parameter integer LOCK_TIMEOUT_CYCLES = 1_000_000,
    parameter integer C_COUNTERS = 2
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [31:0] m_settings,
    input  logic [31:0] c0_settings,
    input  logic [31:0] c1_settings,
    input  logic [31:0] c2_settings,
    input  logic [31:0] c3_settings,
    input  logic [31:0] c4_settings,
    input  logic [14:0] charge_pump_settings,
    input  logic        locked,
    output logic        busy,
    output logic        done,
    output logic        error,
    output logic  [4:0] diagnostic_step,
    output logic  [2:0] error_code,
    output logic  [8:0] last_address,
    output logic [31:0] last_read_data,
    output logic [31:0] last_write_data,

    output logic [26:0] axil_awaddr,
    output logic        axil_awvalid,
    input  logic        axil_awready,
    output logic [31:0] axil_wdata,
    output logic  [3:0] axil_wstrb,
    output logic        axil_wvalid,
    input  logic        axil_wready,
    input  logic  [1:0] axil_bresp,
    input  logic        axil_bvalid,
    output logic        axil_bready,
    output logic [26:0] axil_araddr,
    output logic        axil_arvalid,
    input  logic        axil_arready,
    input  logic [31:0] axil_rdata,
    input  logic  [1:0] axil_rresp,
    input  logic        axil_rvalid,
    output logic        axil_rready
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
    logic [4:0] sequence_step;
    logic [31:0] saved_m_settings;
    logic [31:0] saved_c0_settings;
    logic [31:0] saved_c1_settings;
    logic [31:0] saved_c2_settings;
    logic [31:0] saved_c3_settings;
    logic [31:0] saved_c4_settings;
    logic [14:0] saved_charge_pump;
    logic [31:0] rmw_readdata;
    logic [31:0] lock_timeout;
    logic saw_unlock;

    logic transport_start;
    logic transport_write;
    logic [8:0] transport_address;
    logic [31:0] transport_writedata;
    logic [31:0] transport_readdata;
    logic transport_busy;
    logic transport_done;
    logic transport_error;
    logic transport_timeout;

    logic [8:0] step_address;
    logic [31:0] step_mask;
    logic [31:0] step_value;

    localparam integer RESET_ASSERT_STEP = 4 + C_COUNTERS;
    localparam integer RESET_CLEAR_STEP = RESET_ASSERT_STEP + 1;
    localparam integer RECAL_REQUEST_STEP = RESET_ASSERT_STEP + 2;

    localparam logic [2:0] ERROR_NONE = 3'd0;
    localparam logic [2:0] ERROR_READ_RESPONSE = 3'd1;
    localparam logic [2:0] ERROR_WRITE_RESPONSE = 3'd2;
    localparam logic [2:0] ERROR_LOCK_TIMEOUT = 3'd3;
    localparam logic [2:0] ERROR_READ_TIMEOUT = 3'd4;
    localparam logic [2:0] ERROR_WRITE_TIMEOUT = 3'd5;

    assign diagnostic_step = sequence_step;

    function automatic logic [31:0] saved_counter(input integer index);
        case (index)
            0: saved_counter = saved_c0_settings;
            1: saved_counter = saved_c1_settings;
            2: saved_counter = saved_c2_settings;
            3: saved_counter = saved_c3_settings;
            4: saved_counter = saved_c4_settings;
            default: saved_counter = 32'd0;
        endcase
    endfunction

    always_comb begin
        step_address = 9'h000;
        step_mask    = 32'h0000_0000;
        step_value   = 32'h0000_0000;

        case (sequence_step)
            4'd0: begin
                step_address = 9'h010;
                step_mask    = 32'h0000_0001;
                step_value   = 32'h0000_0001;
            end
            4'd1: begin
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
            RESET_ASSERT_STEP: begin
                step_address = 9'h080;
                step_mask    = 32'h0000_0004;
                step_value   = 32'h0000_0004;
            end
            RESET_CLEAR_STEP: begin
                step_address = 9'h080;
                step_mask    = 32'h0000_0004;
            end
            RECAL_REQUEST_STEP: begin
                step_address = 9'h088;
                step_mask    = 32'h0000_0800;
                step_value   = 32'h0000_0800;
            end
            default: begin
                step_address = 9'h000;
                step_mask    = 32'h0000_0000;
            end
        endcase

        if (sequence_step >= 5'd4 && sequence_step < RESET_ASSERT_STEP) begin
            step_address = 9'h05C + ((sequence_step - 5'd4) << 2);
            step_mask    = C_MASK;
            step_value   = saved_counter(sequence_step - 5'd4);
        end
    end

    assign transport_address   = step_address;
    assign transport_writedata = (rmw_readdata & ~step_mask) |
                                 (step_value & step_mask);

    de25_iopll_axil transport (
        .clk,
        .reset,
        .start(transport_start),
        .write_request(transport_write),
        .address(transport_address),
        .writedata(transport_writedata),
        .readdata(transport_readdata),
        .busy(transport_busy),
        .done(transport_done),
        .response_error(transport_error),
        .timeout_error(transport_timeout),
        .axil_awaddr,
        .axil_awvalid,
        .axil_awready,
        .axil_wdata,
        .axil_wstrb,
        .axil_wvalid,
        .axil_wready,
        .axil_bresp,
        .axil_bvalid,
        .axil_bready,
        .axil_araddr,
        .axil_arvalid,
        .axil_arready,
        .axil_rdata,
        .axil_rresp,
        .axil_rvalid,
        .axil_rready
    );

    always_ff @(posedge clk) begin
        transport_start <= 1'b0;
        done            <= 1'b0;

        if (reset) begin
            state              <= IDLE;
            sequence_step      <= 5'd0;
            saved_m_settings   <= 32'd0;
            saved_c0_settings  <= 32'd0;
            saved_c1_settings  <= 32'd0;
            saved_c2_settings  <= 32'd0;
            saved_c3_settings  <= 32'd0;
            saved_c4_settings  <= 32'd0;
            saved_charge_pump  <= 15'd0;
            rmw_readdata       <= 32'd0;
            lock_timeout       <= 32'd0;
            saw_unlock         <= 1'b0;
            transport_write    <= 1'b0;
            busy               <= 1'b0;
            error              <= 1'b0;
            error_code         <= ERROR_NONE;
            last_address       <= 9'd0;
            last_read_data     <= 32'd0;
            last_write_data    <= 32'd0;
        end else begin
            if (busy && !locked)
                saw_unlock <= 1'b1;

            case (state)
                IDLE: begin
                    if (start) begin
                        saved_m_settings  <= m_settings;
                        saved_c0_settings <= c0_settings;
                        saved_c1_settings <= c1_settings;
                        saved_c2_settings <= c2_settings;
                        saved_c3_settings <= c3_settings;
                        saved_c4_settings <= c4_settings;
                        saved_charge_pump <= charge_pump_settings;
                        sequence_step     <= 5'd0;
                        saw_unlock        <= ~locked;
                        error             <= 1'b0;
                        error_code        <= ERROR_NONE;
                        busy              <= 1'b1;
                        state             <= ISSUE_READ;
                    end
                end

                ISSUE_READ: begin
                    if (!transport_busy) begin
                        transport_write <= 1'b0;
                        transport_start <= 1'b1;
                        state           <= WAIT_READ;
                    end
                end

                WAIT_READ: begin
                    if (transport_done) begin
                        last_address   <= step_address;
                        last_read_data <= transport_readdata;
                        if (transport_error) begin
                            busy       <= 1'b0;
                            error      <= 1'b1;
                            error_code <= transport_timeout ? ERROR_READ_TIMEOUT :
                                                              ERROR_READ_RESPONSE;
                            state      <= IDLE;
                        end else begin
                            rmw_readdata <= transport_readdata;
                            state        <= ISSUE_WRITE;
                        end
                    end
                end

                ISSUE_WRITE: begin
                    if (!transport_busy) begin
                        transport_write <= 1'b1;
                        transport_start <= 1'b1;
                        state           <= WAIT_WRITE;
                    end
                end

                WAIT_WRITE: begin
                    if (transport_done) begin
                        last_address    <= step_address;
                        last_write_data <= transport_writedata;
                        if (transport_error) begin
                            busy       <= 1'b0;
                            error      <= 1'b1;
                            error_code <= transport_timeout ? ERROR_WRITE_TIMEOUT :
                                                              ERROR_WRITE_RESPONSE;
                            state      <= IDLE;
                        end else if (sequence_step == RECAL_REQUEST_STEP) begin
                            lock_timeout <= 32'd0;
                            state        <= WAIT_LOCK;
                        end else begin
                            sequence_step <= sequence_step + 1'b1;
                            state         <= ISSUE_READ;
                        end
                    end
                end

                WAIT_LOCK: begin
                    if (saw_unlock && locked) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= IDLE;
                    end else if (lock_timeout == LOCK_TIMEOUT_CYCLES - 1) begin
                        busy       <= 1'b0;
                        error      <= 1'b1;
                        error_code <= ERROR_LOCK_TIMEOUT;
                        state      <= IDLE;
                    end else begin
                        lock_timeout <= lock_timeout + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
