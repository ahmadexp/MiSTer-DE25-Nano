package require qsys 25.1

# Solve the two Minimig video profiles on the exact production DE25-Nano
# device. Both clocks keep the native 4:1 relationship used by Minimig.
set profiles {
    {pal  113.500640 28.375160}
    {ntsc 114.750000 28.687500}
}

create_system minimig_pll_profile_probe
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

foreach profile $profiles {
    foreach {name clock_114 clock_sys} $profile break

    add_instance iopll_0 altera_iopll 21.0.0
    set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
    set_instance_parameter_value iopll_0 gui_number_of_clocks 2
    set_instance_parameter_value iopll_0 gui_output_clock_frequency0 $clock_114
    set_instance_parameter_value iopll_0 gui_output_clock_frequency1 $clock_sys
    set_instance_parameter_value iopll_0 gui_en_hvio_reconf true

    set fields [list \
        profile $name \
        requested0 $clock_114 \
        requested1 $clock_sys \
        m [get_instance_parameter_value iopll_0 multiply_factor] \
        n_hi [get_instance_parameter_value iopll_0 n_cnt_hi_div] \
        n_lo [get_instance_parameter_value iopll_0 n_cnt_lo_div] \
        n_odd [get_instance_parameter_value iopll_0 n_cnt_odd_div_duty_en] \
        n_bypass [get_instance_parameter_value iopll_0 n_cnt_bypass_en]]

    for {set index 0} {$index < 2} {incr index} {
        foreach {field parameter} {
            actual gui_actual_output_clock_frequency
            hi     c_cnt_hi_div
            lo     c_cnt_lo_div
            odd    c_cnt_odd_div_duty_en
            bypass c_cnt_bypass_en
            preset c_cnt_prst
            phase  c_cnt_ph_mux_prst
        } {
            lappend fields ${field}${index} \
                [get_instance_parameter_value iopll_0 ${parameter}${index}]
        }
    }

    set output ""
    foreach {key value} $fields {
        append output "$key=$value "
    }
    send_message info "MINIMIG_PROFILE [string trim $output]"
    remove_instance iopll_0
}
