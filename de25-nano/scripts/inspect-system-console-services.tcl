# Print live System Console services for JTAG tunnel diagnostics.

refresh_connections
puts [help design_link]
puts "service_types=[get_service_types]"
foreach service_type [get_service_types] {
    puts "$service_type=[get_service_paths $service_type]"
}
flush stdout
exit 0
