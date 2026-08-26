# Preload and verify the private PC110 ROMs through the GHRD JTAG-to-SDRAM
# master. Run this only after HPS LPDDR has initialized and the PC110 core is
# held in reset with SW0 low.

if {$argc != 3} {
    puts stderr "Usage: system-console --script=preload-roms.tcl DESIGN.sof PC110_BIOS.bin PC110_FONT.bin"
    exit 2
}

set design_file [lindex $argv 0]
set bios_file [lindex $argv 1]
set font_file [lindex $argv 2]

proc require_file_size {path expected_size} {
    if {![file isfile $path]} {
        error "File not found: $path"
    }
    if {[file size $path] != $expected_size} {
        error "Unexpected size for $path: got [file size $path], expected $expected_size"
    }
}

proc write_file {master path address} {
    set stream [open $path rb]
    fconfigure $stream -translation binary -encoding binary
    set offset 0
    set chunk_size 4096

    while {![eof $stream]} {
        set data [read $stream $chunk_size]
        set count [string length $data]
        if {$count == 0} {
            break
        }

        binary scan $data c* values
        master_write_8 $master [expr {$address + $offset}] $values
        incr offset $count
    }

    close $stream
    puts [format "Wrote %d bytes at 0x%08x" $offset $address]
    flush stdout
}

proc verify_file {master path address} {
    set dump_file "$path.readback"
    file delete -force $dump_file
    master_read_to_file $master $dump_file $address [file size $path]

    set expected_stream [open $path rb]
    fconfigure $expected_stream -translation binary -encoding binary
    set expected [read $expected_stream]
    close $expected_stream

    set actual_stream [open $dump_file rb]
    fconfigure $actual_stream -translation binary -encoding binary
    set actual [read $actual_stream]
    close $actual_stream
    file delete -force $dump_file

    if {$actual ne $expected} {
        binary scan [string range $expected 0 15] H* expected_prefix
        binary scan [string range $actual 0 15] H* actual_prefix
        error [format "Verification failed for %s at 0x%08x: expected %s, read %s" \
            $path $address $expected_prefix $actual_prefix]
    }

    puts [format "Verified %d bytes at 0x%08x" [string length $actual] $address]
    flush stdout
}

if {![file isfile $design_file]} {
    error "SOF not found: $design_file"
}

require_file_size $bios_file 262144
require_file_size $font_file 1048576

set design [design_load $design_file]
set devices [get_service_paths device]
if {[llength $devices] != 1} {
    puts stderr "Available FPGA devices:"
    foreach path $devices {
        puts stderr "  $path"
    }
    puts stderr "Expected exactly one FPGA device, found [llength $devices]"
    exit 1
}

set design_instance [design_instantiate $design]
design_link $design_instance [lindex $devices 0]
set candidates {}
for {set attempt 0} {$attempt < 100 && [llength $candidates] == 0} {incr attempt} {
    refresh_connections
    set paths [get_service_paths master]
    set candidates [lsearch -all -inline -glob $paths "*hps_f2sdram*"]
    if {[llength $candidates] == 0} {
        after 50
    }
}
if {[llength $candidates] != 1} {
    puts stderr "Available Avalon masters:"
    foreach path $paths {
        puts stderr "  $path"
    }
    puts stderr "Expected exactly one hps_f2sdram JTAG master, found [llength $candidates]"
    exit 1
}

set service_path [lindex $candidates 0]
set master [claim_service master $service_path pc110_rom_loader]

if {[catch {
    puts "Using $service_path"
    puts "Writing PC110 BIOS..."
    write_file $master $bios_file 0xb00c0000
    puts "Writing PC110 font..."
    write_file $master $font_file 0xb2000000

    puts "Verifying PC110 BIOS..."
    flush stdout
    verify_file $master $bios_file 0xb00c0000
    puts "Verifying PC110 font..."
    flush stdout
    verify_file $master $font_file 0xb2000000
} message options]} {
    close_service master $master
    puts stderr $message
    exit 1
}

close_service master $master
puts "PC110 ROM preload complete. Raise SW0 to release the core."
flush stdout
exit 0
