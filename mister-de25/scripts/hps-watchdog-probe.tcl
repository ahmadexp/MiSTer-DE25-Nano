set index [lindex $argv 0]
if {$index eq ""} {
    error "Usage: hps-watchdog-probe.tcl MASTER_INDEX"
}

set masters [get_service_paths master]
if {$index >= [llength $masters]} {
    error "JTAG master index $index is unavailable"
}

set master [lindex $masters $index]
open_service master $master
puts "MASTER_INDEX=$index"
puts "MASTER=$master"
puts "CR=[master_read_32 $master 0x10d00200 1]"
puts "TORR=[master_read_32 $master 0x10d00204 1]"
puts "CCVR=[master_read_32 $master 0x10d00208 1]"
puts "COMP_PARAMS_1=[master_read_32 $master 0x10d002f4 1]"
puts "COMP_VERSION=[master_read_32 $master 0x10d002f8 1]"
puts "COMP_TYPE=[master_read_32 $master 0x10d002fc 1]"
close_service master $master
exit
