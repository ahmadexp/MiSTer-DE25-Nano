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

set reset_clear_nodes [get_pins -nowarn -hierarchical {
    *reset_pipe*clrn
    *init_sync*clrn
}]
puts "DE25 reset clear node count: [get_collection_size $reset_clear_nodes]"
puts "DE25 recovery count before diagnostic exception: [get_collection_size [get_timing_paths -recovery -npaths 200]]"

set_false_path -to $reset_clear_nodes
update_timing_netlist
puts "DE25 recovery count after diagnostic exception: [get_collection_size [get_timing_paths -recovery -npaths 200]]"

report_timing -recovery -npaths 20 -detail summary

delete_timing_netlist
project_close
