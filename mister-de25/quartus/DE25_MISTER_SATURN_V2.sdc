# Saturn runs its native SDRAM controller at 114.545455 MHz. PLL C2 is the
# exact half-cycle-shifted copy of C1 that replaces the Cyclone altddio_out
# forwarded clock. Commands launch on C1 and the SDRAM samples on C2.
set de25_saturn_sdram_clock [get_clocks -nowarn {
    core|pll|impl|iopll_0|iopll_0_outclk2
}]
set de25_saturn_sdram_clock_port [get_ports -nowarn DRAM_CLK]
set de25_saturn_sdram_dq [get_ports -nowarn {DRAM_DQ[*]}]
set de25_saturn_sdram_outputs [get_ports -nowarn {
    DRAM_ADDR[*] DRAM_BA[*] DRAM_DQ[*] DRAM_LDQM DRAM_UDQM
    DRAM_WE_n DRAM_CAS_n DRAM_RAS_n DRAM_CKE DRAM_CS_n[*]
}]

if {[get_collection_size $de25_saturn_sdram_clock] == 1 &&
    [get_collection_size $de25_saturn_sdram_clock_port] == 1} {
    # IS42/45VM16320G-6 timing plus conservative DE25-Nano flight-time
    # mismatch. tAC(max)/tOH(min) become 5.6/2.4 ns at the FPGA pin, while
    # SDRAM input setup/hold become +1.6/-1.1 ns for FPGA outputs.
    set_input_delay -clock $de25_saturn_sdram_clock \
        -reference_pin $de25_saturn_sdram_clock_port \
        -max 5.600 $de25_saturn_sdram_dq
    set_input_delay -clock $de25_saturn_sdram_clock \
        -reference_pin $de25_saturn_sdram_clock_port \
        -min 2.400 $de25_saturn_sdram_dq
    set_output_delay -clock $de25_saturn_sdram_clock \
        -reference_pin $de25_saturn_sdram_clock_port \
        -max 1.600 $de25_saturn_sdram_outputs
    set_output_delay -clock $de25_saturn_sdram_clock \
        -reference_pin $de25_saturn_sdram_clock_port \
        -min -1.100 $de25_saturn_sdram_outputs

    # Board clock-output delay, device tAC, and the fabric input route place
    # the returning beat after the first two C1 edges. The third edge still
    # precedes the following beat at the FPGA input and the state pipeline is
    # aligned to consume it, preserving one word per controller cycle.
    set de25_saturn_sdram_capture_registers [get_keepers -nowarn {
        core|sdram1|rbuf0[*]
    }]
    if {[get_collection_size $de25_saturn_sdram_capture_registers] > 0} {
        set_multicycle_path -setup 3 -from $de25_saturn_sdram_dq \
            -to $de25_saturn_sdram_capture_registers
        set_multicycle_path -hold 2 -from $de25_saturn_sdram_dq \
            -to $de25_saturn_sdram_capture_registers
    }

    # DRAM_CLK is the forwarded reference, not receiver-sampled payload.
    set_false_path -to $de25_saturn_sdram_clock_port

    # CKE has an asynchronous safety override during warm reset. Normal SDRAM
    # commands and all other memory pins remain source-synchronously timed.
    set de25_saturn_platform_reset_gate [get_keepers -nowarn {
        warm_reset_handshake|request_n_sync[*]
        warm_reset_handshake|acknowledge_delay[*]
    }]
    if {[get_collection_size $de25_saturn_platform_reset_gate] > 0} {
        set_false_path -from $de25_saturn_platform_reset_gate \
            -to [get_ports DRAM_CKE]
    }
}
