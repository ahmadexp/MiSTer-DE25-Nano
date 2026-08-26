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

report_timing -setup -npaths 50 -detail full_path \
    -file ${project}.failing-setup.rpt
report_timing -recovery -npaths 50 -detail full_path \
    -file ${project}.failing-recovery.rpt
report_timing -hold -npaths 50 -detail full_path \
    -file ${project}.failing-hold.rpt
report_timing -removal -npaths 50 -detail full_path \
    -file ${project}.failing-removal.rpt

foreach analysis {setup hold recovery removal} {
    puts "DE25 failing $analysis paths:"
    set paths [get_timing_paths -$analysis -npaths 50]
    foreach_in_collection path $paths {
        set slack [get_path_info -slack $path]
        if {$slack >= 0.0} {
            continue
        }
        set from [get_node_info -name [get_path_info -from $path]]
        set to [get_node_info -name [get_path_info -to $path]]
        set launch_clock [get_clock_info -name [get_path_info -from_clock $path]]
        set latch_clock [get_clock_info -name [get_path_info -to_clock $path]]
        puts [format "  %+0.3f ns  %s -> %s  (%s -> %s)" \
            $slack $from $to $launch_clock $latch_clock]
    }
}

delete_timing_netlist
project_close
