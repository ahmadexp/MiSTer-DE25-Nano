package require ::quartus::project
package require ::quartus::sta

set project DE25_MISTER_N64_V2
if {[llength $quartus(args)] > 0} {
    set project [lindex $quartus(args) 0]
}

project_open $project -revision $project
create_timing_netlist
read_sdc
update_timing_netlist

proc show_collection {kind pattern collection} {
    puts "N64 $kind pattern $pattern: count [get_collection_size $collection]"
    set shown 0
    foreach_in_collection item $collection {
        puts "  [get_node_info -name $item] ([get_node_info -type $item])"
        incr shown
        if {$shown >= 200} {
            puts "  ... truncated"
            break
        }
    }
}

foreach pattern {
    {DRAM_DQ[*]}
    {*|sdram|*}
    {*|sdram|dq_reg*}
    {*|sdram|ch1_dout*}
    {*|sdram|ch2_dout*}
    {*|sdram|ch3_dout*}
    {*|sdram_dataRead*}
    {*|sdramMux_dataRead*}
    {*|SDRamMux*}
    {*|iSDRamMux*}
    {*pll_locked*}
    {*|pll|*locked*}
    {*|sdram|state*}
    {*|sdram|sdram_dq_*}
    {*core_sdram_dq*}
} {
    show_collection nodes $pattern [get_nodes -nowarn $pattern]
    show_collection keepers $pattern [get_keepers -nowarn $pattern]
    show_collection pins $pattern [get_pins -nowarn $pattern]
}

set dq_ports [get_ports -nowarn {DRAM_DQ[*]}]
foreach_in_collection dq $dq_ports {
    set dq_name [get_node_info -name $dq]
    set fanout [get_fanouts $dq]
    puts "N64 fanout $dq_name: count [get_collection_size $fanout]"
    set shown 0
    foreach_in_collection item $fanout {
        puts "  [get_node_info -name $item] ([get_node_info -type $item])"
        incr shown
        if {$shown >= 100} {
            puts "  ... truncated"
            break
        }
    }
}

delete_timing_netlist
project_close
