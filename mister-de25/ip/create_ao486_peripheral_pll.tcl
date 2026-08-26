package require qsys 25.1

# Native Agilex 5 source for ao486's fixed UART, MPU, and VGA base clocks.
# Keep these ordinary IOPLLs outside the IOSSM-calibrated CPU clock system.
# Agilex 5 IOPLL core outputs bottom out near 6.2 MHz, so the legacy 1.84 MHz
# UART and 3 MHz MPU clocks are divided from legal base clocks in the wrapper.
create_system ao486_peripheral_pll
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance peripheral_pll altera_iopll 21.0.0
set_instance_parameter_value peripheral_pll gui_reference_clock_frequency 50.0
set_instance_parameter_value peripheral_pll gui_number_of_clocks 2
# Let Quartus choose a legal Agilex 5 VCO operating point. Forcing the legacy
# arithmetic VCO causes the generated IP to round it silently, after which the
# fitter rejects the otherwise connected output clocks.
set_instance_parameter_value peripheral_pll gui_output_clock_frequency0 49.548387
set_instance_parameter_value peripheral_pll gui_output_clock_frequency1 48.0

add_instance video_pll altera_iopll 21.0.0
set_instance_parameter_value video_pll gui_reference_clock_frequency 50.0
set_instance_parameter_value video_pll gui_number_of_clocks 2
# The second output is divided by four for the 1.844262 MHz legacy UART clock.
set_instance_parameter_value video_pll gui_output_clock_frequency0 90.0
set_instance_parameter_value video_pll gui_output_clock_frequency1 7.377049

add_interface peripheral_refclk clock sink
set_interface_property peripheral_refclk EXPORT_OF peripheral_pll.refclk

add_interface peripheral_reset reset sink
set_interface_property peripheral_reset EXPORT_OF peripheral_pll.reset

add_interface peripheral_locked conduit end
set_interface_property peripheral_locked EXPORT_OF peripheral_pll.locked

add_interface video_refclk clock sink
set_interface_property video_refclk EXPORT_OF video_pll.refclk

add_interface video_reset reset sink
set_interface_property video_reset EXPORT_OF video_pll.reset

add_interface video_locked conduit end
set_interface_property video_locked EXPORT_OF video_pll.locked

foreach {name export_of} {
    uart_fast_outclk peripheral_pll.outclk0
    mpu_base_outclk  peripheral_pll.outclk1
    vga_outclk       video_pll.outclk0
    uart_base_outclk video_pll.outclk1
} {
    add_interface $name clock source
    set_interface_property $name EXPORT_OF $export_of
}

save_system ao486_peripheral_pll.qsys
