# Read the DE25-Nano switch PIO directly through the live GHRD JTAG master.
# An optional compatible SOF links symbolic service names to a runtime RBF.

if {$argc > 1} {
    puts stderr "Usage: system-console --script=read-live-switches.tcl ?DESIGN.sof?"
    exit 2
}

if {$argc == 1} {
    set design_file [lindex $argv 0]
    set devices {}
    for {set attempt 0} {$attempt < 100 && [llength $devices] == 0} {incr attempt} {
        refresh_connections
        set devices [get_service_paths device]
        if {[llength $devices] == 0} {
            after 50
        }
    }
    if {![file isfile $design_file] || [llength $devices] != 1} {
        puts stderr "A compatible SOF and exactly one FPGA device are required"
        exit 1
    }
    set design [design_load $design_file]
    set design_instance [design_instantiate $design]
    design_link $design_instance [lindex $devices 0]
}

set candidates {}
for {set attempt 0} {$attempt < 100 && [llength $candidates] == 0} {incr attempt} {
    refresh_connections
    set paths [get_service_paths master]
    set candidates [lsearch -all -inline -glob $paths "*fpga_m*"]
    if {[llength $candidates] == 0} {
        after 50
    }
}
if {[llength $candidates] == 0 && [llength $paths] == 3} {
    # Without a linked design database, System Console exposes the three GHRD
    # masters as phy_0 through phy_2. The first one is fpga_m.
    set candidates [list [lindex $paths 0]]
}
if {[llength $candidates] != 1} {
    error "Expected one live fpga_m JTAG master, found [llength $candidates]"
}

set master [claim_service master [lindex $candidates 0] de25_switch_reader]
if {[catch {
    set switches [expr {[lindex [master_read_32 $master 0x10070 1] 0] & 0x0f}]
    puts [format "SW=0x%X SW0=%d SW1=%d SW2=%d SW3=%d" \
        $switches \
        [expr {$switches & 1}] \
        [expr {($switches >> 1) & 1}] \
        [expr {($switches >> 2) & 1}] \
        [expr {($switches >> 3) & 1}]]
} message options]} {
    close_service master $master
    return -options $options $message
}

close_service master $master
flush stdout
exit 0
