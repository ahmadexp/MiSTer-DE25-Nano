# Inventory the services currently visible through the DE25-Nano JTAG cable.
# This script is read-only and does not require a matching SOF to be loaded.

refresh_connections

set service_types {
    device
    master
    processor
    monitor
    bytestream
    jtag_debug
    sld
}

foreach service_type $service_types {
    if {[catch {set paths [get_service_paths $service_type]} message]} {
        puts "$service_type: unavailable ($message)"
        continue
    }

    puts "$service_type: [llength $paths]"
    set index 0
    foreach path $paths {
        puts "  $index $path"
        incr index
    }
}

exit
