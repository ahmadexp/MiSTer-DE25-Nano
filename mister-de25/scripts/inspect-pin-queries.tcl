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

foreach command {
    {get_pins -nowarn {*clrn}}
    {get_pins -nowarn -hierarchical {*clrn}}
    {get_pins -nowarn -hierarchical {*reset_pipe*clrn}}
    {get_pins -nowarn -hierarchical {*init_sync*clrn}}
    {get_pins -nowarn {core|de25_core_reset_pipe[0]|clrn}}
    {get_pins -nowarn -hierarchical {core|de25_core_reset_pipe[0]|clrn}}
} {
    if {[catch {set pins [eval $command]} result]} {
        puts "DE25 pin query '$command': ERROR $result"
    } else {
        puts "DE25 pin query '$command': [get_collection_size $pins]"
    }
}

delete_timing_netlist
project_close
