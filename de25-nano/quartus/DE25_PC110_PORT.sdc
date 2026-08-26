create_clock -name CLOCK0_50 -period 20.000 [get_ports CLOCK0_50]
create_clock -name HPS_CLK_25 -period 40.000 [get_ports HPS_CLK_25]

# Quartus reads project SDC files before the automatically discovered IP SDC
# files on Agilex 5.  Source the generated IOPLL constraints here so that the
# derived clock objects exist before the clock groups below are evaluated.
set pll_sdc_root [file normalize [file join [file dirname [info script]] .. ip ip pc110_pll]]
foreach pll_sdc [glob -nocomplain \
        [file join $pll_sdc_root * altera_iopll_2100 synth *.sdc]] {
    source $pll_sdc
}

# The PC110 domains use explicit synchronizers, dual-clock RAMs, or the
# Platform Designer clock-crossing bridge.  They must not be timed as a
# synchronous multi-cycle relationship merely because one IOPLL produces
# them all.
set_clock_groups -asynchronous \
    -group [get_clocks {CLOCK0_50}] \
    -group [get_clocks {*|iopll_0|iopll_0_outclk0}] \
    -group [get_clocks {*|iopll_0|iopll_0_outclk1}] \
    -group [get_clocks {*|iopll_0|iopll_0_outclk2}] \
    -group [get_clocks {*|iopll_0|iopll_0_outclk3}] \
    -group [get_clocks {*|vga_iopll_0|vga_iopll_0_outclk0}] \
    -group [get_clocks {*|hps_iopll_0|hps_iopll_0_outclk0}]

# HPS reset-manager outputs and PLL lock are asynchronous reset sources.
# Their deassertion is synchronized by reset controllers in Platform
# Designer and by core_reset_pipe in the board top.
set_false_path -from [get_keepers {*sundancemesa_hps_inst~intosc_clk.reg}]
set_false_path -from [get_keepers {*core_reset_pipe*}]

set_false_path -from [get_ports {KEY[*]}]
set_false_path -from [get_ports {SW[*]}]
set_false_path -from [get_ports FPGA_UART_RX]
set_false_path -from [get_ports HPS_ENET_RX_CTL]
set_false_path -from [get_ports HPS_USB_DIR]
set_false_path -from [get_ports HPS_USB_NXT]
set_false_path -from [get_ports HDMI_TX_INT]
set_false_path -to [get_ports {LED[*]}]
set_false_path -to [get_ports FPGA_UART_TX]

derive_clock_uncertainty
