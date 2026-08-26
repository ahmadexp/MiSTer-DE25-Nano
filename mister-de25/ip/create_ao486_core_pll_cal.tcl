package require qsys 25.1

# ao486 needs a runtime-selectable CPU clock, but its peripheral clocks must
# not move when that profile changes. The first IOPLL is reconfigured through
# the supported IOSSM Calibration IP path. Fixed peripheral clocks live in a
# separate Platform Designer system so this system contains only calibrated
# clock resources.
create_system ao486_core_pll_cal
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance cpu_pll altera_iopll 21.0.0
set_instance_parameter_value cpu_pll gui_reference_clock_frequency 50.0
set_instance_parameter_value cpu_pll gui_number_of_clocks 2
set_instance_parameter_value cpu_pll gui_output_clock_frequency0 90.0
# GUS commands and write data launch on C0. C1 forwards the same frequency to
# the board SDRAM near the middle of the cycle, with 2 ns reserved for the
# SDRAM read-data return path before the following C0 edge.
set_instance_parameter_value cpu_pll gui_output_clock_frequency1 90.0
set_instance_parameter_value cpu_pll gui_phase_shift1 \
    [expr {500000.0 / 90.0 - 2000.0}]
set_instance_parameter_value cpu_pll gui_en_hvio_reconf false
set_instance_parameter_value cpu_pll gui_en_iossm_reconf true
set_instance_parameter_value cpu_pll gui_user_base_address 0

add_instance cal_0 emif_ph2_cal 4.3.0
set_instance_parameter_value cal_0 INSTANCE_NAME ao486_core_pll_cal_cal_0
set_instance_parameter_value cal_0 NUM_CALBUS_PERIPHS 0
set_instance_parameter_value cal_0 NUM_CALBUS_PLLS 1
set_instance_parameter_value cal_0 PORT_S_AXIL_MODE PORT_S_AXIL_MODE_FAB
add_connection cal_0.calbus_pll_0 cpu_pll.calbus_pll

foreach {name export_of} {
    refclk            cpu_pll.refclk
    cpu_reset         cpu_pll.reset
    cpu_locked        cpu_pll.locked
    cpu_outclk        cpu_pll.outclk0
    cpu_sdram_outclk  cpu_pll.outclk1
    s0_axil_clk       cal_0.s0_axil_clk
    s0_axil_rst_n     cal_0.s0_axil_rst_n
    s0_axil           cal_0.s0_axil
} {
    add_interface $name conduit end
    set_interface_property $name EXPORT_OF $export_of
}

save_system ao486_core_pll_cal.qsys
