`timescale 1ns/1ps

// Hardware gate for the Agilex replacement of the MiSTer Cyclone V PLL.
// Each output drives an independently clocked heartbeat so all six domains
// can be observed without routing internal clocks to board pins.
module de25_pc110_clocks (
    input  logic       CLOCK0_50,
    input  logic [1:0] KEY,
    output logic [7:0] LED
);

    logic ninit_done;
    logic pll_locked;
    logic clk_sys;
    logic clk_uart1;
    logic clk_mpu;
    logic clk_opl;
    logic clk_vga;
    logic clk_uart2;

    logic [25:0] count_sys   = '0;
    logic [20:0] count_uart1 = '0;
    logic [21:0] count_mpu   = '0;
    logic [25:0] count_opl   = '0;
    logic [24:0] count_vga   = '0;
    logic [26:0] count_uart2 = '0;

    wire pll_reset = !KEY[0] || ninit_done;

    ResetRelease reset_release (
        .ninit_done(ninit_done)
    );

    pc110_pll clocks (
        .refclk_clk(CLOCK0_50),
        .locked_export(pll_locked),
        .reset_reset(pll_reset),
        .outclk0_clk(clk_sys),
        .outclk1_clk(clk_uart1),
        .outclk2_clk(clk_mpu),
        .outclk3_clk(clk_opl),
        .outclk4_clk(clk_vga),
        .outclk5_clk(clk_uart2)
    );

    always_ff @(posedge clk_sys)
        if (!pll_locked) count_sys <= '0;
        else count_sys <= count_sys + 1'b1;

    always_ff @(posedge clk_uart1)
        if (!pll_locked) count_uart1 <= '0;
        else count_uart1 <= count_uart1 + 1'b1;

    always_ff @(posedge clk_mpu)
        if (!pll_locked) count_mpu <= '0;
        else count_mpu <= count_mpu + 1'b1;

    always_ff @(posedge clk_opl)
        if (!pll_locked) count_opl <= '0;
        else count_opl <= count_opl + 1'b1;

    always_ff @(posedge clk_vga)
        if (!pll_locked) count_vga <= '0;
        else count_vga <= count_vga + 1'b1;

    always_ff @(posedge clk_uart2)
        if (!pll_locked) count_uart2 <= '0;
        else count_uart2 <= count_uart2 + 1'b1;

    always_comb begin
        LED[0] = pll_locked;
        LED[1] = count_sys[25];
        LED[2] = count_uart1[20];
        LED[3] = count_mpu[21];
        LED[4] = count_opl[25];
        LED[5] = count_vga[24];
        LED[6] = count_uart2[26];
        LED[7] = !ninit_done;
    end

endmodule
