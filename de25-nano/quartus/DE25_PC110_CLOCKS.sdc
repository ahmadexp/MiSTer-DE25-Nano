create_clock -name CLOCK0_50 -period 20.000 [get_ports CLOCK0_50]

# LEDs are human-visible heartbeat indicators, not source-synchronous outputs.
set_false_path -to [get_ports {LED[*]}]

derive_clock_uncertainty
