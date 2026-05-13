# Architecture

Top-level architectural notes for the SST-1 reimplementation.

This document is filled in during **Phase 1**. It will cover:

- Block diagram: host bus, register file, command FIFO, triangle setup,
  rasterizer, color combine, texture unit, frame buffer, video scanout.
- Clock and reset strategy.
- Memory partitioning (frame buffer, depth buffer, texture memory).
- Which behaviors are modeled accurately first and which are initially
  approximated.

Until Phase 1 lands, see `docs/references.md` for the authoritative
external sources.
