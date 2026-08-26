set masters [get_service_paths master]
puts stderr "MASTER_COUNT=[llength $masters]"
foreach master $masters {
    puts stderr "MASTER=$master"
}
set processors [get_service_paths processor]
puts stderr "PROCESSOR_COUNT=[llength $processors]"
foreach processor $processors {
    puts stderr "PROCESSOR=$processor"
}
exit
