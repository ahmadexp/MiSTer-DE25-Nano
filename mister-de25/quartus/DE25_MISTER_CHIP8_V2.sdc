# CHIP-8 derives three very slow clocks by toggling registers from the exact
# 1 MHz core PLL output. Model their full periods relative to the 50 MHz board
# reference, including both halves of each divider cycle.
set chip8_ref [get_ports -nowarn CLOCK0_50]
set chip8_fast_target [get_keepers -nowarn {core|clk_cpu_fast}]
set chip8_slow_target [get_keepers -nowarn {core|clk_cpu_slow}]
set chip8_12k_target [get_keepers -nowarn {core|clk_12k}]

if {[get_collection_size $chip8_fast_target] == 1} {
    create_generated_clock -name CHIP8_CPU_FAST \
        -source $chip8_ref -divide_by 8000 $chip8_fast_target
}
if {[get_collection_size $chip8_slow_target] == 1} {
    create_generated_clock -name CHIP8_CPU_SLOW \
        -source $chip8_ref -divide_by 20000 $chip8_slow_target
}
if {[get_collection_size $chip8_12k_target] == 1} {
    create_generated_clock -name CHIP8_SERVICE \
        -source $chip8_ref -divide_by 8300 $chip8_12k_target
}

# The toggling divider registers also use their own Q output as feedback data.
# Once that Q output is declared as a generated clock, TimeQuest otherwise
# invents a generated-clock-to-parent-clock hold check on the divider flop
# itself. The feedback is already timed by its real 1 MHz parent clock.
foreach chip8_divider_target [list \
    $chip8_fast_target $chip8_slow_target $chip8_12k_target] {
    if {[get_collection_size $chip8_divider_target] == 1} {
        set_false_path -from $chip8_divider_target \
            -to $chip8_divider_target
    }
}

# The HPS PS/2 transmitter creates this protocol clock from clk_sys with a
# 4000-count half-period divider. It may pause while idle, but can never run
# faster than this generated-clock constraint.
set chip8_ps2_target \
    [get_keepers -nowarn {core|hps_io|keyboard|ps2_clk_out}]
if {[get_collection_size $chip8_ps2_target] == 1} {
    create_generated_clock -name CHIP8_PS2 \
        -source $chip8_ref -divide_by 8002 $chip8_ps2_target
}
