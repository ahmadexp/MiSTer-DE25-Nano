# Read platform-v2 Si5332 identity and both external-clock counters through the
# JTAG-to-Avalon GP diagnostic pager. Stop MiSTer Main before running this tool.

if {$argc != 1} {
    puts stderr "Usage: system-console --script=read-platform-v2-status.tcl DESIGN.sof"
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
    if {[llength $devices] == 0} { after 50 }
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

set master [claim_service master [lindex $candidates 0] de25_v2_status_reader]
set gp_out_address 0x20000
set gp_in_address  0x20010
set saved_gp_out [lindex [master_read_32 $master $gp_out_address 1] 0]
# Select live GPI, clear the page and all user-I/O selects/strobes, and retain
# the high reset-handshake bits exactly as they were.
set selector_mask 0x001E001F
set base_gp_out [expr {
    (($saved_gp_out | 0x80000000) & ~$selector_mask) & 0xffffffff
}]

proc read_page {master gp_out_address gp_in_address base page} {
    master_write_32 $master $gp_out_address [expr {$base | $page}]
    after 5
    set gp_in [lindex [master_read_32 $master $gp_in_address 1] 0]
    return [expr {($gp_in >> 21) & 0x3f}]
}

if {[catch {
    set probe [read_page $master $gp_out_address $gp_in_address $base_gp_out 0]
    set flags [read_page $master $gp_out_address $gp_in_address $base_gp_out 1]

    set identity 0
    for {set page 2} {$page <= 17} {incr page} {
        set chunk [read_page $master $gp_out_address $gp_in_address \
            $base_gp_out $page]
        set identity [expr {$identity | ($chunk << (6 * ($page - 2)))}]
    }

    set clock1 0
    for {set page 18} {$page <= 21} {incr page} {
        set chunk [read_page $master $gp_out_address $gp_in_address \
            $base_gp_out $page]
        set clock1 [expr {$clock1 | ($chunk << (6 * ($page - 18)))}]
    }
    set clock2 0
    for {set page 22} {$page <= 25} {incr page} {
        set chunk [read_page $master $gp_out_address $gp_in_address \
            $base_gp_out $page]
        set clock2 [expr {$clock2 | ($chunk << (6 * ($page - 22)))}]
    }
    set address_high [read_page $master $gp_out_address $gp_in_address \
        $base_gp_out 26]
    set address [expr {($address_high << 1) | ($flags & 1)}]

    puts [format "probe=0x%02X identity_valid=%d clocks_ready=%d fault=%d" \
        $probe [expr {($flags >> 5) & 1}] [expr {($flags >> 4) & 1}] \
        [expr {($flags >> 3) & 1}]]
    puts [format "address=0x%02X identity=0x%024X" $address $identity]
    puts [format "CLOCK1_50=%d kHz CLOCK2_50=%d kHz" $clock1 $clock2]
} message options]} {
    master_write_32 $master $gp_out_address $saved_gp_out
    close_service master $master
    return -options $options $message
}

master_write_32 $master $gp_out_address $saved_gp_out
close_service master $master
flush stdout
exit 0
