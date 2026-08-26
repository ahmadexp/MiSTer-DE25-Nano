# SPDX-License-Identifier: GPL-3.0-or-later
package require ::quartus::project

set project [lindex $quartus(args) 0]
if {$project eq ""} {
    error "usage: quartus_sh -t inspect-root-assignments.tcl PROJECT"
}

project_open $project -revision $project
foreach assignment {
    PARTITION RESERVED_CORE PLACE_REGION RESERVE_PLACE_REGION
    CORE_ONLY_PLACE_REGION ROUTE_REGION RESERVE_ROUTE_REGION
} {
    set values [get_all_instance_assignments -name $assignment]
    puts "$assignment count=[get_collection_size $values]"
    foreach_in_collection value $values {
        puts "  [join $value { | }]"
    }
}
project_close -dont_export_assignments
