# particles

A powerful, high-performance, and feature-packed 3D particle system module for the [LÖVR](https://lovr.org) VR engine. Inspired by the flexibility of Defold's [AcidRain](https://github.com/approboGames/AcidRain/tree/master) library, this module is built from the ground up to take advantage of LÖVR's native 3D vectors while remaining strictly safe from vector-allocation pool recycling errors.

**Version 0.2.1.** Runs on LÖVR 0.18 and 0.19. Upgrading an existing project? Read [MIGRATION.md](MIGRATION.md) for the behavior changes and compatibility recipes; release notes are in [CHANGELOG.md](CHANGELOG.md).

---

## Features

* **3D Emitter Shapes:** Emit particles from a `point`, `box`, `sphere`, or `disc` (with optional boundary/edge-only spawning).
* **Local vs. World Space:** Decide whether particles move independently in the world or stay anchored to a moving emitter.
* **Property Gradients:** Smoothly interpolate color/alpha and size dimensions from `start` to `end` states over a particle's lifetime.
* **Kinematics:** Built-in support for gravity, air resistance (`drag`), and random range tables (`{min, max}`).
* **Angular Mechanics:** Support for spinning particles with randomized rotation speeds and axes.
* **Flexible Burst Timers:** Schedule timed one-off explosions or repeating interval bursts.
* **Custom Code Injections:** Hook your own math equations (e.g., sine wave paths) directly into individual particle runtimes.
* **Instanced Rendering:** Draws every particle in a system with a single instanced call (per-particle transforms and colors live in buffers), with an automatic immediate-mode fallback.
* **GPU Simulation:** Keeps particle state in buffers and integrates motion, rotation, color, and size in a compute shader, leaving only emission and scheduling on the CPU.

---

## Installation

Drop the `particles` directory into your LÖVR project directory:

```text
my-lovr-game/
├── particles/
│   ├── init.lua
│   └── (other repository files)
├── main.lua

```

Require it in your project using:

```lua
local particles = require 'particles'

```

---

## Upgrading from 0.1

Version 0.2 changes the two defaults that matter most: systems render with instancing, and they
simulate on the GPU when possible. Both have low-risk escape hatches:

| Goal | Options |
| --- | --- |
| Closest to 0.1 behavior | `simulation = "cpu"`, `render_mode = "immediate"` |
| Lua particle state + new instanced renderer | `simulation = "cpu"` |
| GPU simulation + instancing | no options (default `"auto"`) |
| Keep `custom_update` | no options (`"auto"` selects CPU) |

See [MIGRATION.md](MIGRATION.md) for the full checklist, including the two-element vector array
change, burst catch-up semantics, and the new `system.particles` limitation in GPU mode.

---

## Quick Start

```lua
local particles = require 'particles'
local fireSystem

function lovr.load()
  fireSystem = particles.new({
    position = Vec3(0, 1, -3),
    rate = 30,
    velocity = Vec3(0, 1, 0),
    spread = Vec3(0.2, 0, 0.2),
    color_start = Vec4(1, 0.5, 0, 1),
    color_end = Vec4(0.2, 0, 0, 0),
    size_start = 0.1,
    size_end = 0.01
  })
end

function lovr.update(dt)
  fireSystem:update(dt)
end

function lovr.draw(pass)
  fireSystem:draw(pass)
end

```

Then you can run it.

```bash
lovr ./

```

---

## Configuration Options

When creating a new system with `particles.new(options)`, you can pass a table containing any of the parameters below. Many parameters accept a single value, a range (`{min, max}` or `{min = x, max = y}`), or an array of values picked randomly. A two-number array such as `{1.5, 2.5}` is treated as a range; an array of vectors such as `{Vec3(0, 1, 0), Vec3(-1, 0, 0)}` is treated as a list of choices, so use the `{min = ..., max = ...}` form when you want to interpolate between two vectors.

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `position` | `Vec3` | `Vec3(0,0,0)` | The world position origin of the emitter system. |
| `space` | `string` | `"world"` | `"world"` (particles move freely) or `"local"` (particles move with emitter). |
| `max_particles` | `number` | `1000` | Hard cap tracking safety threshold to prevent runaway memory arrays. |
| `rate` | `number | table` | `10` | Continuous flow particles per second. Range/choice values are sampled per emitted particle. |
| `shape` | `string` | `"point"` | Emission boundary: `"point"`, `"box"`, `"sphere"`, or `"disc"`. |
| `shape_size` | `Vec3 | number` | `Vec3(0.1,0.1,0.1)` | Scale of the bounding emitter shape. `box` uses a `Vec3`; `sphere`/`disc` use a single radius (passing a `Vec3` scales each axis, producing an ellipsoid). |
| `shape_edge` | `boolean` | `false` | If true, particles only spawn on the outer shell/rim of the shape. |
| `lifetime` | `number | table` | `5` | How long particles live in seconds. Supports ranges. |
| `velocity` | `Vec3 | table` | `Vec3(0,1,0)` | Base velocity direction vector. Supports ranges/choices. |
| `spread` | `Vec3 | table` | `Vec3(1,1,1)` | Maximum random directional deviation variation. |
| `gravity` | `Vec3 | table` | `Vec3(0,-0.5,0)` | Continuous acceleration vector. GPU mode treats it as constant for a particle's lifetime; CPU mode applies it per frame. |
| `drag` | `number` | `0` | Air resistance coefficient. GPU mode uses the exact exponential solution; CPU mode applies it per frame. |
| `color_start` | `Vec4 | table` | `Vec4(1,1,1,1)` | Initial particle RGBA color. |
| `color_end` | `Vec4 | table` | `nil` | Target color gradient at end of lifetime. Overrides `fade`. |
| `size_start` | `Vec3 | number` | `Vec3(0.1,0.1,0.1)` | Starting particle box dimensions. |
| `size_end` | `Vec3 | number` | `nil` | Target size dimensions at end of lifetime. |
| `fade` | `boolean` | `true` | If `color_end` is nil, automatically fades alpha down to `0`. |
| `rotation_speed` | `number | table` | `0` | Rotational speed in radians per second. |
| `bursts` | `table` | `nil` | Table array containing timed/interval burst blueprints. |
| `custom_update` | `function` | `nil` | Evaluation callback injection hook: `function(p, dt, progress)`. |
| `render_mode` | `string` | `"instanced"` | `"instanced"` draws the whole system in one call; `"immediate"` draws one box per particle. |
| `simulation` | `string` | `"auto"` | `"auto"`, `"gpu"`, or `"cpu"`. GPU simulation requires instanced rendering and falls back to CPU for `custom_update` or `render_mode = "immediate"`. |
| `blend_mode` | `string | table` | `nil` | Applied with `pass:setBlendMode` before drawing, only when set. |
| `depth_write` | `boolean` | `nil` | Applied with `pass:setDepthWrite` before drawing, only when set. |

By default each system renders with a single instanced draw call: a shared unit-cube mesh plus per-particle transform and color buffers, with no per-particle `Pass` state changes. If the graphics module is unavailable or the shader/resources cannot be created, the system falls back to drawing one box per particle (set `render_mode = "immediate"` to force that path).

Instanced drawing changes the active shader and resets it to `nil` when it finishes. `blend_mode` and `depth_write` are left untouched unless set; for transparent particles, consider `depth_write = false` and either additive blending or back-to-front ordering, since instanced particles are drawn in array order.

### Simulation Backends

`simulation = "auto"` uses the GPU backend whenever the graphics module and instanced rendering are available. Particle state then lives in a buffer and a compute shader derives position, rotation, color, and size analytically from each particle's birth time. Per-frame CPU work is limited to emission, slot bookkeeping, and a compute dispatch; `system:update()` becomes nearly free, and `system:draw()` does not rebuild transforms on the CPU.

GPU simulation has a few intentional tradeoffs:

* GPU simulation does not populate `system.particles`, and `custom_update` requires the CPU backend. Passing `custom_update` at creation (or `simulation = "cpu"`) keeps the original per-particle tables and hooks; `"auto"` selects CPU automatically in that case.
* Motion is integrated analytically: exact ballistic motion, and the exact solution for linear drag (the CPU path uses per-frame Euler steps, so the curves can differ slightly).
* Gravity is a single system-wide vector sampled once at creation when given as a range/choice table.
* Capacity is fixed to `max_particles` at creation, and the chosen backend does not change afterwards.
* `getParticleCount()`, `reset()`, `burst()`, `toggle()`, and the burst schedules keep working as usual.

---

## Advanced Usage

### Burst Profiles

You can orchestrate complex bursts alongside or instead of a constant `rate`. Bursts can happen at an absolute timestamp or loop indefinitely at an interval timer:

```lua
local explosion = particles.new({
  position = Vec3(0, 1.5, -2),
  rate = 0, -- Turn off continuous spawning
  bursts = {
    { time = 0.0, count = 100 },     -- Blast 100 particles instantly on start
    { interval = 2.5, count = 15 }   -- Blast 15 more particles every 2.5 seconds
  }
})

```

### Custom Runtime Hooks

Take complete creative control over individual particle trajectories by manipulating internal particle attributes inside the `custom_update` parameter. The modifier receives the particle object `p`, the delta-time `dt`, and the normalized lifetime progression `progress` (a float ranging from `0.0` at birth to `1.0` at death):

```lua
local helixSystem = particles.new({
  position = Vec3(0, 0, -4),
  velocity = Vec3(0, 0.5, 0),
  custom_update = function(p, dt, progress)
    -- Add a sinusoidal wave motion over the particle's age
    p.position.x = p.position.x + math.sin(p.age * 8) * 0.01
    p.position.z = p.position.z + math.cos(p.age * 8) * 0.01
  end
})

```

---

## API Methods

#### `system:update(dt)`

Advances the simulation matrix logic. Put this inside `lovr.update(dt)`.

#### `system:draw(pass)`

Renders the active particles inside the active graphics pipeline. Put this inside `lovr.draw(pass)`. In instanced/GPU mode the system sets its own shader and resets it to `nil` when done; see [Upgrading from 0.1](#upgrading-from-01) if you rely on your own shader staying active.

#### `system:burst(count)`

Forcefully causes the emitter to spit out an explicit number of particles instantly.

#### `system:toggle()`

Toggles whether the system is active or paused. Paused systems stop emitting but will continue to process/draw existing particles until they expire.

#### `system:reset()`

Flushes all active particles out of the lookup array and rewinds system-wide elapsed timers back to zero. Useful for re-triggering one-shot explosion schedules.

#### `system:getParticleCount()`

Returns the current number of active particles in the system. This works with both simulation backends.

#### `system:isActive()`

Returns `true` if the system is currently active (emitting particles), `false` if paused.

#### `system:setActive(active)`

Sets the active state of the system. Pass `true` to enable emission, `false` to pause.

#### `system:getElapsedTime()`

Returns the total elapsed time since the system was created or last reset, in seconds.

#### `system:destroy()`

Cleans up the system by resetting all particles and clearing the particle pool. Call this when you're done with a system to free memory. After destroying, `update`, `draw`, `burst`, and `reset` become no-ops.
