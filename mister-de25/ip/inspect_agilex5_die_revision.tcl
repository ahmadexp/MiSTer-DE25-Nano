package require qsys 25.1

# Query the exact die type and revision associated with the DE25-Nano OPN.
# Ethernet's HVIO path exposes these normally hidden Quartus system-info
# values and contains the tool's explicit SM7 rev-A exclusion.
create_system inspect_agilex5_die_revision
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

add_instance mge_probe intel_mge_phy
send_message info "DE25 die types: [get_instance_parameter_value mge_probe DEVICE_DIE_TYPES]"
send_message info "DE25 die revisions: [get_instance_parameter_value mge_probe DEVICE_DIE_REVISIONS]"
