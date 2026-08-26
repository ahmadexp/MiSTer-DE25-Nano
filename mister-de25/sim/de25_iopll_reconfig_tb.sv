`timescale 1ns/1ps

module de25_iopll_reconfig_tb;
    logic clk = 0;
    logic reset = 1;
    logic start = 0;
    logic [31:0] m_settings = 32'h1552_3456;
    logic [31:0] c0_settings = 32'h9238_1122;
    logic [31:0] c1_settings = 32'hA739_3344;
    logic [14:0] charge_pump_settings = 15'h1234;
    logic locked = 1;
    logic busy;
    logic done;
    logic error;
    logic [8:0] core_avl_address;
    logic core_avl_read;
    logic [7:0] core_avl_readdata;
    logic core_avl_write;
    logic [7:0] core_avl_writedata;

    logic [31:0] register_file [0:511];
    logic [31:0] initial_m;
    logic [31:0] initial_c0;
    logic [31:0] initial_c1;
    logic [31:0] initial_cp;
    logic [31:0] initial_enable;
    logic [31:0] initial_status;
    integer index;

    localparam logic [31:0] M_MASK = 32'h9FF3_FFFF;
    localparam logic [31:0] C_MASK = 32'hFFBF_F9FF;

    always #5 clk = ~clk;

    de25_iopll_reconfig #(.LOCK_TIMEOUT_CYCLES(200)) dut (.*);

    // Byte-wide model of the IOPLL register bank. The transport owns the
    // fixed-cycle timing, so the model exposes the addressed byte according
    // to that transport's current cycle.
    always_comb begin
        core_avl_readdata = 8'h00;
        if (core_avl_read) begin
            case (dut.transport.cycle)
                4'd6: core_avl_readdata = register_file[core_avl_address][7:0];
                4'd7: core_avl_readdata = register_file[core_avl_address][15:8];
                4'd8: core_avl_readdata = register_file[core_avl_address][23:16];
                4'd9: core_avl_readdata = register_file[core_avl_address][31:24];
                default: core_avl_readdata = 8'h00;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (core_avl_write) begin
            case (dut.transport.cycle)
                4'd5: register_file[core_avl_address][7:0]   <= core_avl_writedata;
                4'd6: register_file[core_avl_address][15:8]  <= core_avl_writedata;
                4'd7: register_file[core_avl_address][23:16] <= core_avl_writedata;
                4'd8: register_file[core_avl_address][31:24] <= core_avl_writedata;
                default: ;
            endcase
        end
    end

    task automatic check_condition(input logic condition, input string message);
        if (!condition)
            $fatal(1, "FAIL: %s", message);
    endtask

    initial begin
        for (index = 0; index < 512; index = index + 1)
            register_file[index] = 32'hA5A5_5A5A ^ index;

        initial_enable = register_file[9'h010];
        initial_m      = register_file[9'h040];
        initial_cp     = register_file[9'h044];
        initial_c0     = register_file[9'h05C];
        initial_c1     = register_file[9'h060];
        initial_status = register_file[9'h058];
        register_file[9'h058][21] = 1'b1;
        register_file[9'h058][7]  = 1'b1;

        repeat (3) @(posedge clk);
        reset <= 0;
        repeat (2) @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        wait (register_file[9'h080][2]);
        locked <= 0;
        wait (register_file[9'h088][11]);
        repeat (8) @(posedge clk);
        locked <= 1;
        wait (done);
        #1;

        check_condition(!busy && !error, "sequence must complete without timeout");
        check_condition(register_file[9'h010] ==
            (initial_enable | 32'h1), "register access enable RMW");
        check_condition(register_file[9'h058][21] == 0 &&
            register_file[9'h058][7] == 0, "calibration status clear");
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
        check_condition(register_file[9'h080][2] == 0, "PLL reset released");
        check_condition(register_file[9'h048][14] == 0,
            "recalibration enable cleared after completion");
        check_condition(register_file[9'h088][11] == 1,
            "recalibration request issued");

        $display("PASS: Agilex 5 IOPLL complete reconfiguration sequence");
        $finish;
    end
endmodule
