package require qsys 25.1

# Fixed-root clock resources shared by every DE25 MiSTer persona. One
# four-output IOPLL has a Menu power-up profile: system, video, SDRAM output,
# and SDRAM capture. A persona can apply a characterized runtime profile to
# those same four semantic lanes. PC110 uses the lanes as system, video,
# shared UART, and MPU. Each complete image includes this common source block,
# allowing Quartus to place its clock resources for that core's topology.
# The DE25-Nano device has two IOSSM calibration engines; HPS LPDDR4 consumes
# one and this reusable persona PLL uses the other.
create_system de25_core_clock_banks
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance bank0_iopll altera_iopll 21.0.0
set_instance_parameter_value bank0_iopll gui_reference_clock_frequency 50.0
set_instance_parameter_value bank0_iopll gui_number_of_clocks 4
set_instance_parameter_value bank0_iopll gui_output_clock_frequency0 100.0
set_instance_parameter_value bank0_iopll gui_output_clock_frequency1 25.0
set_instance_parameter_value bank0_iopll gui_output_clock_frequency2 100.0
set_instance_parameter_value bank0_iopll gui_phase_shift2 5500.0
set_instance_parameter_value bank0_iopll gui_output_clock_frequency3 100.0
set_instance_parameter_value bank0_iopll gui_phase_shift3 6500.0
set_instance_parameter_value bank0_iopll gui_en_hvio_reconf false
set_instance_parameter_value bank0_iopll gui_en_iossm_reconf true
set_instance_parameter_value bank0_iopll gui_user_base_address 0

add_instance cal_0 emif_ph2_cal 4.3.0
set_instance_parameter_value cal_0 \
    INSTANCE_NAME de25_core_clock_banks_cal_0
set_instance_parameter_value cal_0 NUM_CALBUS_PERIPHS 0
set_instance_parameter_value cal_0 NUM_CALBUS_PLLS 1
set_instance_parameter_value cal_0 PORT_S_AXIL_MODE PORT_S_AXIL_MODE_FAB
add_connection cal_0.calbus_pll_0 bank0_iopll.calbus_pll

foreach signal {s0_axil_clk s0_axil_rst_n s0_axil} {
    add_interface cal_${signal} conduit end
    set_interface_property cal_${signal} EXPORT_OF cal_0.${signal}
}

foreach signal {refclk reset locked outclk0 outclk1} {
    add_interface bank0_${signal} conduit end
    set_interface_property bank0_${signal} EXPORT_OF bank0_iopll.${signal}
}

add_interface bank0_outclk2 conduit end
set_interface_property bank0_outclk2 EXPORT_OF bank0_iopll.outclk2
add_interface bank0_outclk3 conduit end
set_interface_property bank0_outclk3 EXPORT_OF bank0_iopll.outclk3

save_system de25_core_clock_banks.qsys
