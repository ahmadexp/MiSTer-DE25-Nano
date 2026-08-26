# Request an HPS-only cold reboot through the Agilex SDM packet service.  This
# preserves the configured FPGA fabric and is suitable for remote recovery
# when the HPS-facing Avalon bridge is unavailable.

refresh_connections

set config_paths {}
for {set attempt 0} {$attempt < 50 && [llength $config_paths] == 0} {incr attempt} {
    foreach path [get_service_paths packet] {
        if {[catch {set marker [marker_get_info $path]} message]} {
            puts "packet marker unavailable: $path ($message)"
            continue
        }
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

set service [claim_service packet [lindex $config_paths 0] de25_hps_reboot]
set response [packet_send_command -format 32 $service {0x00000047}]
close_service packet $service

set words {}
foreach word $response {
    lappend words [format 0x%08x [expr {$word & 0xffffffff}]]
}
puts "REBOOT_HPS_RESPONSE=$words"
puts "HPS cold reboot requested through SDM"
exit
