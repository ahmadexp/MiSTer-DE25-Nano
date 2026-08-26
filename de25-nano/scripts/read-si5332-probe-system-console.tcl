# Read the DE25 Si5332B read-only probe through Agilex System Console.

if {[info exists ::env(DE25_SI5332_PROBE_SOF)]} {
    set design_file $::env(DE25_SI5332_PROBE_SOF)
} else {
    set design_file "quartus/output_files_si5332_probe/DE25_SI5332_PROBE.sof"
}
if {![file isfile $design_file]} {
    error "SOF not found: $design_file"
}

set design [design_load $design_file]
set devices {}
for {set attempt 0} {$attempt < 5 && [llength $devices] == 0} {incr attempt} {
    refresh_connections
    set devices [get_service_paths device]
    if {[llength $devices] == 0} {
        # A remote JTAG server can expose the physical FPGA first as a
        # loopback service, without creating the optional device alias.
        set devices [get_service_paths loopback]
    }
    if {[llength $devices] == 0} {
        after 100
    }
}
if {[llength $devices] != 1} {
    error "Expected exactly one FPGA device, found [llength $devices]"
}

set design_instance [design_instantiate $design]
design_link $design_instance [lindex $devices 0]
refresh_connections

set issp_paths [get_service_paths issp]
if {[llength $issp_paths] != 1} {
    error "Expected exactly one ISSP service, found [llength $issp_paths]: $issp_paths"
}

set service [claim_service issp [lindex $issp_paths 0] de25_si5332_reader]
set instance_info [issp_get_instance_info $service]
set raw_status [issp_read_probe_data $service]
close_service issp $service

# System Console returns an integer for this 32-bit probe.
puts "raw_status=$raw_status"
set status [expr {$raw_status & 0xffffffff}]
set signature [expr {($status >> 16) & 0xffff}]
set state     [expr {($status >> 8) & 0x7}]
set fault_state [expr {($status >> 11) & 0x1f}]
set fault     [expr {($status >> 7) & 1}]
set done      [expr {($status >> 6) & 1}]
set ack_6b    [expr {($status >> 5) & 1}]
set ack_6a    [expr {($status >> 4) & 1}]
set sda       [expr {($status >> 3) & 1}]
set scl       [expr {($status >> 2) & 1}]
set sda_low   [expr {($status >> 1) & 1}]
set scl_low   [expr {$status & 1}]

puts "instance=$instance_info"
puts [format "status=0x%08X signature=0x%04X state=%d fault_state=%d done=%d fault=%d" \
    $status $signature $state $fault_state $done $fault]
puts [format "SCL=%d SDA=%d drive_low(SCL=%d SDA=%d)" \
    $scl $sda $scl_low $sda_low]
puts [format "ACK_0x6A=%d ACK_0x6B=%d" $ack_6a $ack_6b]

if {$signature != 0x5332 || !$done || $fault} {
    exit 1
}
exit 0
