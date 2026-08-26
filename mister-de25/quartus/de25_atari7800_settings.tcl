# Quartus settings files accept assignment commands directly, while ordinary
# Tcl variables must be set from a sourced script. The shared persona base
# reads this variable to leave the native SDRAM interface enabled.
set DE25_SIMPLE_PERSONA_NATIVE_SDRAM 1
