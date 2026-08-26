# The dedicated C4 capture clock follows the C3 forwarded clock in phase.
# Its first edge after a C3 launch deliberately samples the preceding SDRAM
# beat. Pair that launch with the following C4 edge using setup-2/hold-1.
# The Jaguar CAS pipeline then consumes the held word on the next C0 edge.
set de25_jaguar_sdram_dq [get_ports -nowarn {DRAM_DQ[*]}]
set de25_jaguar_sdram_capture_registers [get_keepers -nowarn {
    *|sdram|dq_capture[*]
}]
if {[get_collection_size $de25_jaguar_sdram_dq] > 0 &&
    [get_collection_size $de25_jaguar_sdram_capture_registers] > 0} {
    set_multicycle_path -setup 2 -from $de25_jaguar_sdram_dq \
        -to $de25_jaguar_sdram_capture_registers
    set_multicycle_path -hold 1 -from $de25_jaguar_sdram_dq \
        -to $de25_jaguar_sdram_capture_registers
}

# PLL lock is asynchronous to C0 even though both ultimately derive from the
# same reference pin. Only the first stage is a CDC endpoint; its second stage
# and all SDRAM initialization state remain normally timed in C0.
set de25_jaguar_pll_lock_meta [get_keepers -nowarn {
    core|pll_locked_ram_sync[0]
}]
if {[get_collection_size $de25_jaguar_pll_lock_meta] > 0} {
    set_false_path -to $de25_jaguar_pll_lock_meta
}
