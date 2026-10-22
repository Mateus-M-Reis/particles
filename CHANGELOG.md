# Changelog

All notable changes to this project are documented here.

## [0.2.0] - 2026-10-22

### Added

* **Instanced rendering** (`render_mode = "instanced"`, now the default): a system is drawn with one
  instanced call using per-particle transform and color buffers instead of one `pass:box` per
  particle. The old per-particle draw path remains available as `render_mode = "immediate"`.
* **GPU simulation** (`simulation = "auto"`, now the default): particle state lives in buffers and a
  compute shader derives motion, rotation, color, and size analytically. `simulation = "cpu"` keeps
  the per-particle Lua tables and `custom_update` hook.
* Per-system `blend_mode` and `depth_write` overrides, applied only when set.
* `system.simulation` reports the selected backend (`"gpu"` or `"cpu"`).
* `MIGRATION.md` with a compatibility guide for projects upgrading from 0.1.

### Changed

* **Breaking:** a two-element array of vectors is now a list of choices; vector ranges must use
  `{ min = ..., max = ... }`. Two-number arrays are still ranges.
* Random/range `rate` values are sampled per emitted particle instead of once per frame.
* Interval bursts catch up after long frames instead of being dropped. Paused systems do not queue
  interval bursts.
* Gradient math now uses `Vec3:lerp`/`Vec4:lerp`, and `p.color`/`p.size` start from the same sample
  as `p.color_start`/`p.size_start`.
* When `gravity` is a `Vec3`, the CPU backend uses it directly, so in-place mutation is reflected.
* `system:setActive(nil)` stores `false`.
* The demo project version is now `0.2.0`.

### Fixed

* `destroy()` is idempotent; `update`, `draw`, `burst`, and `reset` no longer crash after it.
* Interval bursts are no longer lost when a frame is longer than the burst interval.
* Random-rate emitters no longer change their interval every frame.
* `p.color`/`p.size` no longer start from an independently sampled value.

### Performance

* 1000 particles, steady state, measured with LÖVR 0.18 on the development machine:
  * update + draw recording: ~2.7 ms + ~3.6 ms (0.1) → ~2.3 ms (0.2 CPU) → ~0.003 ms (0.2 GPU).
  * draw calls: one per particle → one per system.
* Emission is still CPU-driven; 1000-particle bursts cost ~4–9 ms depending on the backend.
