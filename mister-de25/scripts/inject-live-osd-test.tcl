# Fill the live Menu OSD RAM with a high-contrast diagnostic pattern through
# the JTAG-to-Avalon master. Stop MiSTer Main before running this script so it
# is the only writer of the general-purpose handshake PIO.

if {$argc != 1} {
    puts stderr "Usage: system-console --script=inject-live-osd-test.tcl DESIGN.sof"
    exit 2
}

set design_file [lindex $argv 0]
if {![file isfile $design_file]} {
    error "SOF not found: $design_file"
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
    error "Expected exactly one fpga_m JTAG master, found [llength $candidates]"
}

set master [claim_service master [lindex $candidates 0] mister_de25_osd_test]
set gp_out_address 0x20000
set gp_in_address  0x20010
set strobe_mask     0x00020000
set osd_mask        0x00080000

proc gp_write {master address value} {
    master_write_32 $master $address [list $value]
}

proc spi_byte {master out_address in_address base value} {
    set low  [expr {$base | ($value & 0xff)}]
    set high [expr {$low | 0x00020000}]
    gp_write $master $out_address $low
    gp_write $master $out_address $high
    gp_write $master $out_address $low

    # One JTAG transaction is many fabric clocks, but also verify that the
    # acknowledge returned low before advancing to the next byte.
    set gp_in [lindex [master_read_32 $master $in_address 1] 0]
    if {$gp_in & 0x00020000} {
        error [format "SPI acknowledge remained high: 0x%08X" $gp_in]
    }
}

set saved_gp_out [lindex [master_read_32 $master $gp_out_address 1] 0]
set released_base [expr {($saved_gp_out & 0xe0000000) | $osd_mask}]

if {[catch {
    puts [format "Saved GPO 0x%08X" $saved_gp_out]
    for {set line 0} {$line < 19} {incr line} {
        spi_byte $master $gp_out_address $gp_in_address $released_base \
            [expr {0x20 | $line}]
        for {set column 0} {$column < 256} {incr column} {
            set stripe [expr {(($column / 16) + $line) & 1}]
            spi_byte $master $gp_out_address $gp_in_address $released_base \
                [expr {$stripe ? 0xff : 0x00}]
        }
        gp_write $master $gp_out_address [expr {$released_base & ~$osd_mask}]
        puts [format "Wrote OSD line %d" $line]
    }

    spi_byte $master $gp_out_address $gp_in_address $released_base 0x41
    gp_write $master $gp_out_address [expr {$saved_gp_out & ~$strobe_mask}]
    puts "Enabled live OSD test pattern"
} message options]} {
    gp_write $master $gp_out_address [expr {$saved_gp_out & ~$strobe_mask}]
    close_service master $master
    return -options $options $message
}

close_service master $master
