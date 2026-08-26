package require qsys 25.1

# Agilex 5 replacement for Apple-I's Cyclone V PLL. The 6.25 MHz output is
# retained for interface fidelity even though the current core uses 25 MHz.
create_system apple1_core_pll
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance iopll_0 altera_iopll 21.0.0
set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value iopll_0 gui_number_of_clocks 2
set_instance_parameter_value iopll_0 gui_output_clock_frequency0 6.25
set_instance_parameter_value iopll_0 gui_output_clock_frequency1 25.0

add_interface refclk clock sink
set_interface_property refclk EXPORT_OF iopll_0.refclk

add_interface reset reset sink
set_interface_property reset EXPORT_OF iopll_0.reset

add_interface locked conduit end
set_interface_property locked EXPORT_OF iopll_0.locked

add_interface outclk0 clock source
set_interface_property outclk0 EXPORT_OF iopll_0.outclk0

add_interface outclk1 clock source
set_interface_property outclk1 EXPORT_OF iopll_0.outclk1

save_system apple1_core_pll.qsys
