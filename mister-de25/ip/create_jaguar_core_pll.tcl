package require qsys 25.1

create_system jaguar_core_pll
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance iopll_0 altera_iopll 21.0.0
set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value iopll_0 gui_number_of_clocks 5

# The stock core uses 106.363636, 26.590909, and 53.181818 MHz, an exact
# 4:1:2 family. A 50 MHz integer IOPLL can produce the exact 106.25,
# 26.5625, and 53.125 MHz family. It is 0.107 percent slow but preserves
# every clock relationship until an exact Si5332 reference is available.
set_instance_parameter_value iopll_0 gui_output_clock_frequency0 106.250000
set_instance_parameter_value iopll_0 gui_output_clock_frequency1 26.562500
set_instance_parameter_value iopll_0 gui_output_clock_frequency2 53.125000

# C3 replaces the Cyclone V DDR output primitive with a dedicated,
# phase-related clock for the SDRAM pin. C4 captures each returned word one
# controller period plus 2 ns after its SDRAM launch edge. The existing CAS
# pipeline consumes that held word on the following controller edge. This
# gives the -6 SDRAM and the FPGA input path their full timing allowance
# without reducing one-word-per-cycle burst throughput.
set_instance_parameter_value iopll_0 gui_output_clock_frequency3 106.250000
set_instance_parameter_value iopll_0 gui_phase_shift3 5500.0
set_instance_parameter_value iopll_0 gui_output_clock_frequency4 106.250000
set_instance_parameter_value iopll_0 gui_phase_shift4 7500.0

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

save_system jaguar_core_pll.qsys
