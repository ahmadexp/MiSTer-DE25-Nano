# Read the live MiSTer general-purpose handshake through the design's
# JTAG-to-Avalon master. This is diagnostic only and never writes the fabric.

if {$argc < 1 || $argc > 2} {
    puts stderr "Usage: system-console --script=read-live-gp.tcl DESIGN.sof ?SAMPLES?"
    exit 2
}

set design_file [lindex $argv 0]
set sample_count 16
if {$argc == 2} {
    set sample_count [lindex $argv 1]
}

if {![file isfile $design_file]} {
    error "SOF not found: $design_file"
}
if {![string is integer -strict $sample_count] || $sample_count < 1} {
    error "SAMPLES must be a positive integer"
}

set design [design_load $design_file]
set devices [get_service_paths device]
if {[llength $devices] != 1} {
    error "Expected exactly one FPGA device, found [llength $devices]"
}

set design_instance [design_instantiate $design]
design_link $design_instance [lindex $devices 0]
refresh_connections

set paths [get_service_paths master]
set candidates [lsearch -all -inline -glob $paths "*fpga_m*"]
if {[llength $candidates] != 1} {
    puts stderr "Available Avalon masters:"
    foreach path $paths {
        puts stderr "  $path"
    }
    error "Expected exactly one fpga_m JTAG master, found [llength $candidates]"
}

set service_path [lindex $candidates 0]
set master [claim_service master $service_path mister_de25_gp_reader]

if {[catch {
    puts "Using $service_path"
    for {set sample 0} {$sample < $sample_count} {incr sample} {
        set gp_out [lindex [master_read_32 $master 0x20000 1] 0]
        set gp_in  [lindex [master_read_32 $master 0x20010 1] 0]
        puts [format "%02d GPO=0x%08X GPI=0x%08X ss=%d%d%d clk=%d ack=%d reset=%d diag=%d" \
            $sample $gp_out $gp_in \
            [expr {($gp_out >> 20) & 1}] \
            [expr {($gp_out >> 19) & 1}] \
            [expr {($gp_out >> 18) & 1}] \
            [expr {($gp_out >> 17) & 1}] \
            [expr {($gp_in >> 17) & 1}] \
            [expr {($gp_out >> 30) & 3}] \
            [expr {($gp_in >> 21) & 0x3f}]]
        after 100
    }
} message options]} {
    close_service master $master
    return -options $options $message
}

close_service master $master
