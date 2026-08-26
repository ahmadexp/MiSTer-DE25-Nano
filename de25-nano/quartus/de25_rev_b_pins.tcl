# Import only the pin assignments used by the PC110 target from Terasic's
# official DE25-Nano rev-B GHRD.  Parsing each QSF line as a Tcl list keeps bus
# names such as LPDDR4A_DQ[0] literal and avoids command substitution.
set pins_script_dir [file dirname [info script]]
set reference_qsf [file normalize [file join $pins_script_dir .. vendor terasic-ghrd golden_top.qsf]]

if {![file exists $reference_qsf]} {
    post_message -type error "Missing Terasic rev-B pin reference: $reference_qsf"
    post_message -type error "Run ../scripts/import-terasic-ghrd.sh first."
    return -code error
}

set pin_file [open $reference_qsf r]
set pin_text [read $pin_file]
close $pin_file

set target_pattern {^(CLOCK0_50|KEY|SW|LED|LPDDR4A_|HDMI_|FPGA_UART_|HPS_|FAN_ALERT_n)}

foreach line [split $pin_text "\n"] {
    set words [string trim $line]
    if {[llength $words] == 0} {
        continue
    }

    set assignment_command [lindex $words 0]
    if {$assignment_command ni {set_instance_assignment set_location_assignment}} {
        continue
    }

    set to_index [lsearch -exact $words -to]
    if {$to_index < 0 || $to_index + 1 >= [llength $words]} {
        continue
    }
    set target [lindex $words [expr {$to_index + 1}]]
    if {![regexp $target_pattern $target]} {
        continue
    }

    if {$assignment_command eq "set_location_assignment"} {
        set location [lindex $words 1]
        set_location_assignment $location -to $target
    } else {
        set name_index [lsearch -exact $words -name]
        set assignment_name [lindex $words [expr {$name_index + 1}]]
        set assignment_value [lindex $words [expr {$name_index + 2}]]
        set_instance_assignment -name $assignment_name $assignment_value -to $target
    }
}

