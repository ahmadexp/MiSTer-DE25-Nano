`timescale 1ns/1ps

module de25_iopll_reconfig_axil_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic [31:0] m_settings = 32'h1552_3456;
    logic [31:0] c0_settings = 32'h9238_1122;
    logic [31:0] c1_settings = 32'hA739_3344;
    logic [31:0] c2_settings = 32'hB73A_5566;
    logic [31:0] c3_settings = 32'hC73B_7788;
    logic [31:0] c4_settings = 32'hD73C_99AA;
    logic [14:0] charge_pump_settings = 15'h1234;
    logic locked = 1'b1;
    logic busy;
    logic done;
    logic error;
    logic [4:0] diagnostic_step;
    logic [2:0] error_code;
    logic [8:0] last_address;
    logic [31:0] last_read_data;
    logic [31:0] last_write_data;

    logic [26:0] axil_awaddr;
    logic axil_awvalid;
    logic axil_awready = 1'b1;
    logic [31:0] axil_wdata;
    logic [3:0] axil_wstrb;
    logic axil_wvalid;
    logic axil_wready = 1'b1;
    logic [1:0] axil_bresp = 2'b00;
    logic axil_bvalid = 1'b0;
    logic axil_bready;
    logic [26:0] axil_araddr;
    logic axil_arvalid;
    logic axil_arready = 1'b1;
    logic [31:0] axil_rdata = 32'd0;
    logic [1:0] axil_rresp = 2'b00;
    logic axil_rvalid = 1'b0;
    logic axil_rready;

    logic [31:0] register_file [0:511];
    logic [31:0] initial_enable;
    logic [31:0] initial_status;
    logic [31:0] initial_recal_enable;
    logic [31:0] initial_m;
    logic [31:0] initial_cp;
    logic [31:0] initial_c0;
    logic [31:0] initial_c1;
    logic [31:0] initial_c2;
    logic [31:0] initial_c3;
    logic [31:0] initial_c4;
    integer index;

    localparam logic [31:0] M_MASK = 32'h9FF3_FFFF;
    localparam logic [31:0] C_MASK = 32'hFFBF_F9FF;

    always #5 clk = ~clk;

    de25_iopll_reconfig_axil #(
        .LOCK_TIMEOUT_CYCLES(200),
        .C_COUNTERS(5)
    ) dut (
        .clk,
        .reset,
        .start,
        .m_settings,
        .c0_settings,
        .c1_settings,
        .c2_settings,
        .c3_settings,
        .c4_settings,
        .charge_pump_settings,
        .locked,
        .busy,
        .done,
        .error,
        .diagnostic_step,
        .error_code,
        .last_address,
        .last_read_data,
        .last_write_data,
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

    // Always-ready AXI-Lite register model for the Calibration IP aperture.
    always_ff @(posedge clk) begin
        if (reset) begin
            axil_bvalid <= 1'b0;
            axil_rvalid <= 1'b0;
            axil_rdata  <= 32'd0;
        end else begin
            if (axil_bvalid && axil_bready)
                axil_bvalid <= 1'b0;
            if (axil_awvalid && axil_awready &&
                axil_wvalid && axil_wready) begin
                if (axil_wstrb != 4'hF)
                    $fatal(1, "unexpected partial AXI-Lite write");
                register_file[axil_awaddr[8:0]] <= axil_wdata;
                axil_bvalid <= 1'b1;
            end

            if (axil_rvalid && axil_rready)
                axil_rvalid <= 1'b0;
            if (axil_arvalid && axil_arready) begin
                axil_rdata  <= register_file[axil_araddr[8:0]];
                axil_rvalid <= 1'b1;
            end
        end
    end

    task automatic check_condition(input logic condition, input string message);
        if (!condition)
            $fatal(1, "FAIL: %s", message);
    endtask

    initial begin
        for (index = 0; index < 512; index = index + 1)
            register_file[index] = 32'h5AA5_A55A ^ index;

        register_file[9'h048][14] = 1'b0;
        register_file[9'h058][21] = 1'b1;
        register_file[9'h058][7]  = 1'b1;
        register_file[9'h080][2]  = 1'b0;
        register_file[9'h088][11] = 1'b0;

        initial_enable = register_file[9'h010];
        initial_m      = register_file[9'h040];
        initial_cp     = register_file[9'h044];
        initial_c0     = register_file[9'h05C];
        initial_c1     = register_file[9'h060];
        initial_c2     = register_file[9'h064];
        initial_c3     = register_file[9'h068];
        initial_c4     = register_file[9'h06C];
        initial_status = register_file[9'h058];
        initial_recal_enable = register_file[9'h048];

        repeat (3) @(posedge clk);
        reset <= 1'b0;
        repeat (2) @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait (register_file[9'h080][2]);
        locked <= 1'b0;
        wait (register_file[9'h088][11]);
        repeat (8) @(posedge clk);
        locked <= 1'b1;
        wait (done);
        #1;

        check_condition(!busy && !error, "sequence must complete");
        check_condition(error_code == 3'd0, "successful sequence has no error code");
        check_condition(register_file[9'h010] ==
            (initial_enable | 32'h1), "register access enable RMW");
        check_condition(register_file[9'h058] ==
            (initial_status & ~32'h0020_0080), "calibration status clear");
        check_condition(register_file[9'h040] ==
            ((initial_m & ~M_MASK) | (m_settings & M_MASK)), "M counter RMW");
        check_condition(register_file[9'h044] ==
            ((initial_cp & ~32'h0000_FFFE) |
             ({16'd0, charge_pump_settings, 1'b0} & 32'h0000_FFFE)),
            "charge pump RMW");
        check_condition(register_file[9'h05C] ==
            ((initial_c0 & ~C_MASK) | (c0_settings & C_MASK)), "C0 RMW");
        check_condition(register_file[9'h060] ==
            ((initial_c1 & ~C_MASK) | (c1_settings & C_MASK)), "C1 RMW");
        check_condition(register_file[9'h064] ==
            ((initial_c2 & ~C_MASK) | (c2_settings & C_MASK)), "C2 RMW");
        check_condition(register_file[9'h068] ==
            ((initial_c3 & ~C_MASK) | (c3_settings & C_MASK)), "C3 RMW");
        check_condition(register_file[9'h06C] ==
            ((initial_c4 & ~C_MASK) | (c4_settings & C_MASK)), "C4 RMW");
        check_condition(!register_file[9'h080][2], "PLL reset released");
        check_condition(register_file[9'h048] == initial_recal_enable,
            "HSIO flow must not access HVIO recalibration-enable register");
        check_condition(register_file[9'h088][11],
            "recalibration request issued");
        check_condition(diagnostic_step == 5'd11,
            "diagnostic step identifies the HSIO recalibration request");
        check_condition(last_address == 9'h088,
            "last transaction identifies the recalibration request");

        $display("PASS: Agilex 5 IOPLL reconfiguration through EMIF AXI-Lite");
        $finish;
    end
endmodule
