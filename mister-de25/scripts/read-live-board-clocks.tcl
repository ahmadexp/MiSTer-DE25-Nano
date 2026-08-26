# Read the two otherwise-unused DE25-Nano programmable-clock inputs through
# the PC110 diagnostic pager. Main must be stopped while this script owns GPO.

if {$argc != 1} {
    puts stderr "Usage: system-console --script=read-live-board-clocks.tcl DESIGN.sof"
    exit 2
}

set design_file [lindex $argv 0]
if {![file isfile $design_file]} {
    error "SOF not found: $design_file"
}

set design [design_load $design_file]
set devices {}
for {set attempt 0} {$attempt < 100 && [llength $devices] == 0} {incr attempt} {
    refresh_connections
    set devices [get_service_paths device]
    if {[llength $devices] == 0} {
        after 50
    }
}
if {[llength $devices] != 1} {
    error "Expected exactly one FPGA device, found [llength $devices]"
}
set design_instance [design_instantiate $design]
design_link $design_instance [lindex $devices 0]
refresh_connections

set paths [get_service_paths master]
set candidates [lsearch -all -inline -glob $paths "*fpga_m*"]
if {[llength $candidates] != 1} {
    error "Expected exactly one fpga_m JTAG master, found [llength $candidates]"
}

set master [claim_service master [lindex $candidates 0] de25_clock_reader]
set gp_out_address 0x20000
set gp_in_address  0x20010
set saved_gp_out [lindex [master_read_32 $master $gp_out_address 1] 0]
set selector_mask 0x3FC00007
set base_gp_out [expr {
    (($saved_gp_out | 0x80000000) & ~$selector_mask) & 0xffffffff
}]

if {[catch {
    foreach clock_select {0 1} {
        set frequency 0
        for {set page 0} {$page < 4} {incr page} {
            set gp_out [expr {$base_gp_out | (1 << 23) |
                ($clock_select << 22) | $page}]
            master_write_32 $master $gp_out_address $gp_out
            after 5
            set gp_in [lindex [master_read_32 $master $gp_in_address 1] 0]
            set chunk [expr {($gp_in >> 21) & 0x3f}]
            set frequency [expr {$frequency | ($chunk << (6 * $page))}]
        }
        set label [expr {$clock_select ? 2 : 1}]
        puts [format "CLOCK%d_50=%d kHz" $label $frequency]
    }
} message options]} {
    master_write_32 $master $gp_out_address $saved_gp_out
    close_service master $master
    return -options $options $message
}

master_write_32 $master $gp_out_address $saved_gp_out
close_service master $master
flush stdout
exit 0
