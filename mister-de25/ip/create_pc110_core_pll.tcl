package require qsys 25.1

# PC110 uses six fixed clock domains on DE25-Nano. The 100 MHz HPS fabric and
# 24.576 MHz HDMI audio clocks remain in the common platform PLL.
create_system pc110_core_pll
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance core_iopll altera_iopll 21.0.0
set_instance_parameter_value core_iopll gui_reference_clock_frequency 50.0
set_instance_parameter_value core_iopll gui_number_of_clocks 4
set_instance_parameter_value core_iopll gui_output_clock_frequency0 30.0
set_instance_parameter_value core_iopll gui_output_clock_frequency1 1.8432
set_instance_parameter_value core_iopll gui_output_clock_frequency2 3.0
set_instance_parameter_value core_iopll gui_output_clock_frequency3 1.8432

add_instance vga_iopll altera_iopll 21.0.0
set_instance_parameter_value vga_iopll gui_reference_clock_frequency 50.0
set_instance_parameter_value vga_iopll gui_number_of_clocks 2
# Keep the VGA engine and HDMI scanout on integer-related outputs of one PLL.
# Four engine clocks per 25.173611 MHz pixel avoid phase beating and preserve
# the three-PLL physical topology used by the proven 078A HPS platform.
set_instance_parameter_value vga_iopll gui_output_clock_frequency0 100.701756
set_instance_parameter_value vga_iopll gui_output_clock_frequency1 25.175439

add_interface refclk clock sink
set_interface_property refclk EXPORT_OF core_iopll.refclk
add_interface reset reset sink
set_interface_property reset EXPORT_OF core_iopll.reset
add_interface vga_refclk clock sink
set_interface_property vga_refclk EXPORT_OF vga_iopll.refclk
add_interface vga_reset reset sink
set_interface_property vga_reset EXPORT_OF vga_iopll.reset

add_interface locked conduit end
set_interface_property locked EXPORT_OF core_iopll.locked
add_interface vga_locked conduit end
set_interface_property vga_locked EXPORT_OF vga_iopll.locked

for {set index 0} {$index < 4} {incr index} {
    set interface_name "outclk${index}"
    add_interface $interface_name clock source
    set_interface_property $interface_name EXPORT_OF "core_iopll.${interface_name}"
}
add_interface outclk4 clock source
set_interface_property outclk4 EXPORT_OF vga_iopll.outclk0
add_interface outclk5 clock source
set_interface_property outclk5 EXPORT_OF vga_iopll.outclk1

save_system pc110_core_pll.qsys
