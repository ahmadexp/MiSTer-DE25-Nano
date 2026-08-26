# N64 forwards PLL C3 to the 62.5 MHz SDRAM while its controller runs on C0.
# C3 is shifted 11.556 ns from C0, matching the official Cyclone V project.
# Use C3 itself for the board-interface requirements so TimeQuest evaluates
# the reference clock at the physical DRAM_CLK pin.
set de25_n64_sdram_clock [get_clocks -nowarn {
    core|pll|impl|iopll_0|iopll_0_outclk3
}]
set de25_n64_sdram_clock_port [get_ports -nowarn DRAM_CLK]
set de25_n64_sdram_dq [get_ports -nowarn {DRAM_DQ[*]}]
set de25_n64_sdram_outputs [get_ports -nowarn {
    DRAM_ADDR[*] DRAM_BA[*] DRAM_DQ[*] DRAM_LDQM DRAM_UDQM
    DRAM_WE_n DRAM_CAS_n DRAM_RAS_n DRAM_CKE DRAM_CS_n[*]
}]

if {[get_collection_size $de25_n64_sdram_clock] == 1 &&
    [get_collection_size $de25_n64_sdram_clock_port] == 1} {
    # IS42/45VM16320G-6 timing plus conservative DE25-Nano flight-time
    # mismatch: tAC(max)/tOH(min) become 5.6/2.4 ns at the FPGA pin, and
    # SDRAM input setup/hold become +1.6/-1.1 ns for FPGA outputs.
    set_input_delay -clock $de25_n64_sdram_clock \
        -reference_pin $de25_n64_sdram_clock_port \
        -max 5.600 $de25_n64_sdram_dq
    set_input_delay -clock $de25_n64_sdram_clock \
        -reference_pin $de25_n64_sdram_clock_port \
        -min 2.400 $de25_n64_sdram_dq
    set_output_delay -clock $de25_n64_sdram_clock \
        -reference_pin $de25_n64_sdram_clock_port \
        -max 1.600 $de25_n64_sdram_outputs
    set_output_delay -clock $de25_n64_sdram_clock \
        -reference_pin $de25_n64_sdram_clock_port \
        -min -1.100 $de25_n64_sdram_outputs

    # The first C0 edge after each C3 launch is only 4.444 ns later and still
    # captures the preceding burst beat. The controller's CAS pipeline delays
    # use of dq_reg until the following C0 capture, 20.444 ns after launch.
    # Pair launch and functional capture with the normal setup-2/hold-1 rule.
    set de25_n64_sdram_capture_registers [get_keepers -nowarn {
        core|sdram|dq_reg[*]
    }]
    if {[get_collection_size $de25_n64_sdram_capture_registers] > 0} {
        set_multicycle_path -setup 2 -from $de25_n64_sdram_dq \
            -to $de25_n64_sdram_capture_registers
        set_multicycle_path -hold 1 -from $de25_n64_sdram_dq \
            -to $de25_n64_sdram_capture_registers
    }

    # DRAM_CLK is the forwarded reference, not receiver-sampled payload.
    set_false_path -to $de25_n64_sdram_clock_port
}
