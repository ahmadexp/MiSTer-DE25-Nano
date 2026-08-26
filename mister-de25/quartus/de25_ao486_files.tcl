set ao486_root [file normalize [file join [file dirname [info script]] .. upstream cores AO486]]

foreach source_file {
    sys/math.sv
    sys/video_cleaner.sv
    sys/gamma_corr.sv
    sys/video_freak.sv
    sys/mt32pi.sv
    sys/hps_io.sv
} {
    set_global_assignment -name SYSTEMVERILOG_FILE [file join $ao486_root $source_file]
}

foreach qip_file {
    rtl/ao486/ao486.qip
    rtl/cache/cache.qip
    rtl/soc/uart/uart.qip
    rtl/soc/gus/gus.qip
    rtl/soc/sound/opl3/opl3.qip
} {
    set_global_assignment -name QIP_FILE [file join $ao486_root $qip_file]
}

foreach source_file {
    rtl/soc/sound/sound.v
    rtl/soc/sound/sound_dsp.v
    rtl/soc/sound/saa1099.sv
    rtl/common/cdc_vector_handshake_continuous.sv
    rtl/common/synchronizer.sv
} {
    set_global_assignment -name SYSTEMVERILOG_FILE [file join $ao486_root $source_file]
}

foreach source_file {
    rtl/common/simple_fifo.v
    rtl/common/simple_fifo_mlab.v
    rtl/common/simple_mult.v
    rtl/common/simple_ram.v
    rtl/common/simple_rom.v
    rtl/common/simple_single_rom.v
} {
    set_global_assignment -name VERILOG_FILE [file join $ao486_root $source_file]
}

set_global_assignment -name VHDL_FILE ../rtl/de25_ao486_spram.vhd
set_global_assignment -name VHDL_FILE ../../de25-nano/rtl/de25_bram.vhd

foreach source_file {
    rtl/soc/iobus.v
    rtl/soc/ide.v
    rtl/soc/joystick.v
    rtl/soc/pic.v
    rtl/soc/pit.v
    rtl/soc/pit_counter.v
    rtl/soc/ps2.v
    rtl/soc/rtc.v
    rtl/soc/vga.v
    rtl/system.v
    rtl/hps_ext.v
} {
    set_global_assignment -name VERILOG_FILE [file join $ao486_root $source_file]
}

foreach source_file {
    rtl/soc/floppy.v
    rtl/soc/cdda.v
    rtl/soc/dma.v
} {
    set_global_assignment -name SYSTEMVERILOG_FILE [file join $ao486_root $source_file]
}
