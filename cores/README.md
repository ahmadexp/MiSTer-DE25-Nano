# Local core sources

The common DE25-Nano platform lives in `mister-de25/`. This directory contains
only supplemental core sources that are maintained with the platform and are
not fetched from the locked official MiSTer catalog.

Each core is isolated in its own directory. Core-specific RTL must not become
an implicit dependency of unrelated platform builds.

- [`PC110`](PC110/): IBM Palm Top PC 110 core and retained Cyclone V project.
