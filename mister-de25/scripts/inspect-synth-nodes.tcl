# SPDX-License-Identifier: GPL-3.0-or-later
package require ::quartus::project
load_package report

set project [lindex $quartus(args) 0]
if {$project eq ""} {
    error "usage: quartus_cdb -t inspect-synth-nodes.tcl PROJECT"
}

project_open $project -revision $project
load_report
set names [get_names -filter *core_partition* -node_type hierarchy]
puts "core_partition names=[get_collection_size $names]"
foreach_in_collection name $names {
    puts "  [get_name_info -info full_path $name] type=[get_name_info -info node_type $name]"
}
unload_report
project_close -dont_export_assignments
