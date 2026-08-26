# Reset a stalled HPS through the JTAG-to-HPS master already present in the
# DE25-Nano GHRD. Identify the master by the Synopsys DesignWare watchdog
# component signature before writing anything.
set watchdog_base 0x10d00200
set watchdog_torr [expr {$watchdog_base + 0x04}]
set watchdog_cr [expr {$watchdog_base + 0x00}]
set watchdog_comp_type [expr {$watchdog_base + 0xfc}]
set expected_comp_type 0x44570120

# A non-interactive System Console starts before the USB/JTAG connection list
# is populated.  Refresh explicitly so the guarded probe sees the same live
# masters as list-live-services.tcl.
refresh_connections

# USB-Blaster enumeration is asynchronous.  A refresh can briefly return an
# empty master list even though the same System Console instance discovers the
# fabric services a moment later.  Wait for that bounded cold-plug window so a
# remote recovery request cannot fail spuriously.
set masters {}
for {set attempt 0} {$attempt < 50} {incr attempt} {
    set masters [get_service_paths master]
    if {[llength $masters] > 0} {
        break
    }
    after 100
    refresh_connections
}
set master_count [llength $masters]
if {$master_count == 0} {
    error "No JTAG Avalon master was discovered"
}

set master ""
for {set index [expr {$master_count - 1}]} {$index >= 0} {incr index -1} {
    set candidate [lindex $masters $index]
    if {[catch {open_service master $candidate} open_error]} {
        puts stderr "Skipping JTAG master $index: $open_error"
        continue
    }

    if {[catch {set observed [master_read_32 $candidate $watchdog_comp_type 1]} read_error]} {
        puts stderr "Skipping JTAG master $index: $read_error"
        catch {close_service master $candidate}
        continue
    }

    if {[expr {$observed == $expected_comp_type}]} {
        set master $candidate
        puts "Using HPS watchdog JTAG master $index: $master"
        break
    }

    puts "Skipping JTAG master $index: component type $observed"
    catch {close_service master $candidate}
}

if {$master eq ""} {
    error "No JTAG master exposes the HPS watchdog component"
}

set old_cr [master_read_32 $master $watchdog_cr 1]
set old_torr [master_read_32 $master $watchdog_torr 1]
puts "Watchdog before reset: CR=$old_cr TORR=$old_torr"

# Select the minimum watchdog timeout range, then enable reset response mode.
master_write_32 $master $watchdog_torr 0x00000000
master_write_32 $master $watchdog_cr 0x00000001
puts "HPS watchdog armed; cold reset should follow"
flush stdout
catch {close_service master $master}
exit
