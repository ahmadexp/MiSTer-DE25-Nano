echo "Trying to boot the DE25-Nano MiSTer platform from ${target}";

if test "${target}" = "mmc0"; then
        echo "Found kernel on mmc0";
        mmc rescan;

        if fatload mmc 0:1 ${kernel_addr_r} Image &&
           fatload mmc 0:1 ${fdt_addr_r} socfpga_agilex5_de25_nano.dtb; then
                setenv bootargs "console=ttyS0,115200 root=${mmcroot} rw rootwait mem=512M";
                setenv fdt_high 0x9fffefff;
                booti ${kernel_addr_r} - ${fdt_addr_r};
        else
                echo "DE25-Nano MiSTer boot files are missing or unreadable";
        fi;
        exit;
fi;
