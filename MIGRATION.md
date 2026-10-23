# Migrating from 0.1 to 0.2

> 0.2.1 is a compatibility patch for LÖVR 0.19: the public API is unchanged,
> and the same code runs on 0.18 and 0.19. See [CHANGELOG.md](CHANGELOG.md).

Version 0.2 keeps the same constructor/update/draw API, but it changes two defaults and a handful of
option semantics. Most projects only need to make sure their simulation/rendering backend matches
what their code expects; the rest are small, documented behavior fixes.

## Quick compatibility

| Goal | Options |
| --- | --- |
| Closest to the old 0.1 behavior | `simulation = "cpu"`, `render_mode = "immediate"` |
| Keep Lua particle state, use the new instanced renderer | `simulation = "cpu"` (leave `render_mode` default) |
| Full performance (GPU simulation + instancing) | No options — `simulation = "auto"` picks the GPU when available |
| Keep `custom_update` | No options — `"auto"` selects the CPU backend automatically |
| Force CPU with a specific renderer | `simulation = "cpu"`, optionally `render_mode = "immediate"` |

`system.simulation` is set after construction, so it is easy to log or assert:

```lua
local system = particles.new({ ... })
print(system.simulation) -- "gpu" or "cpu"
```

## 1. Rendering default: instanced

`render_mode` now defaults to `"instanced"`. Instead of touching the `Pass` transform stack,
blend/color state, and calling `pass:box` for every particle, a system uploads one transform matrix
and color per particle and draws the whole system with a single instanced call.

What this means for existing code:

* `system:draw(pass)` no longer calls `pass:push`, `pass:translate`, `pass:rotate`,
  `pass:setColor`, `pass:box`, or `pass:pop`.
* The system sets a custom shader while drawing and **resets `pass:setShader(nil)` afterwards**.
  If you set your own shader before drawing particles and then draw other objects without setting it
  again, those objects will now use the default shader. Set your shader after the particle draws, or
  use `render_mode = "immediate"`.
* `blend_mode` and `depth_write` are optional per-system overrides. They are applied only when set;
  otherwise the current `Pass` state is used, as before.
* Instanced particles are blended in array order. Transparent particles may need
  `depth_write = false` plus additive blending, or an application-side sort.

If the graphics module or the required shader/buffers are unavailable, the system automatically falls
back to immediate rendering. `render_mode = "immediate"` forces the old one-draw-per-particle path.

There is no visual change for opaque, equal-sized particles; rotations, sizes, colors, and alpha are
encoded exactly as before.

## 2. Simulation default: auto (GPU when possible)

`simulation` now defaults to `"auto"`:

* `"gpu"` when the graphics module is available, `render_mode` is not `"immediate"`, and no
  `custom_update` hook was provided.
* `"cpu"` otherwise.

GPU simulation keeps particle state in buffers and derives position, color, size, and rotation in a
compute shader. The important user-visible consequences are:

* **`system.particles` is empty.** Any code that iterates particles, reads `p.position`, or inspects
  `particle_pool` must opt into `simulation = "cpu"`.
* **`custom_update` requires the CPU backend.** Passing it at construction makes `"auto"` select CPU.
  Setting it on a system that already selected GPU does nothing; create the system with
  `simulation = "cpu"` if you need the hook.
* **Capacity is fixed at construction** to `max_particles` (about 200 bytes per particle of GPU
  buffers). Changing `max_particles` later does not resize GPU buffers.
* **The backend is fixed at construction.** Changing `simulation` afterwards has no effect.
* **Motion is analytic.** With `drag = 0` it is exact ballistic motion; with `drag > 0` it uses the
  exact solution for linear drag. The CPU backend still uses per-frame Euler steps, so particle paths
  can differ slightly between backends.
* **Range/choice gravity is sampled once**, when the system is created, instead of every frame. If
  `gravity` is a `Vec3`, it is read each frame and in-place mutation is still reflected — but in GPU
  mode changing gravity or drag mid-flight recomputes the whole trajectory from birth, so treat them
  as constants for a particle's lifetime.
* `getParticleCount()`, `reset()`, `burst()`, `toggle()`, `setActive()`, and the burst schedules work
  the same in both backends. `reset()` also clears the GPU state buffer.

If any of those limitations is a problem, use `simulation = "cpu"`; the previous per-particle tables
and hooks are preserved exactly.

## 3. Option semantics that changed

### Two-element vector arrays are choices, not ranges

This is the one breaking change that can silently change emission values:

```lua
-- 0.1: interpolated between the two vectors
velocity = { Vec3(1, 0, 0), Vec3(5, 0, 0) }

-- 0.2: picks one of the two vectors
velocity = { Vec3(1, 0, 0), Vec3(5, 0, 0) }

-- 0.2: vector range (the explicit form)
velocity = { min = Vec3(1, 0, 0), max = Vec3(5, 0, 0) }
```

* Two-number arrays such as `{ 1.5, 2.5 }` are still ranges.
* Arrays of two vectors are now treated as choices.
* Arrays with more than two elements, or non-numeric elements, are choices (as before).
* Vector ranges must use `{ min = ..., max = ... }`.

### Random rates are sampled per particle

A scalar `rate` behaves exactly as before. A range or choice `rate` used to be re-rolled every frame,
which made the emission interval jitter; it is now sampled per emitted particle. Average flow is
preserved, and the emission cadence is more stable.

### Interval bursts catch up

Interval bursts were previously dropped when a frame took longer than the interval. They now catch up
in a `while` loop, so a hitch can release several bursts at once. Paused systems advance their burst
timers, so they do **not** queue a burst backlog. If you want to discard catch-up, call
`system:reset()`.

### Gravity vectors are used directly on the CPU

When `gravity` is a `Vec3`, the CPU backend now reads it each frame instead of copying it. In-place
mutation (`system.gravity.y = ...`) is reflected immediately. Range/choice gravity is still sampled
per frame on the CPU; GPU mode samples it once at construction.

### Start color/size are consistent

`p.color` and `p.size` are now initialized from the same sampled values as `p.color_start` and
`p.size_start`. Previously they were sampled independently, so a random start spec could begin at a
slightly different color/size than advertised. Constant colors/sizes are unaffected.

### `setActive` coerces to boolean

`system:setActive(nil)` now stores `false` rather than `nil`. Both were falsey, so this only matters
if you inspect `system.active` directly.

### `destroy` is safe and final

`system:destroy()` can be called more than once. After it, `update`, `draw`, `burst`, and `reset` are
no-ops, and `getParticleCount()` returns `0`. Previously calling `update` with a positive rate after
`destroy` could throw from a nil particle pool.

## 4. Migration checklist

1. Search the project for direct particle access:
   ```text
   system.particles
   particle_pool
   ```
   If you find any, set `simulation = "cpu"` for those systems.
2. Search for `custom_update`. It keeps working, but ensure it is passed at construction time.
3. Search option tables for two-element vector arrays (`{ Vec3(...), Vec3(...) }`) used as ranges and
   convert them to `{ min = ..., max = ... }`.
4. Search for code that sets a shader before calling `system:draw(pass)` and relies on it afterwards;
   set the shader after the draw or use `render_mode = "immediate"`.
5. Search for code that changes `max_particles`, `simulation`, or `custom_update` after creation.
   Those changes are not supported by the GPU backend; create the system with the final options.
6. If you need pixel-identical legacy motion, use `simulation = "cpu"`. For the old draw path, also
   use `render_mode = "immediate"`.
7. Run the project and compare. `pass:getStats().draws` should show one draw per instanced system
   instead of one per particle.

## 5. Compatibility recipes

### Old behavior, plus the bug fixes

```lua
local system = particles.new({
  simulation = "cpu",
  render_mode = "immediate",
  -- ...the rest of your options
})
```

### CPU simulation with the new instanced renderer

```lua
local system = particles.new({
  simulation = "cpu",
  -- render_mode defaults to "instanced"
  -- ...the rest of your options
})
```

### Full GPU mode

```lua
local system = particles.new({
  simulation = "gpu", -- optional; "auto" is the default
  -- do not provide custom_update
  -- do not access system.particles
})
```

### Per-particle hooks

```lua
local system = particles.new({
  custom_update = function(p, dt, progress)
    -- ...
  end,
})
-- system.simulation is "cpu"
```

## 6. Performance expectations

Measured on the development machine with LÖVR 0.18, 1000 particles, steady state:

| Path | CPU per frame |
| --- | --- |
| CPU simulation + instanced rendering | ~2.3 ms (update + draw recording) |
| GPU simulation + instanced rendering | ~0.003 ms (update + compute/draw recording) |

Burst emission remains a CPU cost in both backends because particle parameters are generated in Lua.
If you emit very large bursts, the GPU backend performs one buffer write per particle; batching that
is a future optimization.

## 7. Known differences and limitations

* GPU mode does not expose per-particle tables, and `custom_update` is CPU-only.
* GPU mode requires instanced rendering; `render_mode = "immediate"` forces CPU simulation.
* GPU mode samples range/choice gravity once at construction and treats gravity/drag as constants for
  a particle's lifetime when computing its path.
* GPU mode allocates `max_particles` worth of buffers up front (about 200 bytes per particle).
* GPU systems read `simulation`, `render_mode`, and `max_particles` at construction; changing them
  later does not reconfigure GPU resources. CPU systems can still switch `render_mode` at runtime.
* `space = "local"` applies the emitter's current position each frame in both backends; emitter
  rotation is not part of the local transform.
* Alpha blending still uses array order; there is no automatic back-to-front sort.
* The instanced path resets the active shader to `nil` after drawing.
