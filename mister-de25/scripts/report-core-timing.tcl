package require ::quartus::project
package require ::quartus::sta

set project DE25_MISTER_SMS
if {[llength $quartus(args)] > 0} {
    set project [lindex $quartus(args) 0]
}

project_open $project -revision $project
create_timing_netlist
read_sdc
update_timing_netlist

set core_clock_patterns {
    outclk0 {*|pll|pll|iopll_0|iopll_0_outclk0}
    outclk1 {*|pll|pll|iopll_0|iopll_0_outclk1}
    outclk2 {*|pll|pll|iopll_0|iopll_0_outclk2}
}

foreach {label pattern} $core_clock_patterns {
    set clock [get_clocks -nowarn $pattern]
    if {[get_collection_size $clock] != 1} {
        puts "Core timing report: $label matched [get_collection_size $clock] clocks"
        continue
    }

    report_timing -setup -to_clock $clock -npaths 50 -detail full_path \
        -file ${project}.${label}-setup.rpt
    report_timing -hold -to_clock $clock -npaths 50 -detail full_path \
        -file ${project}.${label}-hold.rpt

    puts "Core timing report: $label ([get_clock_info -name $clock])"
    set paths [get_timing_paths -setup -to_clock $clock -npaths 50]
    if {[get_collection_size $paths] == 0} {
        puts "  no setup paths"
        continue
    }

    set index 0
    foreach_in_collection path $paths {
        incr index
        set start_node [get_path_info -from $path]
        set end_node [get_path_info -to $path]
        puts [format "  %2d  %+8.3f ns  %s -> %s" \
            $index [get_path_info -slack $path] \
            [get_node_info -name $start_node] \
            [get_node_info -name $end_node]]
    }
}

delete_timing_netlist
project_close
