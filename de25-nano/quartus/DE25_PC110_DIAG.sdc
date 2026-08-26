create_clock -name CLOCK0_50 -period 20.000 [get_ports CLOCK0_50]
create_clock -name CLOCK1_50 -period 20.000 [get_ports CLOCK1_50]
create_clock -name CLOCK2_50 -period 20.000 [get_ports CLOCK2_50]

set_clock_groups -asynchronous \
    -group [get_clocks CLOCK0_50] \
    -group [get_clocks CLOCK1_50] \
    -group [get_clocks CLOCK2_50]

derive_clock_uncertainty

