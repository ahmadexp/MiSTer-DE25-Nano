package require qsys 25.1

# Solve both SNES region profiles on the exact production DE25-Nano device.
# C0 clocks SDRAM, C1 is the phase-related video clock, C2 is the master
# clock, C3 drives SDRAM, and C4 captures SDRAM reads.
set profiles {
    {ntsc 85.9090800 42.9545400 21.4772700}
    {pal  85.1254784 42.5627392 21.2813696}
}

create_system snes_pll_profile_probe
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

foreach profile $profiles {
    foreach {name controller video master} $profile break
    set physical_phase_ps [expr {500000.0 / double($controller) - 500.0}]
    set capture_phase_ps  [expr {500000.0 / double($controller) + 500.0}]

    add_instance iopll_0 altera_iopll 21.0.0
    set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
    set_instance_parameter_value iopll_0 gui_number_of_clocks 5
    set_instance_parameter_value iopll_0 gui_output_clock_frequency0 $controller
    set_instance_parameter_value iopll_0 gui_output_clock_frequency1 $video
    set_instance_parameter_value iopll_0 gui_phase_shift1 -4365.0
    set_instance_parameter_value iopll_0 gui_output_clock_frequency2 $master
    set_instance_parameter_value iopll_0 gui_output_clock_frequency3 $controller
    set_instance_parameter_value iopll_0 gui_output_clock_frequency4 $controller
    set_instance_parameter_value iopll_0 gui_phase_shift3 $physical_phase_ps
    set_instance_parameter_value iopll_0 gui_phase_shift4 $capture_phase_ps
    set_instance_parameter_value iopll_0 gui_en_hvio_reconf true

    set fields [list \
        profile $name \
        requested0 $controller \
        requested1 $video \
        requested2 $master \
        phase_requested1 -4365.0 \
        phase_requested3 $physical_phase_ps \
        phase_requested4 $capture_phase_ps \
        m [get_instance_parameter_value iopll_0 multiply_factor] \
        n_hi [get_instance_parameter_value iopll_0 n_cnt_hi_div] \
        n_lo [get_instance_parameter_value iopll_0 n_cnt_lo_div] \
        n_odd [get_instance_parameter_value iopll_0 n_cnt_odd_div_duty_en] \
        n_bypass [get_instance_parameter_value iopll_0 n_cnt_bypass_en]]

    for {set index 0} {$index < 5} {incr index} {
        foreach {field parameter} {
            actual        gui_actual_output_clock_frequency
            actual_phase  gui_actual_phase_shift
            hi            c_cnt_hi_div
            lo            c_cnt_lo_div
            odd           c_cnt_odd_div_duty_en
            bypass        c_cnt_bypass_en
            preset        c_cnt_prst
            phase         c_cnt_ph_mux_prst
        } {
            lappend fields ${field}${index} \
                [get_instance_parameter_value iopll_0 ${parameter}${index}]
        }
    }

    set output ""
    foreach {key value} $fields {
        append output "$key=$value "
    }
    send_message info "SNES_PROFILE [string trim $output]"
    remove_instance iopll_0
}
