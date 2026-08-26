package require ::quartus::project
package require ::quartus::sta

set project DE25_MISTER_PCXT
if {[llength $quartus(args)] > 0} {
    set project [lindex $quartus(args) 0]
}

project_open $project -revision $project
create_timing_netlist
read_sdc
update_timing_netlist

foreach variable {
    de25_core_pll_clocks de25_async_clock_groups
    de25_audio_sample_registers de25_shell_memory_clocks
    de25_shell_video_clock
} {
    if {[info exists $variable]} {
        set value [set $variable]
        if {$variable eq "de25_async_clock_groups"} {
            puts "PCXT SDC diagnostic: $variable has [llength $value] groups: $value"
        } else {
            puts "PCXT SDC diagnostic: $variable has [get_collection_size $value] objects"
        }
    } else {
        puts "PCXT SDC diagnostic: $variable is not defined"
    }
}
foreach pattern {
    {*|pll_all|impl|iopll_0|iopll_0_outclk*}
    {*|audio|samples[*]}
    {*audio|samples*}
} {
    set objects [get_keepers -nowarn $pattern]
    set clocks [get_clocks -nowarn $pattern]
    puts "PCXT SDC diagnostic: pattern $pattern matches [get_collection_size $objects] keepers and [get_collection_size $clocks] clocks"
}

foreach pattern {
    {core|clk_14_318*}
    {core|ce_pixel_cga*}
    {core|u_CHIPSET|u_PERIPHERALS|cga1|crtc|HSYNC*}
} {
    set pcxt_pins [get_pins -nowarn $pattern]
    puts "PCXT SDC diagnostic: pins for $pattern ([get_collection_size $pcxt_pins])"
    foreach_in_collection pin $pcxt_pins {
        puts "  [get_pin_info -name $pin]"
    }
}

set pcxt_clock_patterns {
    platform_outclk0 {platform_clocks|system_pll|system_pll_outclk0}
    platform_outclk1 {platform_clocks|system_pll|system_pll_outclk1}
    platform_outclk2 {platform_clocks|system_pll|system_pll_outclk2}
    core_outclk0     {core|pll_all|impl|iopll_0|iopll_0_outclk0}
    core_outclk1     {core|pll_all|impl|iopll_0|iopll_0_outclk1}
    core_outclk2     {core|pll_all|impl|iopll_0|iopll_0_outclk2}
    core_outclk3     {core|pll_all|impl|iopll_0|iopll_0_outclk3}
    core_outclk5     {core|pll_all|impl|iopll_0|iopll_0_outclk5}
    pcxt_clk_14      {DE25_PCXT_CLK_14_318}
    pcxt_ce_pixel    {DE25_PCXT_CE_PIXEL_CGA}
    pcxt_cga_hsync   {DE25_PCXT_CGA_HSYNC}
}

foreach {label pattern} $pcxt_clock_patterns {
    set clock [get_clocks -nowarn $pattern]
    if {[get_collection_size $clock] != 1} {
        puts "PCXT timing report: $label matched [get_collection_size $clock] clocks"
        continue
    }

    report_timing -setup -to_clock $clock -npaths 20 -detail full_path \
        -file ${project}.${label}-setup.rpt
    puts "PCXT timing report: $label ([get_clock_info -name $clock])"
    set paths [get_timing_paths -setup -to_clock $clock -npaths 20]
    foreach_in_collection path $paths {
        set start_node [get_path_info -from $path]
        set end_node [get_path_info -to $path]
        puts [format "  %+8.3f ns  %s -> %s  (%s)" \
            [get_path_info -slack $path] \
            [get_node_info -name $start_node] \
            [get_node_info -name $end_node] \
            [get_clock_info -name [get_path_info -from_clock $path]]]
    }
}

foreach {label pattern} {
    pcxt_clk_14   {DE25_PCXT_CLK_14_318}
    pcxt_ce_pixel {DE25_PCXT_CE_PIXEL_CGA}
} {
    set clock [get_clocks -nowarn $pattern]
    if {[get_collection_size $clock] != 1} {
        continue
    }
    report_timing -hold -to_clock $clock -npaths 20 -detail full_path \
        -file ${project}.${label}-hold.rpt
    puts "PCXT hold report: $label"
    set paths [get_timing_paths -hold -to_clock $clock -npaths 20]
    foreach_in_collection path $paths {
        set start_node [get_path_info -from $path]
        set end_node [get_path_info -to $path]
        puts [format "  %+8.3f ns  %s -> %s  (%s)" \
            [get_path_info -slack $path] \
            [get_node_info -name $start_node] \
            [get_node_info -name $end_node] \
            [get_clock_info -name [get_path_info -from_clock $path]]]
    }
}

delete_timing_netlist
project_close
