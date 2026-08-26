package require ::quartus::project
package require ::quartus::sta

set project DE25_MISTER_PC110
if {[llength $quartus(args)] > 0} {
    set project [lindex $quartus(args) 0]
}

project_open $project -revision $project
create_timing_netlist
read_sdc
update_timing_netlist

foreach port_name {HDMI_TX_CLK HDMI_MCLK HDMI_SCLK HDMI_LRCLK HDMI_I2S} {
    set port [get_ports $port_name]
    set clocks [get_clocks -nowarn -of_objects $port]
    puts "$port_name clocks: [get_collection_size $clocks]"
    foreach_in_collection clock $clocks {
        puts "  [get_clock_info -name $clock] period=[get_clock_info -period $clock]"
    }
}

foreach keeper_pattern {{*|audio|bit_clock} {*audio|bit_clock} {*bit_clock*}} {
    set keepers [get_keepers -nowarn $keeper_pattern]
    puts "$keeper_pattern keepers: [get_collection_size $keepers]"
    foreach_in_collection keeper $keepers {
        puts "  [get_node_info -name $keeper]"
    }
}

delete_timing_netlist
project_close
