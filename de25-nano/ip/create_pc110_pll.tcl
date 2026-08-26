package require qsys 25.1

# Generate the fixed PC110 clock domains from the DE25-Nano's 50 MHz CLOCK0
# oscillator.  The system/UART/MPU clocks share one IOPLL.  Independent
# IOPLLs supply the 90 MHz VGA engine and 100 MHz HPS fabric clocks so those
# exact frequencies cannot be perturbed by the UART baud-clock ratio.  The
# OPL model uses the board's 50 MHz oscillator directly in the board top.
create_system pc110_pll
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance iopll_0 altera_iopll 21.0.0
set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value iopll_0 gui_number_of_clocks 4
set_instance_parameter_value iopll_0 gui_output_clock_frequency0 30.0
set_instance_parameter_value iopll_0 gui_output_clock_frequency1 1.8432
set_instance_parameter_value iopll_0 gui_output_clock_frequency2 3.0
set_instance_parameter_value iopll_0 gui_output_clock_frequency3 1.8432

add_instance vga_iopll_0 altera_iopll 21.0.0
set_instance_parameter_value vga_iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value vga_iopll_0 gui_number_of_clocks 1
set_instance_parameter_value vga_iopll_0 gui_output_clock_frequency0 90.0

add_instance hps_iopll_0 altera_iopll 21.0.0
set_instance_parameter_value hps_iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value hps_iopll_0 gui_number_of_clocks 1
set_instance_parameter_value hps_iopll_0 gui_output_clock_frequency0 100.0

add_interface refclk clock sink
set_interface_property refclk EXPORT_OF iopll_0.refclk

add_interface reset reset sink
set_interface_property reset EXPORT_OF iopll_0.reset

add_interface hps_refclk clock sink
set_interface_property hps_refclk EXPORT_OF hps_iopll_0.refclk

add_interface hps_reset reset sink
set_interface_property hps_reset EXPORT_OF hps_iopll_0.reset

add_interface vga_refclk clock sink
set_interface_property vga_refclk EXPORT_OF vga_iopll_0.refclk

add_interface vga_reset reset sink
set_interface_property vga_reset EXPORT_OF vga_iopll_0.reset

add_interface locked conduit end
set_interface_property locked EXPORT_OF iopll_0.locked

add_interface hps_locked conduit end
set_interface_property hps_locked EXPORT_OF hps_iopll_0.locked

add_interface vga_locked conduit end
set_interface_property vga_locked EXPORT_OF vga_iopll_0.locked

for {set index 0} {$index < 3} {incr index} {
    set interface_name "outclk${index}"
    add_interface $interface_name clock source
    set_interface_property $interface_name EXPORT_OF "iopll_0.${interface_name}"
}

add_interface outclk4 clock source
set_interface_property outclk4 EXPORT_OF vga_iopll_0.outclk0

add_interface outclk5 clock source
set_interface_property outclk5 EXPORT_OF iopll_0.outclk3

add_interface outclk6 clock source
set_interface_property outclk6 EXPORT_OF hps_iopll_0.outclk0

save_system pc110_pll.qsys
