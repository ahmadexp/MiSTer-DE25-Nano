package require qsys 25.1

# Ask the installed Agilex 5 IOPLL solver for complete SMS NTSC and PAL
# profiles. C0 clocks the controller. C1 launches the SDRAM clock early in
# the opposite half-cycle, and C2 captures reads on the controller edge.
set profiles {
    {ntsc 53.693175}
    {pal  53.203424}
}

create_system inspect_sms_pll_profiles
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

foreach profile $profiles {
    foreach {name controller} $profile break
    set physical_phase_ps [expr {500000.0 / double($controller) - 2000.0}]
    set capture_phase_ps  0.0

    add_instance iopll_0 altera_iopll 21.0.0
    set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
    set_instance_parameter_value iopll_0 gui_number_of_clocks 3
    set_instance_parameter_value iopll_0 gui_output_clock_frequency0 $controller
    set_instance_parameter_value iopll_0 gui_output_clock_frequency1 $controller
    set_instance_parameter_value iopll_0 gui_output_clock_frequency2 $controller
    set_instance_parameter_value iopll_0 gui_phase_shift1 $physical_phase_ps
    set_instance_parameter_value iopll_0 gui_phase_shift2 $capture_phase_ps
    set_instance_parameter_value iopll_0 gui_en_hvio_reconf true

    set fields [list \
        profile $name \
        requested0 $controller \
        phase_requested1 $physical_phase_ps \
        phase_requested2 $capture_phase_ps \
        m [get_instance_parameter_value iopll_0 multiply_factor] \
        n_hi [get_instance_parameter_value iopll_0 n_cnt_hi_div] \
        n_lo [get_instance_parameter_value iopll_0 n_cnt_lo_div] \
        n_odd [get_instance_parameter_value iopll_0 n_cnt_odd_div_duty_en] \
        n_bypass [get_instance_parameter_value iopll_0 n_cnt_bypass_en]]

    for {set index 0} {$index < 3} {incr index} {
        foreach {field parameter} {
            actual       gui_actual_output_clock_frequency
            actual_phase gui_actual_phase_shift
            hi           c_cnt_hi_div
            lo           c_cnt_lo_div
            odd          c_cnt_odd_div_duty_en
            bypass       c_cnt_bypass_en
            preset       c_cnt_prst
            phase        c_cnt_ph_mux_prst
        } {
            lappend fields ${field}${index} \
                [get_instance_parameter_value iopll_0 ${parameter}${index}]
        }
    }

    set output ""
    foreach {key value} $fields {
        append output "$key=$value "
    }
    send_message info "SMS_PROFILE [string trim $output]"
    remove_instance iopll_0
}
