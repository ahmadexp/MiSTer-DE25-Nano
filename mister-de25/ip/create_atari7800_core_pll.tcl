package require qsys 25.1

create_system atari7800_core_pll
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance iopll_0 altera_iopll 21.0.0
set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value iopll_0 gui_number_of_clocks 5

# The original core asks for 14.318182, 57.272728, and 7.159091 MHz.
# Agilex 5's fabric PLL is integer-only. Use a single exact 1:4:0.5 clock
# family for bring-up so the core never sees slowly drifting clock domains.
# This temporary profile is 0.23 percent slow. The external Si5332 profile
# can later supply the exact 14.318182 MHz reference without changing RTL.
set_instance_parameter_value iopll_0 gui_output_clock_frequency0 14.285714
set_instance_parameter_value iopll_0 gui_output_clock_frequency1 57.142857
set_instance_parameter_value iopll_0 gui_output_clock_frequency2 7.142857

# C3 is the physical SDRAM clock. It preserves the 180 degree relationship
# that the Cyclone V altddio_out generated from clk_vid. C4 captures returning
# DQ 12.75 ns after that SDRAM edge (the following 4 ns phase in the 17.5 ns
# cycle). A falling clk_vid pipeline stage then transfers the sample before
# the controller consumes it on the next rising edge.
set_instance_parameter_value iopll_0 gui_output_clock_frequency3 57.142857
set_instance_parameter_value iopll_0 gui_phase_shift3 8750.0
set_instance_parameter_value iopll_0 gui_output_clock_frequency4 57.142857
set_instance_parameter_value iopll_0 gui_phase_shift4 4000.0

add_interface refclk clock sink
set_interface_property refclk EXPORT_OF iopll_0.refclk
add_interface reset reset sink
set_interface_property reset EXPORT_OF iopll_0.reset
add_interface locked conduit end
set_interface_property locked EXPORT_OF iopll_0.locked
for {set index 0} {$index < 5} {incr index} {
    add_interface outclk$index clock source
    set_interface_property outclk$index EXPORT_OF iopll_0.outclk$index
}

save_system atari7800_core_pll.qsys
