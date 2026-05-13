# Fixed-point formats

Fixed-point conventions used in the SST-1 pipeline (color interpolation,
depth, texture coordinates, perspective division).

This document is filled in during **Phase 5**. It will cover:

- Notation: `Qm.n` (signed) and `UQm.n` (unsigned).
- Color channel precision and saturation rules.
- Depth (Z) precision and compare semantics.
- S, T, W formats and the reciprocal/approximation strategy for
  perspective correction.
- Rounding, truncation, and clamping rules per stage.

The conventions defined here are consumed by `rtl/common/sst1_fixed_pkg.sv`
and by every pipeline module that performs interpolation.
