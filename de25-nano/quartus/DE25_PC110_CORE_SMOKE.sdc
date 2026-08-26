create_clock -name CLOCK0_50 -period 20.000 [get_ports CLOCK0_50]

set_false_path -from [get_ports KEY[*]]
set_false_path -from [get_ports FPGA_UART_RX]
set_false_path -to [get_ports {LED[*]}]
set_false_path -to [get_ports FPGA_UART_TX]

derive_clock_uncertainty
