package require qsys 25.1

# Persona-local MiSTer DDRAM clock crossing. The core controls the s0 clock;
# the reusable root boundary and the HPS-facing m0 side always run at 100 MHz.
# Keeping this IP below de25_mister_core prevents persona clocks from entering
# the fixed HPS hierarchy of the root partition.
create_system de25_ddram_cdc
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance cdc altera_avalon_mm_clock_crossing_bridge 19.4.0
set_instance_parameter_value cdc DATA_WIDTH 64
set_instance_parameter_value cdc SYMBOL_WIDTH 8
set_instance_parameter_value cdc ADDRESS_UNITS SYMBOLS
set_instance_parameter_value cdc ADDRESS_WIDTH 29
set_instance_parameter_value cdc HDL_ADDR_WIDTH 29
set_instance_parameter_value cdc USE_AUTO_ADDRESS_WIDTH 0
set_instance_parameter_value cdc MAX_BURST_SIZE 128
set_instance_parameter_value cdc COMMAND_FIFO_DEPTH 32
set_instance_parameter_value cdc RESPONSE_FIFO_DEPTH 256
set_instance_parameter_value cdc MASTER_SYNC_DEPTH 3
set_instance_parameter_value cdc SLAVE_SYNC_DEPTH 3
set_instance_parameter_value cdc PIPELINE_ENABLE 1
set_instance_parameter_value cdc SYNC_RESET 1

add_interface core avalon slave
set_interface_property core EXPORT_OF cdc.s0
add_interface core_clk clock sink
set_interface_property core_clk EXPORT_OF cdc.s0_clk
add_interface core_reset reset sink
set_interface_property core_reset EXPORT_OF cdc.s0_reset

add_interface root avalon master
set_interface_property root EXPORT_OF cdc.m0
add_interface root_clk clock sink
set_interface_property root_clk EXPORT_OF cdc.m0_clk
add_interface root_reset reset sink
set_interface_property root_reset EXPORT_OF cdc.m0_reset

save_system de25_ddram_cdc.qsys
