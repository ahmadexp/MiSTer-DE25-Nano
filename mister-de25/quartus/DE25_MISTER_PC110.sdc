set pc110_sdc_root [file normalize [file join [file dirname [info script]] .. ip ip pc110_core_pll]]
foreach pc110_pll_sdc [glob -nocomplain \
        [file join $pc110_sdc_root * altera_iopll_2100 synth *.sdc]] {
    source $pc110_pll_sdc
}

# PC110 moves control and data only through explicit synchronizers,
# dual-clock RAMs, or the Platform Designer DDR clock crossing bridge.  The
# platform PLL IP may create the board-reference clock before the shared SDC
# can name it CLOCK0_50, so select that clock by its source port instead of by
# a name which Quartus is then free to replace with the IP-generated name.
set pc110_async_clock_groups {}
set pc110_ref_clock [get_clocks -nowarn -of_objects [get_ports CLOCK0_50]]
if {[get_collection_size $pc110_ref_clock] > 0} {
    lappend pc110_async_clock_groups $pc110_ref_clock
}
set pc110_jtag_clock \
    [get_clocks -nowarn -of_objects [get_ports altera_reserved_tck]]
if {[get_collection_size $pc110_jtag_clock] > 0} {
    lappend pc110_async_clock_groups $pc110_jtag_clock
}
foreach pc110_clock_pattern {
    {*|system_pll|*outclk0}
    {*|system_pll|*outclk1}
    {*|system_pll|*outclk2}
    {*|core_iopll|core_iopll_outclk0}
    {*|core_iopll|core_iopll_outclk1}
    {*|core_iopll|core_iopll_outclk2}
    {*|core_iopll|core_iopll_outclk3}
    {*|vga_iopll|vga_iopll_outclk0}
    {*|vga_iopll|vga_iopll_outclk1}
} {
    set pc110_clock_group [get_clocks -nowarn $pc110_clock_pattern]
    if {[get_collection_size $pc110_clock_group] > 0} {
        lappend pc110_async_clock_groups $pc110_clock_group
    }
}
# Required non-JTAG domains: board reference, two platform clocks, four core
# clocks, the VGA clock, and the phase-related scanout clock.  outclk2 is accepted
# above for compatibility with older platform PLL generation but is optional.
set pc110_expected_clock_groups 9
if {[get_collection_size $pc110_jtag_clock] > 0} {
    incr pc110_expected_clock_groups
}
if {[llength $pc110_async_clock_groups] < $pc110_expected_clock_groups} {
    post_message -type error \
        "PC110 timing constraints did not resolve all required clock domains"
} else {
    set pc110_clock_group_command [list set_clock_groups -asynchronous]
    foreach pc110_clock_group $pc110_async_clock_groups {
        lappend pc110_clock_group_command -group $pc110_clock_group
    }
    eval $pc110_clock_group_command
}

# The optional Si5332B probe is a self-timed 25 kHz open-drain bus. Its input
# pins enter explicit two-register synchronizers, and its output transitions
# are protocol-timed by the 50 MHz state machine rather than an external
# synchronous receiver. They therefore have no board-level setup/hold delay.
set_false_path -from [get_ports {SI5332_SCL SI5332_SDA}]
set_false_path -to   [get_ports {SI5332_SCL SI5332_SDA}]
