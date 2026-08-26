package require qsys 25.1

create_system n64_video_pll
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance iopll_0 altera_iopll 21.0.0
set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value iopll_0 gui_number_of_clocks 1
set_instance_parameter_value iopll_0 gui_output_clock_frequency0 48.68

add_interface refclk clock sink
set_interface_property refclk EXPORT_OF iopll_0.refclk
add_interface reset reset sink
set_interface_property reset EXPORT_OF iopll_0.reset
add_interface locked conduit end
set_interface_property locked EXPORT_OF iopll_0.locked
add_interface outclk0 clock source
set_interface_property outclk0 EXPORT_OF iopll_0.outclk0

save_system n64_video_pll.qsys
