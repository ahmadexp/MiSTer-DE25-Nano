package require qsys 25.1

create_system memtest_core_pll_cal
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance iopll_0 altera_iopll 21.0.0
set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value iopll_0 gui_number_of_clocks 2
set_instance_parameter_value iopll_0 gui_output_clock_frequency0 80.0
set_instance_parameter_value iopll_0 gui_output_clock_frequency1 80.0
set_instance_parameter_value iopll_0 gui_phase_shift1 5750.0
set_instance_parameter_value iopll_0 gui_en_hvio_reconf false
set_instance_parameter_value iopll_0 gui_en_iossm_reconf true
set_instance_parameter_value iopll_0 gui_user_base_address 0

add_instance cal_0 emif_ph2_cal 4.3.0
set_instance_parameter_value cal_0 INSTANCE_NAME memtest_core_pll_cal_cal_0
set_instance_parameter_value cal_0 NUM_CALBUS_PERIPHS 0
set_instance_parameter_value cal_0 NUM_CALBUS_PLLS 1
set_instance_parameter_value cal_0 PORT_S_AXIL_MODE PORT_S_AXIL_MODE_FAB

add_connection cal_0.calbus_pll_0 iopll_0.calbus_pll

foreach {name export_of} {
    refclk       iopll_0.refclk
    reset        iopll_0.reset
    locked       iopll_0.locked
    outclk0      iopll_0.outclk0
    outclk1      iopll_0.outclk1
    s0_axil_clk  cal_0.s0_axil_clk
    s0_axil_rst_n cal_0.s0_axil_rst_n
    s0_axil      cal_0.s0_axil
} {
    add_interface $name conduit end
    set_interface_property $name EXPORT_OF $export_of
}

save_system memtest_core_pll_cal.qsys
