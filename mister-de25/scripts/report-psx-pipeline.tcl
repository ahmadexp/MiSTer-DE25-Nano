package require ::quartus::project
package require ::quartus::sta

set project DE25_MISTER_PSX_V2
if {[llength $quartus(args)] > 0} {
    set project [lindex $quartus(args) 0]
}

proc require_count {label collection expected} {
    set actual [get_collection_size $collection]
    puts [format "PSX pipeline nodes: %-12s %d" $label $actual]
    if {$actual != $expected} {
        error [format "PSX pipeline expected %d %s nodes, found %d" \
            $expected $label $actual]
    }
}

proc require_minimum_count {label collection minimum} {
    set actual [get_collection_size $collection]
    puts [format "PSX pipeline nodes: %-12s %d" $label $actual]
    if {$actual < $minimum} {
        error [format "PSX pipeline expected at least %d %s nodes, found %d" \
            $minimum $label $actual]
    }
}

proc summarize_paths {label analysis from_nodes to_nodes} {
    set paths [get_timing_paths -$analysis -from $from_nodes -to $to_nodes \
        -npaths 1000]
    set count [get_collection_size $paths]
    if {$count == 0} {
        error "PSX pipeline timing check '$label-$analysis' found no paths"
    }

    set worst 1.0e30
    set violations 0
    set endpoints [dict create]
    foreach_in_collection path $paths {
        set slack [get_path_info -slack $path]
        if {$slack < $worst} {
            set worst $slack
        }
        if {$slack < 0.0} {
            incr violations
        }
        set endpoint [get_node_info -name [get_path_info -to $path]]
        dict set endpoints $endpoint 1
    }
    puts [format \
        "PSX pipeline timing: %-22s %-5s %+0.3f ns, %d paths, %d endpoints, %d violations" \
        $label $analysis $worst $count [dict size $endpoints] $violations]
    if {$violations != 0} {
        error [format "PSX pipeline timing check '%s-%s' has %d violations" \
            $label $analysis $violations]
    }
}

project_open $project -revision $project
create_timing_netlist
read_sdc
update_timing_netlist

set dq_pins [get_ports -nowarn {DRAM_DQ[*]}]
set dq_capture [get_keepers -nowarn {*|sdram|dq_reg[*]}]
set dq_pipeline [get_keepers -nowarn {*|sdram|dq_pipe[*]}]
set dq_consumers [get_keepers -nowarn {
    *|sdram|ch1_dout[*]
    *|sdram|ch2_dout[*]
    *|sdram|ch3_dout[*]
}]

require_count dq-pins $dq_pins 16
require_count dq-capture $dq_capture 16
# Physical synthesis may duplicate dq_pipe bits to reduce fanout. Require at
# least the 16 logical bits and report the exact fitted-node count below.
require_minimum_count dq-pipeline $dq_pipeline 16

summarize_paths external-input setup $dq_pins $dq_capture
summarize_paths external-input hold $dq_pins $dq_capture
summarize_paths capture-to-pipeline setup $dq_capture $dq_pipeline
summarize_paths capture-to-pipeline hold $dq_capture $dq_pipeline
summarize_paths pipeline-to-consumer setup $dq_pipeline $dq_consumers
summarize_paths pipeline-to-consumer hold $dq_pipeline $dq_consumers

report_timing -setup -from $dq_pins -to $dq_capture -npaths 16 \
    -detail full_path -file ${project}.psx-external-input-setup.rpt
report_timing -hold -from $dq_pins -to $dq_capture -npaths 16 \
    -detail full_path -file ${project}.psx-external-input-hold.rpt
report_timing -setup -from $dq_capture -to $dq_pipeline -npaths 16 \
    -detail full_path -file ${project}.psx-capture-pipeline-setup.rpt
report_timing -setup -from $dq_pipeline -to $dq_consumers -npaths 100 \
    -detail full_path -file ${project}.psx-pipeline-consumer-setup.rpt

delete_timing_netlist
project_close
