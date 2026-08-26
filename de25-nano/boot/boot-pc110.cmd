echo "Trying to boot PC110 Linux support from device ${target}";

if test "${target}" = "mmc0"; then
        bridge enable;
        echo "Found kernel on mmc0";
        mmc rescan;

        if fatload mmc 0:1 ${kernel_addr_r} Image &&
           fatload mmc 0:1 0xb00c0000 pc110_bios.bin &&
           fatload mmc 0:1 0xb2000000 pc110_font.bin &&
           fatload mmc 0:1 ${fdt_addr_r} socfpga_agilex5_de25_nano.dtb; then
                echo "PC110 BIOS and font loaded into reserved LPDDR";
                setenv bootargs "console=ttyS0,115200 root=${mmcroot} rw rootwait";
                setenv fdt_high 0xafffffff;
                booti ${kernel_addr_r} - ${fdt_addr_r};
        else
                echo "PC110 boot files are missing or unreadable";
        fi;
        exit;
fi;
