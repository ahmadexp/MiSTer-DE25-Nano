package require qsys 25.1

create_system n64_core_pll
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance iopll_0 altera_iopll 21.0.0
set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value iopll_0 gui_number_of_clocks 4
set_instance_parameter_value iopll_0 gui_output_clock_frequency0 62.5
set_instance_parameter_value iopll_0 gui_output_clock_frequency1 93.75
set_instance_parameter_value iopll_0 gui_phase_shift1 -1777.778
set_instance_parameter_value iopll_0 gui_output_clock_frequency2 125.0
set_instance_parameter_value iopll_0 gui_output_clock_frequency3 62.5
set_instance_parameter_value iopll_0 gui_phase_shift3 11556.0

add_interface refclk clock sink
set_interface_property refclk EXPORT_OF iopll_0.refclk
add_interface reset reset sink
set_interface_property reset EXPORT_OF iopll_0.reset
add_interface locked conduit end
set_interface_property locked EXPORT_OF iopll_0.locked
for {set index 0} {$index < 4} {incr index} {
    add_interface outclk$index clock source
    set_interface_property outclk$index EXPORT_OF iopll_0.outclk$index
}

save_system n64_core_pll.qsys
