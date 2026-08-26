# Standalone NES clocks. The platform and NES IOPLLs share a board reference,
# but their output phases are unrelated and all communication crosses through
# explicit synchronizers or dual-clock RAM.
set standalone_board_clock \
    [get_clocks -nowarn -of_objects [get_ports CLOCK0_50]]
if {[get_collection_size $standalone_board_clock] == 0} {
    create_clock -name CLOCK0_50 -period 20.000 [get_ports CLOCK0_50]
}

foreach pll_root {mister_pll nes_core_pll_cal} {
    set pll_sdc_root [file normalize [file join [file dirname [info script]] .. ip ip $pll_root]]
    foreach pll_sdc [glob -nocomplain [file join $pll_sdc_root * altera_iopll_2100 synth *.sdc]] {
        source $pll_sdc
    }
}

set board_clocks [get_clocks -nowarn -of_objects [get_ports CLOCK0_50]]
set platform_clocks [get_clocks -nowarn {*|system_pll|*outclk*}]
set core_clocks [get_clocks -nowarn {
    *|pll|pll|iopll_0|iopll_0_outclk*
    *|pll|impl|iopll_0|iopll_0_outclk*
}]
set async_groups {}
foreach clock_group [list $board_clocks $platform_clocks $core_clocks] {
    if {[get_collection_size $clock_group] > 0} {
        lappend async_groups $clock_group
    }
}
if {[llength $async_groups] > 1} {
    set group_command [list set_clock_groups -asynchronous]
    foreach clock_group $async_groups {
        lappend group_command -group $clock_group
    }
    eval $group_command
}

# ADV7513 video output. The parallel bus changes on clk_video_out and the
# transmitter samples it on the forwarded inverted pixel clock.
set hdmi_clock_port [get_ports HDMI_TX_CLK]
set hdmi_master [get_clocks -nowarn -of_objects $hdmi_clock_port]
set hdmi_video_outputs [get_ports {
    HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS
}]
if {[get_collection_size $hdmi_master] == 1} {
    create_generated_clock -name DE25_HDMI_TX_CLK \
        -master_clock $hdmi_master \
        -source [get_clock_info -targets $hdmi_master] \
        -invert $hdmi_clock_port
    set_output_delay -clock [get_clocks DE25_HDMI_TX_CLK] \
        -reference_pin $hdmi_clock_port -max 1.800 $hdmi_video_outputs
    set_output_delay -clock [get_clocks DE25_HDMI_TX_CLK] \
        -reference_pin $hdmi_clock_port -min -1.300 $hdmi_video_outputs
}
set_false_path -to $hdmi_clock_port

# Audio crosses from the core into the independent fixed 24.576 MHz I2S
# serializer. Its samples are stable payload, not a same-cycle transfer.
set audio_samples [get_keepers -nowarn {*audio|samples*}]
if {[get_collection_size $audio_samples] > 0} {
    set_false_path -to $audio_samples
}
set_false_path -to [get_ports {HDMI_MCLK HDMI_SCLK}]

# Only the first stages of these explicit control synchronizers accept an
# asynchronous input. Dual-clock memory data is covered by clock grouping.
set cdc_meta [get_keepers -nowarn {
    *completed_toggle_sync[0]
    *completed_bank_sync[0]
    *diagnostic_sync0[*]
    *de25_want_pal_sync[0]
    *de25_loader_bridge|request_sync[0]
    *de25_loader_bridge|done_sync[0]
    *de25_loader_bridge|accepted_sync[0]
    *de25_loader_bridge|verify_error_sync[0]
    *de25_ram_quiesce|ram_request_sync[0]
}]
if {[get_collection_size $cdc_meta] > 0} {
    set_false_path -to $cdc_meta
}

# Reset assertion is asynchronous. Reset release is carried only through the
# three-stage pipes above, so recovery/removal on their clear pins is not a
# functional synchronous path.
set_false_path -to [get_pins -nowarn -hierarchical {
    *reset_pipe*clrn
}]

set_false_path -from [get_ports -nowarn {KEY[*] HDMI_TX_INT}]
set_false_path -to [get_ports -nowarn {LED[*] DRAM_*}]
set_false_path -from [get_ports {HDMI_I2C_SCL HDMI_I2C_SDA}]
set_false_path -to [get_ports {HDMI_I2C_SCL HDMI_I2C_SDA}]

derive_clock_uncertainty
