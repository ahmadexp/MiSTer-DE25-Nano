package require qsys 25.1

# Ask the installed Agilex 5 IOPLL solver for every frequency used by MemTest.
# The emitted parameter table is the source of truth for counter legality and
# actual output frequency on the exact DE25-Nano OPN.
set frequencies {
    167 160 150 149 148 147 146 145 144 143 142 141 140 139 138 137 136 135
    134 133 132 131 130 129 128 127 126 125 124 123 122 121 120 110 100 90
    80 70 69 68 67 66 65 64 63 62.5 62 61 60 59 58 57 56 55 54 53 52 51
    50 49 48 47 46 45
}

create_system inspect_memtest_pll_profiles
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EB013BB23BE4SCS

foreach frequency $frequencies {
    add_instance iopll_0 altera_iopll 21.0.0
    set_instance_parameter_value iopll_0 gui_reference_clock_frequency 50.0
    set_instance_parameter_value iopll_0 gui_number_of_clocks 2
    set_instance_parameter_value iopll_0 gui_output_clock_frequency0 $frequency
    set_instance_parameter_value iopll_0 gui_output_clock_frequency1 $frequency
    # Reads are captured with this same forwarded clock, so its phase can favor
    # command/write setup without reducing the input window. Keep 0.5 ns before
    # the nominal opposite controller edge: phase = period/2 - 0.5 ns.
    set phase_ps [expr {500000.0 / double($frequency) - 500.0}]
    set_instance_parameter_value iopll_0 gui_phase_shift1 $phase_ps
    set_instance_parameter_value iopll_0 gui_en_hvio_reconf true

    set actual [get_instance_parameter_value iopll_0 gui_actual_output_clock_frequency0]
    set m [get_instance_parameter_value iopll_0 multiply_factor]
    set n_hi [get_instance_parameter_value iopll_0 n_cnt_hi_div]
    set n_lo [get_instance_parameter_value iopll_0 n_cnt_lo_div]
    set n_odd [get_instance_parameter_value iopll_0 n_cnt_odd_div_duty_en]
    set n_bypass [get_instance_parameter_value iopll_0 n_cnt_bypass_en]
    set c0_hi [get_instance_parameter_value iopll_0 c_cnt_hi_div0]
    set c0_lo [get_instance_parameter_value iopll_0 c_cnt_lo_div0]
    set c0_odd [get_instance_parameter_value iopll_0 c_cnt_odd_div_duty_en0]
    set c0_bypass [get_instance_parameter_value iopll_0 c_cnt_bypass_en0]
    set c0_preset [get_instance_parameter_value iopll_0 c_cnt_prst0]
    set c0_phase [get_instance_parameter_value iopll_0 c_cnt_ph_mux_prst0]
    set c1_hi [get_instance_parameter_value iopll_0 c_cnt_hi_div1]
    set c1_lo [get_instance_parameter_value iopll_0 c_cnt_lo_div1]
    set c1_odd [get_instance_parameter_value iopll_0 c_cnt_odd_div_duty_en1]
    set c1_bypass [get_instance_parameter_value iopll_0 c_cnt_bypass_en1]
    set c1_preset [get_instance_parameter_value iopll_0 c_cnt_prst1]
    set c1_phase [get_instance_parameter_value iopll_0 c_cnt_ph_mux_prst1]
    set actual1 [get_instance_parameter_value iopll_0 gui_actual_output_clock_frequency1]
    set actual_phase1 [get_instance_parameter_value iopll_0 gui_actual_phase_shift1]
    send_message info "MEMTEST_PROFILE requested=$frequency actual=$actual actual1=$actual1 phase1=$actual_phase1 m=$m n_hi=$n_hi n_lo=$n_lo n_odd=$n_odd n_bypass=$n_bypass c0_hi=$c0_hi c0_lo=$c0_lo c0_odd=$c0_odd c0_bypass=$c0_bypass c0_preset=$c0_preset c0_phase=$c0_phase c1_hi=$c1_hi c1_lo=$c1_lo c1_odd=$c1_odd c1_bypass=$c1_bypass c1_preset=$c1_preset c1_phase=$c1_phase"
    remove_instance iopll_0
}
