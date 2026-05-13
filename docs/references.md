# References

Primary source material used as architectural and behavioral references
for this project. None of the listed projects are copied verbatim; they
are read for documented behavior, register semantics, and validation.

## 3dfx SST-1 / Voodoo Graphics specification

- **Voodoo Graphics Hardware Specification, Revision 1.61** (3dfx)
  - <https://www.o3one.org/hwdocs/video/voodoo_graphics.pdf>
- **Bitsavers / Internet Archive mirror**
  - <https://archive.org/details/bitsavers_3dfxVoodoo2_1357630>

The SST-1 spec is the primary source for:

- Memory-mapped register addresses and reset values
- Command FIFO format and triangle setup register set
- fbzMode, fbzColorPath, alphaMode, fogMode, textureMode bit layouts
- Fixed-point precision for color, depth, S/T/W
- LFB read/write semantics and pixel format conversions
- Fast-fill and buffer-swap command behavior

## MAME Voodoo implementation

- <https://github.com/mamedev/mame/blob/master/src/devices/video/voodoo.cpp>
- <https://github.com/mamedev/mame/blob/master/src/devices/video/voodoo.h>
- <https://github.com/mamedev/mame/blob/master/src/devices/video/voodoo_regs.h>
- <https://github.com/mamedev/mame/blob/master/src/devices/video/voodoo_render.cpp>
- <https://github.com/mamedev/mame/blob/master/src/devices/video/voodoo_pci.cpp>

MAME is the most thoroughly tested public Voodoo emulator. It is used as a
reference for:

- Edge cases where the public spec is ambiguous
- Register-bit interpretation for combine/blend/depth modes
- Order of operations in the per-pixel pipeline
- LFB pixel format conversion details

MAME is GPL-licensed. **No code is copied from MAME into this project.**
Only behavioral and architectural information is referenced.

## PCem

- <https://github.com/sarah-walker-pcem/pcem>

PCem is referenced for an alternative, independently developed view of
Voodoo behavior. Useful as a cross-check when MAME and the spec disagree
or when a behavior is implied but not explicit.

## FPGA reference project

- <https://github.com/victor-fisyuk/voodoo-fpga-public>

Prior FPGA-oriented work on the Voodoo architecture. Referenced for
hardware-implementation perspective: partitioning of work between blocks,
memory-interface choices, and known practical pitfalls. Code is not copied;
the project is used for design intuition only.

## Internal documentation

Project-internal documents derived from the above:

- `docs/architecture.md` — top-level block diagram and pipeline overview
- `docs/registers.md` — implemented register map and bit-field notes
- `docs/fixed_point.md` — fixed-point formats used in interpolation,
  texture coordinates, and depth

## Attribution policy

When a specific behavior is taken from one of these sources, the relevant
RTL or document comment includes a citation, e.g.:

```
// Reference: SST-1 spec Rev 1.61, section 5.x (fbzMode bits)
// Reference: MAME voodoo.cpp -- behavior of pixel pipeline order
```

The goal is to make it straightforward for a future reader to audit which
external behavior is being modeled.
