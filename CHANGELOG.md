# Changelog

All notable changes to this project are documented here.

## [0.2.2] - 2026-10-23

### Added

* `particles.vec4(r, g, b, a)` creates a 4-component color on both LÖVR 0.18
  and 0.19, where the legacy global `Vec4` is aliased to the 3D vector type and
  silently drops the alpha component.

### Fixed

* Color alpha, GPU row data, and gradient `w` values are preserved on LÖVR
  0.19. The global `Vec4` there is a 3D vector, so internal color/row vectors
  now add `w` explicitly after construction.
* The GPU emitter row fields (`position`, `velocity`, `sizeStart`, `sizeEnd`,
  `axis`) keep their fourth component instead of losing lifetime, speed, and
  flags to the same alias.

## [0.2.1] - 2026-10-23

### Changed

* LÖVR 0.19 compatibility. The library no longer calls `Vec3:set`, `Vec3:add`,
  `Vec3:mul`, or the other removed vector methods. Motion, gradients, and the
  GPU emitter offset are applied through explicit component writes instead.
* Vector copies are explicit. LÖVR 0.19 changed `Vec3(existing)` /
  `Vec4(existing)` to return the input table (the deprecated copy behavior was
  removed), so `system.position`, particle colors/sizes, and range/choice
  samples are now copied by component. This keeps emitters from aliasing each
  other and stops gradients from mutating `p.color_start` / `p.size_start`.
* `is_vector` recognizes the table-based vectors used by 0.19 as well as the
  userdata vectors used by 0.18, so per-frame `gravity` mutation and GPU
  gravity sampling work on both.

### Fixed

* Color and size gradients now actually interpolate on LÖVR 0.19. Its
  `Vec3:lerp` / `Vec4:lerp` returns a new vector instead of mutating the
  receiver, so the previous `:set(...):lerp(...)` chain discarded the result.

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
