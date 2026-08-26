# Request a full Agilex remote-system update from QSPI through the SDM packet
# service. Unlike REBOOT_HPS (mailbox command 0x47), RSU_UPDATE (0x5c)
# restarts the complete HPS-first configuration sequence and therefore reloads
# the HPS I/O handoff. The command takes the 64-bit QSPI image address as two
# little-endian 32-bit words. The DE25 recovery JIC stores its image at zero.

if {$argc != 1 || [lindex $argv 0] ne "RECONFIGURE-VERIFIED-QSPI"} {
    puts stderr "Usage: system-console --script=reconfigure-from-qspi-sdm.tcl RECONFIGURE-VERIFIED-QSPI"
    exit 2
}

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

puts "Requesting full reconfiguration from verified QSPI address 0"
set service [claim_service packet [lindex $config_paths 0] de25_qspi_reconfigure]

# Serial Flash Loader programming can leave the SDM QSPI service closed.
# Open it for this packet client before asking RSU to read the image.
set open_response [packet_send_command -format 32 $service {0x00000032}]
set open_status 0xffffffff
if {[llength $open_response] == 1} {
    set open_status [expr {[lindex $open_response 0] & 0xffffffff}]
}
puts [format "QSPI_OPEN_RESPONSE=0x%08x" $open_status]
if {$open_status != 0} {
    close_service packet $service
    puts stderr "SDM rejected QSPI_OPEN; QSPI reconfiguration did not start"
    exit 1
}
set close_response [packet_send_command -format 32 $service {0x00000033}]
set close_status 0xffffffff
if {[llength $close_response] == 1} {
    set close_status [expr {[lindex $close_response 0] & 0xffffffff}]
}
puts [format "QSPI_CLOSE_RESPONSE=0x%08x" $close_status]
if {$close_status != 0} {
    close_service packet $service
    puts stderr "SDM rejected QSPI_CLOSE; QSPI reconfiguration did not start"
    exit 1
}

# MBOX_RSU_UPDATE = 92 (0x5c), followed by the low and high address words.
# Mailbox header bits 22:12 carry the two-word argument length, giving 0x205c.
# A successful request can remove the JTAG service before a response arrives.
if {[catch {
    set response [packet_send_command -format 32 $service \
        {0x0000205c 0x00000000 0x00000000}]
} message]} {
    if {[string match -nocase "*disconnect*" $message] ||
        [string match -nocase "*closed*" $message] ||
        [string match -nocase "*service*unavailable*" $message]} {
        catch {close_service packet $service}
        puts "RSU request disconnected the configuration service: $message"
        puts "Full QSPI reconfiguration requested"
        exit 0
    }
    catch {close_service packet $service}
    puts stderr "RSU_UPDATE request failed before reconfiguration: $message"
    exit 1
}

set words {}
foreach word $response {
    lappend words [format 0x%08x [expr {$word & 0xffffffff}]]
}
puts "RSU_UPDATE_RESPONSE=$words"
if {[llength $response] != 1 || ([lindex $response 0] & 0xffffffff) != 0} {
    close_service packet $service
    puts stderr "SDM rejected RSU_UPDATE; QSPI reconfiguration did not start"
    exit 1
}
close_service packet $service
puts "Full QSPI reconfiguration requested"
exit
