package require ::quartus::project
package require ::quartus::sta

set project DE25_MISTER_SNES
if {[llength $quartus(args)] > 0} {
    set project [lindex $quartus(args) 0]
}

project_open $project -revision $project
create_timing_netlist
read_sdc
update_timing_netlist

foreach pattern {
    {*|core_reset_pipe*}
    {*|audio_reset_pipe*}
    {*|hps_reset_pipe*}
    {*|init_sync*}
    {*DRAM_DQ*}
    {*data_capture*}
    {*rbuf*}
    {*dout_buf*}
    {*de25_core_reset_pipe*}
} {
    puts "DE25 node pattern $pattern:"
    set nodes [get_nodes -nowarn $pattern]
    puts "  count [get_collection_size $nodes]"
    set shown 0
    foreach_in_collection node $nodes {
        puts "  [get_node_info -name $node] ([get_node_info -type $node])"
        incr shown
        if {$shown >= 80} {
            break
        }
    }
}

foreach pattern {
    {*|core_reset_pipe*|clrn}
    {*|audio_reset_pipe*|clrn}
    {*|hps_reset_pipe*|clrn}
    {*|init_sync*|clrn}
} {
    puts "DE25 pin pattern $pattern:"
    set pins [get_pins -nowarn $pattern]
    puts "  count [get_collection_size $pins]"
    foreach_in_collection pin $pins {
        puts "  [get_node_info -name $pin] ([get_node_info -type $pin])"
    }
}

delete_timing_netlist
project_close
