# Clear ao486's legacy status[0] reset through the live MiSTer UIO transport.
# Stop Main first so JTAG is the only writer of the GPO handshake register.

if {$argc != 1} {
    puts stderr "Usage: system-console --script=release-live-ao486-status-reset.tcl DESIGN.sof"
    exit 2
}

set design_file [lindex $argv 0]
if {![file isfile $design_file]} {
    error "SOF not found: $design_file"
}

set devices {}
for {set attempt 0} {$attempt < 100 && [llength $devices] == 0} {incr attempt} {
    refresh_connections
    set devices [get_service_paths device]
    if {[llength $devices] == 0} { after 50 }
}
if {[llength $devices] != 1} {
    error "Expected exactly one FPGA device, found [llength $devices]"
}

set design [design_load $design_file]
set instance [design_instantiate $design]
design_link $instance [lindex $devices 0]
refresh_connections

set paths [get_service_paths master]
set candidates [lsearch -all -inline -glob $paths "*fpga_m*"]
if {[llength $candidates] != 1} {
    error "Expected exactly one fpga_m JTAG master, found [llength $candidates]"
}

set master [claim_service master [lindex $candidates 0] ao486_reset_release]
set gp_out_address 0x20000
set gp_in_address  0x20010
set strobe_mask     0x00020000
set uio_mask        0x00100000

proc gp_write {master address value} {
    master_write_32 $master $address [list $value]
}

proc spi_word {master out_address in_address base value} {
    set low  [expr {$base | ($value & 0xffff)}]
    set high [expr {$low | 0x00020000}]
    gp_write $master $out_address $low
    gp_write $master $out_address $high
    gp_write $master $out_address $low
    set gp_in [lindex [master_read_32 $master $in_address 1] 0]
    if {$gp_in & 0x00020000} {
        error [format "UIO acknowledge remained high: 0x%08X" $gp_in]
    }
}

set saved [lindex [master_read_32 $master $gp_out_address 1] 0]
# Preserve Main's reset state and clear every select/strobe before selecting UIO.
set base [expr {($saved & 0xc0000000) | $uio_mask}]

if {[catch {
    puts [format "Saved GPO 0x%08X" $saved]
    spi_word $master $gp_out_address $gp_in_address $base 0x001e
    for {set word 0} {$word < 8} {incr word} {
        spi_word $master $gp_out_address $gp_in_address $base 0x0000
    }
    gp_write $master $gp_out_address [expr {$base & ~$uio_mask}]
    # Exercise the same assert/release states Main uses around persona loads.
    # This confirms whether ao486's edge-only local latch missed that release.
    gp_write $master $gp_out_address 0x40000000
    after 100
    gp_write $master $gp_out_address 0x80000000
    after 100
    set gp_in [lindex [master_read_32 $master $gp_in_address 1] 0]
    puts [format "Released GPO 0x%08X GPI 0x%08X diag=%d" \
        [expr {$base & ~$uio_mask}] $gp_in [expr {($gp_in >> 21) & 0x3f}]]
} message options]} {
    gp_write $master $gp_out_address [expr {$saved & ~$strobe_mask}]
    close_service master $master
    return -options $options $message
}

close_service master $master
flush stdout
exit 0
