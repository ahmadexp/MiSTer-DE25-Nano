# Read-only probe for the Agilex 5 Remote System Update state through the SDM
# JTAG packet service. A valid response is required before any reconfiguration
# request is considered.
refresh_connections

set config_paths {}
for {set attempt 0} {$attempt < 50 && [llength $config_paths] == 0} {incr attempt} {
    foreach path [get_service_paths packet] {
        if {![catch {set marker [marker_get_info $path]}] &&
            [lindex $marker 1] eq "config"} {
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

set service [claim_service packet [lindex $config_paths 0] de25_rsu_status]
set response [packet_send_command -format 32 $service {0x0000005b}]
close_service packet $service

set words {}
foreach word $response {
    lappend words [format 0x%08x [expr {$word & 0xffffffff}]]
}
puts "RSU_STATUS=$words"
exit
