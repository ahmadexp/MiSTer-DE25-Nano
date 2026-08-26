package require qsys 25.1

# Native Agilex 5 replacement for PCXT's two Cyclone V PLLs. Output 5 is
# phase shifted by one quarter of a 57.272 MHz period for video retiming.
create_system pcxt_core_pll
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

set video_phase_ps [expr {250000.0 / 57.272}]

add_instance iopll_0 altera_iopll 21.0.0
set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value iopll_0 gui_number_of_clocks 6
set_instance_parameter_value iopll_0 gui_output_clock_frequency0 100.0
set_instance_parameter_value iopll_0 gui_output_clock_frequency1 50.0
set_instance_parameter_value iopll_0 gui_output_clock_frequency2 28.636
set_instance_parameter_value iopll_0 gui_output_clock_frequency3 57.272
set_instance_parameter_value iopll_0 gui_output_clock_frequency4 114.544
set_instance_parameter_value iopll_0 gui_output_clock_frequency5 57.272
set_instance_parameter_value iopll_0 gui_phase_shift5 $video_phase_ps

add_interface refclk clock sink
set_interface_property refclk EXPORT_OF iopll_0.refclk

add_interface reset reset sink
set_interface_property reset EXPORT_OF iopll_0.reset

add_interface locked conduit end
set_interface_property locked EXPORT_OF iopll_0.locked

for {set index 0} {$index < 6} {incr index} {
    add_interface outclk$index clock source
    set_interface_property outclk$index EXPORT_OF iopll_0.outclk$index
}

save_system pcxt_core_pll.qsys
