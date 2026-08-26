# Read the SDM configuration-status response through the JTAG packet service.
# This is read-only and works before the FPGA fabric has entered user mode.

refresh_connections

set config_paths {}
for {set attempt 0} {$attempt < 50 && [llength $config_paths] == 0} {incr attempt} {
    foreach path [get_service_paths packet] {
        if {[catch {set marker [marker_get_info $path]} message]} {
            puts "packet marker unavailable: $path ($message)"
            continue
        }
        puts "packet: $path marker=$marker"
        if {[lindex $marker 1] eq "config"} {
            lappend config_paths $path
        }
    }
    if {[llength $config_paths] == 0} {
        after 100
        refresh_connections
    }
}

if {[llength $config_paths] == 0} {
    puts stderr "No SDM configuration packet service found"
    exit 1
}

set service [claim_service packet [lindex $config_paths 0] de25_config_status]
set response [packet_send_command -format 32 $service {0x00000004}]
close_service packet $service

set words {}
foreach word $response {
    lappend words [format 0x%08x [expr {$word & 0xffffffff}]]
}
puts "CONFIG_STATUS=$words"

exit
