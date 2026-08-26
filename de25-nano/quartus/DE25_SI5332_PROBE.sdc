create_clock -name CLOCK0_50 -period 20.000 [get_ports CLOCK0_50]

# The two management wires are asynchronous open-drain signals.  Their slow
# protocol timing is enforced structurally by the 50 MHz state machine.
set_false_path -from [get_ports {SI5332_SCL SI5332_SDA}]
set_false_path -to [get_ports {SI5332_SCL SI5332_SDA}]

derive_clock_uncertainty
