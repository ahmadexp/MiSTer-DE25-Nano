package require qsys 25.1

create_system psx_core_pll
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance iopll_0 altera_iopll 21.0.0
set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value iopll_0 gui_number_of_clocks 5
# Agilex 5 uses integer PLL output counters. Asking it to approximate the
# three nominal PSX clocks independently produces 33.866667, 66.842105, and
# 101.600000 MHz, which are not harmonic and eventually create near-coincident
# edges between domains. Until the Si5332 profile controller supplies the
# exact 33.8688 MHz reference, use one exact 1:2:3 integer family. This is a
# 1.58 percent slow bring-up profile but preserves the core's clock contract.
set_instance_parameter_value iopll_0 gui_output_clock_frequency0 33.333333
set_instance_parameter_value iopll_0 gui_output_clock_frequency1 66.666667
# The official Cyclone V implementation's generated pll_0002.v uses zero
# phase for C1. The stale -60 degree GUI metadata in pll.v does not describe
# the generated hardware and creates a false 2.5 ns 2x-to-1x relationship.
set_instance_parameter_value iopll_0 gui_phase_shift1 0.0
set_instance_parameter_value iopll_0 gui_output_clock_frequency2 100.000000
# C3 replaces the removed altddio_out forwarded SDRAM clock. The board's
# forwarded-clock output path plus SDRAM tAC places returning data after the
# next nominal engine edge. Put C4 5 ns after C3 so a normal fabric input
# register has enough round-trip margin. A falling-edge C2 pipeline stage then
# transfers each word before rising-edge controller consumption. The PSX-local
# SDC pairs the external C3/C4 edges with a setup-2/hold-1 constraint. Both
# clocks remain exact harmonics of the 100 MHz engine.
set_instance_parameter_value iopll_0 gui_output_clock_frequency3 100.000000
set_instance_parameter_value iopll_0 gui_phase_shift3 4750.0
set_instance_parameter_value iopll_0 gui_output_clock_frequency4 100.000000
set_instance_parameter_value iopll_0 gui_phase_shift4 9750.0

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

save_system psx_core_pll.qsys
