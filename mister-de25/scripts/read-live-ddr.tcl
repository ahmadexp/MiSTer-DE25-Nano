# Read selected DE25 MiSTer DDR locations through the live FPGA-side Avalon
# master. This observes the same LPDDR4 fabric path used by cores, independently
# of Linux /dev/mem mappings and ARM cache attributes.

if {$argc != 1} {
    puts stderr "Usage: system-console --script=read-live-ddr.tcl DESIGN.sof"
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
    if {[llength $devices] == 0} {
        after 50
    }
}
if {[llength $devices] != 1} {
    error "Expected exactly one FPGA device, found [llength $devices]"
}

set design [design_load $design_file]
set design_instance [design_instantiate $design]
design_link $design_instance [lindex $devices 0]
refresh_connections

set paths [get_service_paths master]
set candidates [lsearch -all -inline -glob $paths "*hps_f2sdram*"]
if {[llength $candidates] != 1} {
    puts stderr "Available Avalon masters:"
    foreach path $paths {
        puts stderr "  $path"
    }
    error "Expected exactly one hps_f2sdram JTAG master, found [llength $candidates]"
}

set master [claim_service master [lindex $candidates 0] de25_ddr_reader]
if {[catch {
    foreach {label address words} {
        LOW_RAM 0xB0000000 16
        BDA      0xB0000400 16
        BDA_VIDEO 0xB0000440 16
        BOOT1    0xB00C0000 16
        TEXT_RAM 0xB00B8000 16
        BOOT0    0xB00F0000 16
    } {
        set values [master_read_32 $master $address $words]
        puts [format "%s @ 0x%08X" $label $address]
        set index 0
        foreach value $values {
            puts [format "  +0x%02X 0x%08X" [expr {$index * 4}] $value]
            incr index
        }
    }
} message options]} {
    close_service master $master
    return -options $options $message
}

close_service master $master
flush stdout
exit 0
