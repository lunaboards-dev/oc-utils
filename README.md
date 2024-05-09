OC-Utils
========================
Various utilities for OpenComputers

# fdisk
`fdisk` should support drives, tape, and EEPROM cards and supports OSDI and MTPT partition tables.
It's unfinished, with a few commands unimplemented, but most of the functionality should be there.

# cpio
Supports only binary cpio archives (`-Hbin`). Can pipe output to another program like a compressor or something. Pipe list of files in when creating (`cpio -o`). Use `--F=...` for specifying an output path.