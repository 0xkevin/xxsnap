# Snipory v2 Architecture

- `core/`: shared C++ library
- `platforms/mac/`: Swift/AppKit application shell
- `platforms/win/`: Windows native shell scaffold

During the migration phase, `core/` still uses Qt value types for shared image and geometry models.
The native platform shells remain the long-term UI boundary.
