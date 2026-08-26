package require ::quartus::insystem_source_probe

set hardware_names [get_hardware_names]
if {[llength $hardware_names] != 1} {
    error "Expected exactly one JTAG cable, found [llength $hardware_names]: $hardware_names"
}
set hardware_name [lindex $hardware_names 0]

set device_names [get_device_names -hardware_name $hardware_name]
if {[llength $device_names] != 1} {
    error "Expected exactly one JTAG device, found [llength $device_names]: $device_names"
}
set device_name [lindex $device_names 0]

set instances [get_insystem_source_probe_instance_info \
    -hardware_name $hardware_name -device_name $device_name]
set probe_index -1
foreach instance $instances {
    if {[lindex $instance 3] eq "S533"} {
        set probe_index [lindex $instance 0]
    }
}
if {$probe_index < 0} {
    error "S533 read-only probe was not found: $instances"
}

start_insystem_source_probe \
    -hardware_name $hardware_name -device_name $device_name
set status_hex [read_probe_data -instance_index $probe_index -value_in_hex]
end_insystem_source_probe

scan $status_hex %x status
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

puts [format "status=0x%08X signature=0x%04X state=%d fault_state=%d done=%d fault=%d" \
    $status $signature $state $fault_state $done $fault]
puts [format "SCL=%d SDA=%d drive_low(SCL=%d SDA=%d)" \
    $scl $sda $scl_low $sda_low]
puts [format "ACK_0x6A=%d ACK_0x6B=%d" $ack_6a $ack_6b]

if {$signature != 0x5332 || !$done || $fault} {
    exit 1
}
exit 0
