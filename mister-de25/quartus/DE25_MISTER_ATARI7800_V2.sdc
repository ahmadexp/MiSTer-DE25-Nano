# Atari7800 clocks its SDR SDRAM controller at clk_vid (57.142857 MHz in the
# Agilex bring-up profile). A dedicated PLL output forwards the physical clock
# at the original 180 degree phase. A second related PLL phase captures return
# data, followed by a falling-edge transfer into the clk_vid controller domain.
set de25_atari_sdram_clock_source [get_pins -nowarn {
    core|pll|impl|iopll_0|iopll_0|tennm_ph2_iopll|out_clk[3]
}]
set de25_atari_sdram_clock_port [get_ports -nowarn DRAM_CLK]

if {[get_collection_size $de25_atari_sdram_clock_source] == 1 &&
    [get_collection_size $de25_atari_sdram_clock_port] == 1} {
    create_generated_clock -name ATARI7800_SDRAM_CLK \
        -source $de25_atari_sdram_clock_source \
        $de25_atari_sdram_clock_port

    set de25_atari_sdram_clock [get_clocks ATARI7800_SDRAM_CLK]
    set de25_atari_sdram_dq [get_ports -nowarn {DRAM_DQ[*]}]
    set de25_atari_sdram_outputs [get_ports -nowarn {
        DRAM_ADDR[*] DRAM_BA[*] DRAM_DQ[*] DRAM_LDQM DRAM_UDQM
        DRAM_WE_n DRAM_CAS_n DRAM_RAS_n DRAM_CKE DRAM_CS_n[*]
    }]

    # IS42/45VM16320G-6 timing plus conservative DE25-Nano flight-time
    # mismatch. tAC(max)=5.5 ns and tOH(min)=2.5 ns become 5.6/2.4 ns at
    # the FPGA pin. SDRAM input setup/hold plus flight mismatch become
    # +1.6/-1.1 ns for FPGA outputs.
    set_input_delay -clock $de25_atari_sdram_clock \
        -reference_pin $de25_atari_sdram_clock_port \
        -max 5.600 $de25_atari_sdram_dq
    set_input_delay -clock $de25_atari_sdram_clock \
        -reference_pin $de25_atari_sdram_clock_port \
        -min 2.400 $de25_atari_sdram_dq
    set_output_delay -clock $de25_atari_sdram_clock \
        -reference_pin $de25_atari_sdram_clock_port \
        -max 1.600 $de25_atari_sdram_outputs
    set_output_delay -clock $de25_atari_sdram_clock \
        -reference_pin $de25_atari_sdram_clock_port \
        -min -1.100 $de25_atari_sdram_outputs

    # DRAM_CLK is the forwarded timing reference, not receiver-sampled data.
    set_false_path -to $de25_atari_sdram_clock_port

    # The common shell drops CKE immediately when the HPS warm-reset
    # handshake is asserted. This is an asynchronous electrical-safety path,
    # not a command launched against the Atari SDRAM clock. Normal controller
    # commands and every other SDRAM pin remain source-synchronously timed.
    set de25_atari_platform_reset_gate [get_keepers -nowarn {
        warm_reset_handshake|request_n_sync[*]
        warm_reset_handshake|acknowledge_delay[*]
    }]
    if {[get_collection_size $de25_atari_platform_reset_gate] > 0} {
        set_false_path -from $de25_atari_platform_reset_gate \
            -to [get_ports DRAM_CKE]
    }
}
