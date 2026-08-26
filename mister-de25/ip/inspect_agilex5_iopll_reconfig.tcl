package require qsys 25.1

# Developer diagnostic: print the interfaces exposed by Quartus for the exact
# Agilex 5 device after HVIO IOPLL dynamic reconfiguration is enabled.
create_system inspect_agilex5_iopll_reconfig
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance iopll_0 altera_iopll 21.0.0
set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value iopll_0 gui_number_of_clocks 1
set_instance_parameter_value iopll_0 gui_output_clock_frequency0 100.0
set_instance_parameter_value iopll_0 gui_en_hvio_reconf true

send_message info "IOPLL interfaces: [get_instance_interfaces iopll_0]"

save_system inspect_agilex5_iopll_reconfig.qsys
