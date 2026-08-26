set pcxt_root [file normalize [file join [file dirname [info script]] .. upstream cores PCXT]]

# Quartus Pro 25 is stricter than the Quartus 17 flow used by the upstream
# project. Compile legacy unpacked arrays and ANSI ports as SystemVerilog.
foreach source_file {
    rtl/common/ram.v
    rtl/common/bios.v
    rtl/common/floppy.v
    rtl/common/simple_fifo.v
    rtl/common/simple_ram.v
    rtl/common/MSMouseWrapper.v
    rtl/common/ide.v
    rtl/common/tandy_pcjr_joy.sv
    rtl/common/jtframe_credits.v
    rtl/common/jtframe_ram.v
    rtl/common/jtframe_dual_ram.v
} {
    set_global_assignment -name SYSTEMVERILOG_FILE [file join $pcxt_root $source_file]
}
set_global_assignment -name VHDL_FILE [file join $pcxt_root rtl common bram.vhd]

# Peripherals.sv keeps the HGC instances in the elaborated hierarchy even
# when ENABLE_HGC is zero, so Quartus still needs their entity definitions.
foreach source_file {
    rtl/video/vram.v
    rtl/video/UM6845R.v
    rtl/video/cga_vram.v
    rtl/video/cga_vgaport.v
    rtl/video/cga_sequencer.v
    rtl/video/video_scandoubler.v
    rtl/video/cga_pixel.sv
    rtl/video/cga_composite.v
    rtl/video/cga_attrib.v
    rtl/video/cga.v
    rtl/video/hgc_vgaport.v
    rtl/video/hgc_pixel.v
    rtl/video/hgc_sequencer.v
    rtl/video/hgc_attrib.v
    rtl/video/hgc.v
    rtl/video/splash_rom.v
    rtl/video/video_monochrome_converter.sv
} {
    set_global_assignment -name SYSTEMVERILOG_FILE [file join $pcxt_root $source_file]
}
set_global_assignment -name QIP_FILE [file join $pcxt_root rtl uart uart.qip]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $pcxt_root rtl sound saa1099.sv]
set_global_assignment -name QIP_FILE [file join $pcxt_root rtl sound jt89 hdl jt89.qip]
set_global_assignment -name QIP_FILE [file join $pcxt_root rtl sound jtopl hdl jtopl2.qip]
set_global_assignment -name QIP_FILE [file join $pcxt_root rtl 8088 8088.qip]
foreach source_file {
    rtl/KFPC-XT/HDL/KFSDRAM/HDL/KFSDRAM.sv
    rtl/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB_Shift_Register.sv
    rtl/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB_Send_Data.sv
    rtl/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB.sv
    rtl/KFPC-XT/HDL/KFPS2KB/HDL/Tandy_Scancode_Converter.sv
    rtl/KFPC-XT/HDL/KF8288/HDL/KF8288.sv
    rtl/KFPC-XT/HDL/KF8259/HDL/KF8259_Priority_Resolver.sv
    rtl/KFPC-XT/HDL/KF8259/HDL/KF8259_Interrupt_Request.sv
    rtl/KFPC-XT/HDL/KF8259/HDL/KF8259_In_Service.sv
    rtl/KFPC-XT/HDL/KF8259/HDL/KF8259_Control_Logic.sv
    rtl/KFPC-XT/HDL/KF8259/HDL/KF8259_Bus_Control_Logic.sv
    rtl/KFPC-XT/HDL/KF8259/HDL/KF8259.sv
    rtl/KFPC-XT/HDL/KF8255/HDL/KF8255_Port_C.sv
    rtl/KFPC-XT/HDL/KF8255/HDL/KF8255_Port.sv
    rtl/KFPC-XT/HDL/KF8255/HDL/KF8255_Group.sv
    rtl/KFPC-XT/HDL/KF8255/HDL/KF8255_Control_Logic.sv
    rtl/KFPC-XT/HDL/KF8255/HDL/KF8255.sv
    rtl/KFPC-XT/HDL/KF8253/HDL/KF8253_Counter.sv
    rtl/KFPC-XT/HDL/KF8253/HDL/KF8253_Control_Logic.sv
    rtl/KFPC-XT/HDL/KF8253/HDL/KF8253.sv
    rtl/KFPC-XT/HDL/KF8237/HDL/KF8237_Timing_And_Control.sv
    rtl/KFPC-XT/HDL/KF8237/HDL/KF8237_Priority_Encoder.sv
    rtl/KFPC-XT/HDL/KF8237/HDL/KF8237_Bus_Control_Logic.sv
    rtl/KFPC-XT/HDL/KF8237/HDL/KF8237_Address_And_Count_Registers.sv
    rtl/KFPC-XT/HDL/KF8237/HDL/KF8237.sv
    rtl/KFPC-XT/HDL/XT_CE_Generator.sv
    rtl/KFPC-XT/HDL/Ready.sv
    rtl/KFPC-XT/HDL/RAM.sv
    rtl/KFPC-XT/HDL/XT2IDE.sv
    rtl/KFPC-XT/HDL/KFMMC/HDL/LDST_SEQUENCER.v
    rtl/KFPC-XT/HDL/KFMMC/HDL/KFMMC_SPI.sv
    rtl/KFPC-XT/HDL/KFMMC/HDL/KFMMC_SPI2IDE_ROM.v
    rtl/KFPC-XT/HDL/KFMMC/HDL/KFMMC_DRIVE_SPI2IDE.sv
    rtl/KFPC-XT/HDL/Peripherals.sv
    rtl/KFPC-XT/HDL/Chipset.sv
    rtl/KFPC-XT/HDL/Bus_Arbiter.sv
    rtl/hps_ext.v
} {
    set_global_assignment -name SYSTEMVERILOG_FILE [file join $pcxt_root $source_file]
}
set_global_assignment -name VERILOG_FILE [file join $pcxt_root rtl KFPC-XT HDL rtc.v]
