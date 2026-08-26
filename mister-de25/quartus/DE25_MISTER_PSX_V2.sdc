# C4 is 5 ns later than the forwarded C3 clock in the PLL cycle. The C4 edge
# immediately following a C3 edge is too early for that edge's returned data;
# it captures the preceding SDRAM beat. Pair each C3 launch with the next C4
# edge, 15 ns later, using the conventional setup-2/hold-1 constraint. A
# falling-edge C2 stage then pipelines dq_reg before the delayed data_ready
# sequence consumes it on rising C2 edges.
set de25_psx_sdram_dq [get_ports -nowarn {DRAM_DQ[*]}]
set de25_psx_sdram_capture_registers [get_keepers -nowarn {
    *|sdram|dq_reg[*]
}]
if {[get_collection_size $de25_psx_sdram_dq] > 0 &&
    [get_collection_size $de25_psx_sdram_capture_registers] > 0} {
    set_multicycle_path -setup 2 -from $de25_psx_sdram_dq \
        -to $de25_psx_sdram_capture_registers
    set_multicycle_path -hold 1 -from $de25_psx_sdram_dq \
        -to $de25_psx_sdram_capture_registers
}
