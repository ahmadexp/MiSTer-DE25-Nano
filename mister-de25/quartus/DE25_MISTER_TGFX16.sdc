# TurboGrafx16's 85.9088 MHz RAM/video clock and 42.9544 MHz system clock are
# related outputs of one fixed IOPLL. Upstream intentionally allows the memory
# adapters two source cycles and the audio filters three system cycles.
set tgfx_system_clock [get_clocks -nowarn {
    *|core|pll|impl|iopll_0|iopll_0_outclk1
}]
if {[get_collection_size $tgfx_system_clock] == 1} {
    set tgfx_memory_registers [get_keepers -nowarn {
        *|core|sdram|*
        *|core|ddram|*
    }]
    if {[get_collection_size $tgfx_memory_registers] > 0} {
        set_multicycle_path -from $tgfx_memory_registers \
            -to $tgfx_system_clock -start -setup 2
        set_multicycle_path -from $tgfx_memory_registers \
            -to $tgfx_system_clock -start -hold 1
    }
}

foreach tgfx_filter_pattern {
    {*|core|psg_filter|*}
    {*|core|adpcm_filter|*}
} {
    set tgfx_filter_registers [get_keepers -nowarn $tgfx_filter_pattern]
    if {[get_collection_size $tgfx_filter_registers] > 0} {
        set_multicycle_path -from $tgfx_filter_registers -setup 3
        set_multicycle_path -from $tgfx_filter_registers -hold 2
    }
}
