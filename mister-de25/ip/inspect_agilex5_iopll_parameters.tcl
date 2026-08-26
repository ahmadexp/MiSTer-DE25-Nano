package require qsys 25.1

create_system inspect_agilex5_iopll_parameters
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS
add_instance iopll_0 altera_iopll 21.0.0
set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
set_instance_parameter_value iopll_0 gui_number_of_clocks 1
set_instance_parameter_value iopll_0 gui_output_clock_frequency0 167.0
set_instance_parameter_value iopll_0 gui_en_hvio_reconf true

foreach parameter {gui_location_type gui_use_coreclk gui_include_iossm gui_en_hvio_reconf gui_en_iossm_reconf gui_user_base_address} {
    send_message info "IOPLL_PARAM $parameter=[get_instance_parameter_value iopll_0 $parameter]"
    foreach property {ALLOWED_RANGES DESCRIPTION DISPLAY_NAME ENABLED VISIBLE} {
        if {![catch {set value [get_instance_parameter_property iopll_0 $parameter $property]}]} {
            send_message info "IOPLL_PROPERTY $parameter $property=$value"
        }
    }
}

# Probe the production alternative after the direct HVIO interface passes
# synthesis but fails package placement.
set_instance_parameter_value iopll_0 gui_en_hvio_reconf false
set_instance_parameter_value iopll_0 gui_en_iossm_reconf true
send_message info "IOSSM interfaces: [get_instance_interfaces iopll_0]"

add_instance cal_0 emif_ph2_cal 4.3.0
set_instance_parameter_value cal_0 NUM_CALBUS_PERIPHS 0
set_instance_parameter_value cal_0 NUM_CALBUS_PLLS 1
set_instance_parameter_value cal_0 PORT_S_AXIL_MODE PORT_S_AXIL_MODE_FAB
send_message info "EMIF_CAL interfaces: [get_instance_interfaces cal_0]"

foreach instance {iopll_0 cal_0} {
    foreach iface [get_instance_interfaces $instance] {
        send_message info "INTERFACE $instance.$iface ports=[get_instance_interface_ports $instance $iface]"
        foreach property {TYPE ROLE ENABLED EXPORT_OF} {
            if {![catch {set value [get_instance_interface_property $instance $iface $property]}]} {
                send_message info "INTERFACE_PROPERTY $instance.$iface $property=$value"
            }
        }
    }
}

save_system inspect_agilex5_iopll_parameters.qsys
