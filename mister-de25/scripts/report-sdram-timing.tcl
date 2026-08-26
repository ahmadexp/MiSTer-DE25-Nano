package require ::quartus::project
package require ::quartus::sta

set project DE25_MISTER_MEMTEST
if {[llength $quartus(args)] > 0} {
    set project [lindex $quartus(args) 0]
}

project_open $project -revision $project
create_timing_netlist
read_sdc
update_timing_netlist

set de25_sdram_dq [get_ports {DRAM_DQ[*]}]
set de25_sdram_outputs [get_ports {
    DRAM_ADDR[*] DRAM_BA[*] DRAM_DQ[*] DRAM_LDQM DRAM_UDQM
    DRAM_WE_n DRAM_CAS_n DRAM_RAS_n DRAM_CKE DRAM_CS_n[*]
}]
set de25_registers [all_registers]

proc require_nonnegative_slack {label paths} {
    if {[get_collection_size $paths] == 0} {
        error "SDRAM timing check '$label' found no paths"
    }

    set worst_slack 1.0e30
    foreach_in_collection path $paths {
        set slack [get_path_info -slack $path]
        if {$slack < $worst_slack} {
            set worst_slack $slack
        }
    }

    puts [format "SDRAM timing check: %-12s %+0.3f ns" $label $worst_slack]
    if {$worst_slack < 0.0} {
        error [format "SDRAM timing check '%s' failed with %+0.3f ns slack" \
            $label $worst_slack]
    }
}

report_clocks -file ${project}.sdram-clocks.rpt
report_timing -setup -npaths 100 -detail summary \
    -file ${project}.global-setup.rpt
report_timing -hold -npaths 100 -detail summary \
    -file ${project}.global-hold.rpt
report_timing -setup -to [get_ports {DRAM_ADDR[0]}] -npaths 5 \
    -detail full_path -file ${project}.sdram-output-setup.rpt
report_timing -hold -to [get_ports {DRAM_ADDR[0]}] -npaths 5 \
    -detail full_path -file ${project}.sdram-output-hold.rpt
report_timing -setup -to $de25_sdram_outputs -npaths 100 \
    -detail summary -file ${project}.sdram-all-output-setup.rpt
report_timing -hold -to $de25_sdram_outputs -npaths 100 \
    -detail summary -file ${project}.sdram-all-output-hold.rpt
report_timing -setup -from $de25_sdram_dq -to $de25_registers -npaths 100 \
    -detail full_path -file ${project}.sdram-input-setup.rpt
report_timing -hold -from $de25_sdram_dq -to $de25_registers -npaths 100 \
    -detail full_path -file ${project}.sdram-input-hold.rpt

# Full-design setup and hold are enforced separately from the standard
# TimeQuest summary. Keep this audit scoped to paths that actually terminate
# at or originate from the external SDRAM interface.
require_nonnegative_slack output-setup \
    [get_timing_paths -setup -to $de25_sdram_outputs -npaths 100]
require_nonnegative_slack output-hold \
    [get_timing_paths -hold -to $de25_sdram_outputs -npaths 100]
require_nonnegative_slack input-setup \
    [get_timing_paths -setup -from $de25_sdram_dq -to $de25_registers -npaths 100]
require_nonnegative_slack input-hold \
    [get_timing_paths -hold -from $de25_sdram_dq -to $de25_registers -npaths 100]

delete_timing_netlist
project_close
