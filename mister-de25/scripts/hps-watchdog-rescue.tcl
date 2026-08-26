# Rescue an HPS caught in a short DesignWare watchdog reset loop.
#
# The JTAG transaction is queued while the FPGA-to-HPS bridge is in reset. If
# the bridge opens during a boot attempt, the single contiguous burst changes
# both timeout fields to their maximum value and reloads the counter before the
# next short timeout can expire.
set watchdog_base 0x10d00200
set masters [get_service_paths master]
set master_count [llength $masters]

if {$master_count == 0} {
    error "No JTAG Avalon master was discovered"
}

# The GHRD exposes the coherent JTAG-to-HPS master last. A component-signature
# read is intentionally not used here because reads block during the reset loop.
set index [expr {$master_count - 1}]
set master [lindex $masters $index]
open_service master $master
puts "Queueing watchdog rescue burst on JTAG master $index: $master"
flush stdout

# CR=reset mode + enabled, TORR={TOPINIT=15,TOP=15}, CCVR is read-only,
# CRR=0x76 reloads the counter. Keeping this as one burst minimizes latency.
master_write_32 $master $watchdog_base {0x00000001 0x000000ff 0x00000000 0x00000076}
puts "Watchdog rescue burst completed"
flush stdout
catch {close_service master $master}
exit
