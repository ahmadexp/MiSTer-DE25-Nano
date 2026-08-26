# Read the non-destructive Si5332B address-probe result through the existing
# PC110 JTAG-to-Avalon master.

if {[info exists ::env(DE25_PC110_PROBE_SOF)]} {
    set design_file $::env(DE25_PC110_PROBE_SOF)
} else {
    set design_file "quartus/output_files_pc110/DE25_MISTER_PC110.sof"
}
if {![file isfile $design_file]} {
    error "SOF not found: $design_file"
}

set design [design_load $design_file]
set devices {}
for {set attempt 0} {$attempt < 20 && [llength $devices] == 0} {incr attempt} {
    refresh_connections
    set devices [get_service_paths device]
    if {[llength $devices] == 0} {
        after 100
    }
}
if {[llength $devices] != 1} {
    error "Expected exactly one FPGA device, found [llength $devices]"
}

set design_instance [design_instantiate $design]
design_link $design_instance [lindex $devices 0]

set candidates {}
for {set attempt 0} {$attempt < 20 && [llength $candidates] == 0} {incr attempt} {
    refresh_connections
    set paths [get_service_paths master]
    set candidates [lsearch -all -inline -glob $paths "*fpga_m*"]
    if {[llength $candidates] == 0} {
        after 100
    }
}
if {[llength $candidates] != 1} {
    error "Expected exactly one fpga_m JTAG master, found [llength $candidates]"
}

set master [claim_service master [lindex $candidates 0] si5332_probe_reader]
set gp_out_address 0x20000
set gp_in_address  0x20010
set gp_out [lindex [master_read_32 $master $gp_out_address 1] 0]
set changed_gp_out 0

if {!(($gp_out >> 31) & 1)} {
    # Select the live-response word without changing any other GPO bit. There
    # is no I/O strobe unless Main already asserted GPO[17].
    master_write_32 $master $gp_out_address [expr {$gp_out | 0x80000000}]
    set changed_gp_out 1
    after 5
}

set gp_in [lindex [master_read_32 $master $gp_in_address 1] 0]
if {$changed_gp_out} {
    master_write_32 $master $gp_out_address $gp_out
}
close_service master $master

set diagnostic [expr {($gp_in >> 21) & 0x3f}]
set fault      [expr {($diagnostic >> 5) & 1}]
set done       [expr {($diagnostic >> 4) & 1}]
set ack_6b     [expr {($diagnostic >> 3) & 1}]
set ack_6a     [expr {($diagnostic >> 2) & 1}]
set sda        [expr {($diagnostic >> 1) & 1}]
set scl        [expr {$diagnostic & 1}]

puts [format "GPO=0x%08X GPI=0x%08X diagnostic=0x%02X" \
    $gp_out $gp_in $diagnostic]
puts [format "SCL=%d SDA=%d done=%d fault=%d ACK_0x6A=%d ACK_0x6B=%d" \
    $scl $sda $done $fault $ack_6a $ack_6b]
if {$fault} {
    puts [format "fault_state=%d" [expr {$diagnostic & 0x1f}]]
}
flush stdout

if {!$done || $fault} {
    exit 1
}
exit 0
