package require qsys 25.1

# Start from Terasic's rev-B GHRD so the HPS, LPDDR4, SD, USB, Ethernet,
# and boot handoff remain identical to the supported board image.  Work on a
# generated copy so the imported reference remains pristine.
set source_system ../vendor/terasic-ghrd/qsys_top.qsys
set output_system ../vendor/terasic-ghrd/pc110_hps.qsys
file copy -force $source_system $output_system
load_system $output_system

# The GHRD's 256 KiB FPGA on-chip memory is only a debug scratchpad.  It is
# not the HPS OCRAM and the PC110 port does not map or use it.  Retaining it
# costs roughly 104 M20Ks, which prevents the complete VGA core from fitting
# in the DE25-Nano's A5E-B013 device.
remove_connection clk_100.out_clk/ocm.clk1
remove_connection rst_in.out_reset/ocm.reset1
remove_connection subsys_debug.fpga_m_master/ocm.axi_s1
remove_connection subsys_hps.hps2fpga/ocm.axi_s1
remove_instance ocm

# Export a 64-bit Avalon-MM subordinate that the PC110 core can use as its DDR
# backing store.  The clock-crossing bridge transfers requests from the 30 MHz
# core domain into the official 100 MHz HPS fabric.  Platform Designer then
# adapts the 64-bit Avalon transactions to the HPS 256-bit FPGA-to-SDRAM AXI
# interface.
add_instance pc110_mem_cdc altera_avalon_mm_clock_crossing_bridge 19.4.0
set_instance_parameter_value pc110_mem_cdc DATA_WIDTH 64
set_instance_parameter_value pc110_mem_cdc SYMBOL_WIDTH 8
set_instance_parameter_value pc110_mem_cdc ADDRESS_UNITS SYMBOLS
set_instance_parameter_value pc110_mem_cdc ADDRESS_WIDTH 32
set_instance_parameter_value pc110_mem_cdc HDL_ADDR_WIDTH 32
set_instance_parameter_value pc110_mem_cdc USE_AUTO_ADDRESS_WIDTH 0
set_instance_parameter_value pc110_mem_cdc MAX_BURST_SIZE 128
set_instance_parameter_value pc110_mem_cdc COMMAND_FIFO_DEPTH 32
set_instance_parameter_value pc110_mem_cdc RESPONSE_FIFO_DEPTH 256
set_instance_parameter_value pc110_mem_cdc MASTER_SYNC_DEPTH 3
set_instance_parameter_value pc110_mem_cdc SLAVE_SYNC_DEPTH 3
set_instance_parameter_value pc110_mem_cdc PIPELINE_ENABLE 1
set_instance_parameter_value pc110_mem_cdc SYNC_RESET 1

add_connection clk_100.out_clk pc110_mem_cdc.m0_clk
add_connection rst_in.out_reset pc110_mem_cdc.m0_reset
add_connection pc110_mem_cdc.m0 subsys_hps.f2sdram_adapter_axi4_sub
set_connection_parameter_value \
    pc110_mem_cdc.m0/subsys_hps.f2sdram_adapter_axi4_sub baseAddress 0x00000000

add_interface pc110_mem avalon slave
set_interface_property pc110_mem EXPORT_OF pc110_mem_cdc.s0

add_interface pc110_clk clock sink
set_interface_property pc110_clk EXPORT_OF pc110_mem_cdc.s0_clk

add_interface pc110_reset reset sink
set_interface_property pc110_reset EXPORT_OF pc110_mem_cdc.s0_reset

save_system
