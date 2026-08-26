# Minimig's clk_114 and clk_sys are related 4:1 outputs of one IOPLL. The
# shared SDC keeps them synchronous when the core PLL exposes exactly these
# two clocks, allowing TimeQuest to analyze every real inter-domain path.

set de25_minimig_clk_114 [get_clocks -nowarn {
    *|pll|pll|iopll_0|iopll_0_outclk0
}]
set de25_minimig_clk_sys [get_clocks -nowarn {
    *|pll|pll|iopll_0|iopll_0_outclk1
}]

# These are direct translations of upstream Minimig.sdc from top instance
# "emu" to the DE25 shell's "core" instance. The controller samples the 28 MHz
# chipset and CPU state only on its scheduled 114 MHz slots.
foreach {de25_from_pattern de25_to_pattern} {
    {core|cpu_wrapper|cpu_inst*} {core|ram*}
    {core|amiga_clk|cck*}        {core|ram1|*}
    {core|minimig|*}             {core|ram1|*}
} {
    set de25_from_nodes [get_keepers -nowarn $de25_from_pattern]
    set de25_to_nodes [get_keepers -nowarn $de25_to_pattern]
    if {[get_collection_size $de25_from_nodes] > 0 &&
        [get_collection_size $de25_to_nodes] > 0} {
        set_multicycle_path -setup 2 -from $de25_from_nodes -to $de25_to_nodes
        set_multicycle_path -hold 1 -from $de25_from_nodes -to $de25_to_nodes
    }
}

if {[get_collection_size $de25_minimig_clk_sys] == 1 &&
    [get_collection_size $de25_minimig_clk_114] == 1} {
    set_multicycle_path -setup 2 -from $de25_minimig_clk_sys \
        -to $de25_minimig_clk_114
    set_multicycle_path -hold 1 -from $de25_minimig_clk_sys \
        -to $de25_minimig_clk_114
}

set de25_minimig_static_config [get_keepers -nowarn {
    core|minimig|USERIO1|cpu_config*
    core|minimig|USERIO1|ide_config*
    core|minimig|USERIO1|bootrom
    core|minimig|CPU1|halt
}]
if {[get_collection_size $de25_minimig_static_config] > 0} {
    set_false_path -from $de25_minimig_static_config
}

set de25_minimig_hq2x [get_keepers -nowarn {*Hq2x*}]
if {[get_collection_size $de25_minimig_hq2x] > 0} {
    set_multicycle_path -setup 2 -to $de25_minimig_hq2x
    set_multicycle_path -hold 1 -to $de25_minimig_hq2x
}

# Reset and PLL-switch requests assert asynchronously, but release through
# dedicated pipelines in both variable-clock domains. Only their asynchronous
# clear pins and first CDC stages are excluded from normal timing analysis.
set de25_minimig_async_stages [get_keepers -nowarn {
    core|ram1|quiesce_sync[0]
    core|de25_ram_quiesce|ram_request_sync[0]
    core|de25_want_ntsc_sync[0]
}]
if {[get_collection_size $de25_minimig_async_stages] > 0} {
    set_false_path -to $de25_minimig_async_stages
}

set de25_minimig_reset_pins [get_pins -nowarn {
    core|reset_s[*]|clrn
    core|reset_d|clrn
    core|reset_114_s[*]|clrn
    core|reset_114_d|clrn
}]
if {[get_collection_size $de25_minimig_reset_pins] > 0} {
    set_false_path -to $de25_minimig_reset_pins
}

# Native Minimig forwards a registered divide-by-two of clk_114 to the
# onboard SDRAM. Commands and write data change on its falling edge. Read data
# is captured on the following clk_114 edge, one source-clock period after the
# SDRAM launch edge. Its rising edge is source edge 3, its falling edge is
# source edge 5, and its next rising edge is source edge 7. Define the clock
# on the divider register so TimeQuest propagates its actual routed delay to
# DRAM_CLK. Forced HVIO packing is intentionally disabled in this project,
# avoiding the Quartus 25.3.1 U2B2 fitter defect on this bidirectional bus.
set de25_minimig_sdram_clock_port [get_ports DRAM_CLK]
if {[get_collection_size $de25_minimig_clk_114] == 1} {
    create_generated_clock -name minimig_sdram_clk \
        -source [get_pins {core|ram1|sd_clk|clk}] -edges {3 5 7} \
        [get_pins {core|ram1|sd_clk|q}]

    set de25_minimig_sdram_clock [get_clocks minimig_sdram_clk]
    set de25_minimig_sdram_dq [get_ports {DRAM_DQ[*]}]
    set de25_minimig_sdram_outputs [get_ports {
        DRAM_ADDR[*] DRAM_BA[*] DRAM_DQ[*] DRAM_LDQM DRAM_UDQM
        DRAM_WE_n DRAM_CAS_n DRAM_RAS_n DRAM_CKE DRAM_CS_n[*]
    }]

    # IS42/45VM16320G-6 timing plus conservative DE25-Nano flight-time
    # mismatch. These are the same board-level limits used by Menu/MemTest.
    set_input_delay -clock $de25_minimig_sdram_clock \
        -reference_pin $de25_minimig_sdram_clock_port \
        -max 5.600 $de25_minimig_sdram_dq
    set_input_delay -clock $de25_minimig_sdram_clock \
        -reference_pin $de25_minimig_sdram_clock_port \
        -min 2.400 $de25_minimig_sdram_dq
    set_output_delay -clock $de25_minimig_sdram_clock \
        -reference_pin $de25_minimig_sdram_clock_port \
        -max 1.600 $de25_minimig_sdram_outputs
    set_output_delay -clock $de25_minimig_sdram_clock \
        -reference_pin $de25_minimig_sdram_clock_port \
        -min -1.100 $de25_minimig_sdram_outputs

    set de25_minimig_sdata_registers [get_keepers -nowarn {
        core|ram1|sdata_reg[*]
    }]
    if {[get_collection_size $de25_minimig_sdata_registers] > 0} {
        set_multicycle_path -setup 2 -from $de25_minimig_sdram_dq \
            -to $de25_minimig_sdata_registers
        set_multicycle_path -hold 1 -from $de25_minimig_sdram_dq \
            -to $de25_minimig_sdata_registers
    }

    # sd_data_oe is assigned only when sdram_state[0] is low, exactly when
    # the registered DRAM_CLK output falls. It cannot change at the rising
    # sampling edge even though generic register timing assumes it can launch
    # on every clk_114 edge. Keep its setup check to the next rising edge and
    # remove only the impossible same-rising-edge hold check.
    set de25_minimig_sdram_oe [get_keepers -nowarn {
        core|ram1|sd_data_oe
    }]
    if {[get_collection_size $de25_minimig_sdram_oe] > 0} {
        set_false_path -hold -from $de25_minimig_sdram_oe \
            -to $de25_minimig_sdram_dq
    }

    # DRAM_CLK is the forwarded reference clock, not a data output.
    set_false_path -to $de25_minimig_sdram_clock_port
}

# CKE and rank select are static during normal transfers. This path is the
# deliberately immediate safety shutdown for PLL loss or requested clock
# reconfiguration, not a transaction launched against SDRAM_CLK.
set de25_minimig_safety_gate [get_keepers -nowarn {
    core|de25_ram_quiesce|ram_quiesce_pipe[0]
}]
if {[get_collection_size $de25_minimig_safety_gate] > 0} {
    set_false_path -from $de25_minimig_safety_gate -to [get_ports {
        DRAM_CKE DRAM_CS_n[*]
    }]
}

# The common shell also drops CKE combinationally when the platform warm-reset
# handshake is pending. Assertion is intentionally asynchronous so the SDRAM
# is made harmless before any HPS-facing fabric can continue operating. It is
# not a command launched against the forwarded SDRAM clock. Normal controller
# commands, addresses, data, CKE, and rank-select timing remain constrained.
set de25_minimig_platform_reset_gate [get_keepers -nowarn {
    warm_reset_handshake|request_n_sync[*]
    warm_reset_handshake|acknowledge_delay[*]
}]
if {[get_collection_size $de25_minimig_platform_reset_gate] > 0} {
    set_false_path -from $de25_minimig_platform_reset_gate \
        -to [get_ports DRAM_CKE]
}

# Loss of IOPLL lock asynchronously removes DQ drive through sdram_active.
# This is an emergency electrical-safety path, not a transfer between the PLL
# reference clock and the 114 MHz controller domain.
set de25_minimig_pll_lock [get_keepers -nowarn {
    *|tennm_ph2_iopll~pll_ctrl_reg
}]
if {[get_collection_size $de25_minimig_pll_lock] > 0} {
    set_false_path -from $de25_minimig_pll_lock -to [get_keepers -nowarn {
        core|ram1|sd_data_oe
    }]
}
