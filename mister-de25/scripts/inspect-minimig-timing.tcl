package require ::quartus::project
package require ::quartus::sta

set project DE25_MISTER_MINIMIG
project_open $project -revision $project
create_timing_netlist
read_sdc
update_timing_netlist

proc show_collection {label collection} {
    puts [format "COLLECTION %-24s %d" $label [get_collection_size $collection]]
    set shown 0
    foreach_in_collection item $collection {
        puts "  [get_object_info -name $item]"
        incr shown
        if {$shown >= 12} {
            break
        }
    }
}

show_collection ram1_registers [get_keepers -nowarn {*ram1*}]
show_collection sdata_registers [get_keepers -nowarn {*ram1*sdata_reg*}]
show_collection sdram_state [get_keepers -nowarn {*ram1*sdram_state*}]
show_collection sdram_clock_pin [get_pins -nowarn {core|ram1|sd_clk|*}]
show_collection sdram_state0_pin [get_pins -nowarn {core|ram1|sdram_state[0]|*}]
show_collection sdram_clock_register [get_keepers -nowarn {*ram1*sd_clk*}]
show_collection minimig_registers [get_keepers -nowarn {core|minimig*}]
show_collection cpu_registers [get_keepers -nowarn {core|cpu_wrapper*}]

report_timing -setup -npaths 30 -detail full_path \
    -file ${project}.inspect-global-setup.rpt
report_timing -recovery -npaths 30 -detail full_path \
    -file ${project}.inspect-global-recovery.rpt
report_timing -setup -from [get_ports {DRAM_DQ[*]}] -npaths 30 \
    -detail full_path -file ${project}.inspect-sdram-input-setup.rpt
report_timing -setup -to [get_ports {
    DRAM_ADDR[*] DRAM_BA[*] DRAM_DQ[*] DRAM_LDQM DRAM_UDQM
    DRAM_WE_n DRAM_CAS_n DRAM_RAS_n DRAM_CKE DRAM_CS_n[*]
}] -npaths 30 -detail full_path \
    -file ${project}.inspect-sdram-output-setup.rpt

delete_timing_netlist
project_close
