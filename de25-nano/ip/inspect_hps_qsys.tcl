package require qsys 25.1

load_system ../vendor/terasic-ghrd/qsys_top.qsys

puts "INSTANCES"
foreach instance [get_instances] {
    puts $instance
}

puts "SUBSYS_HPS_INTERFACES"
foreach interface [get_instance_interfaces subsys_hps] {
    puts $interface
}

add_instance pc110_bridge altera_avalon_mm_bridge 20.1.0

puts "PC110_BRIDGE_PARAMETERS"
foreach parameter [get_instance_parameters pc110_bridge] {
    puts "$parameter=[get_instance_parameter_value pc110_bridge $parameter]"
}

puts "PC110_BRIDGE_INTERFACES"
foreach interface [get_instance_interfaces pc110_bridge] {
    puts $interface
}
