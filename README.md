# particles

A powerful, high-performance, and feature-packed 3D particle system module for the [LÖVR](https://lovr.org) VR engine. Inspired by the flexibility of Defold's *AcidRain* library, this module is built from the ground up to take advantage of LÖVR's native 3D vectors while remaining strictly safe from vector-allocation pool recycling errors.

---

## Features

* **3D Emitter Shapes:** Emit particles from a `point`, `box`, `sphere`, or `disc` (with optional boundary/edge-only spawning).
* **Local vs. World Space:** Decide whether particles move independently in the world or stay anchored to a moving emitter.
* **Property Gradients:** Smoothly interpolate color/alpha and size dimensions from `start` to `end` states over a particle's lifetime.
* **Kinematics:** Built-in support for gravity, air resistance (`drag`), and random range tables (`{min, max}`).
* **Angular Mechanics:** Support for spinning particles with randomized rotation speeds and axes.
* **Flexible Burst Timers:** Schedule timed one-off explosions or repeating interval bursts.
* **Custom Code Injections:** Hook your own math equations (e.g., sine wave paths) directly into individual particle runtimes.

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

The remaining files in this repository (`main.lua`, `lodr`, and `assets`) comprise a live preview workspace.

To execute the demo with hot-reloading active, run the following command from the root of the repository:

```bash
lovr lodr ./
```

---

## Configuration Options

When creating a new system with `particles.new(options)`, you can pass a table containing any of the parameters below. Many parameters accept a single value, an array of values (picked randomly), or a range table (`{min, max}` or `{min = x, max = y}`).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `position` | `Vec3` | `Vec3(0,0,0)` | The world position origin of the emitter system. |
| `space` | `string` | `"world"` | `"world"` (particles move freely) or `"local"` (particles move with emitter). |
| `max_particles` | `number` | `1000` | Hard cap tracking safety threshold to prevent runaway memory arrays. |
| `rate` | `number | table` | `10` | Continuous flow particles per second. Supports range tables. |
| `shape` | `string` | `"point"` | Emission boundary: `"point"`, `"box"`, `"sphere"`, or `"disc"`. |
| `shape_size` | `Vec3 | number` | `Vec3(0.1,0.1,0.1)` | Scale of the bounding emitter shape (Radius if sphere/disc). |
| `shape_edge` | `boolean` | `false` | If true, particles only spawn on the outer shell/rim of the shape. |
| `lifetime` | `number | table` | `5` | How long particles live in seconds. Supports ranges. |
| `velocity` | `Vec3 | table` | `Vec3(0,1,0)` | Base velocity direction vector. Supports ranges/choices. |
| `spread` | `Vec3 | table` | `Vec3(1,1,1)` | Maximum random directional deviation variation. |
| `gravity` | `Vec3 | table` | `Vec3(0,-0.5,0)` | Continuous acceleration vector applied every frame. |
| `drag` | `number` | `0` | Air resistance deceleration coefficient (higher = slows down faster). |
| `color_start` | `Vec4 | table` | `Vec4(1,1,1,1)` | Initial particle RGBA color color. |
| `color_end` | `Vec4 | table` | `nil` | Target color gradient at end of lifetime. Overrides `fade`. |
| `size_start` | `Vec3 | number` | `Vec3(0.1,0.1,0.1)` | Starting particle box dimensions. |
| `size_end` | `Vec3 | number` | `nil` | Target size dimensions at end of lifetime. |
| `fade` | `boolean` | `true` | If `color_end` is nil, automatically fades alpha down to `0`. |
| `rotation_speed` | `number | table` | `0` | Rotational speed in radians per second. |
| `bursts` | `table` | `nil` | Table array containing timed/interval burst blueprints. |
| `custom_update` | `function` | `nil` | Evaluation callback injection hook: `function(p, dt, progress)`. |

---

## Advanced Usage

### Burst Profiles

You can orchestrate complex bursts alongside or instead of a constant `rate`. Bursts can happen at an absolute timestamp or loop indefinitely on a interval timer:

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

Take complete creative control over individual particle trajectories by manipulating internal particle attributes inside the `custom_update` parameter. The modifier receives the particle object `p`, the delta-time `dt`, and the normalized lifetime progression `progress` (a float floating from `0.0` at birth to `1.0` at death):

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

Renders the active particles inside the active graphics pipeline. Put this inside `lovr.draw(pass)`.

#### `system:burst(count)`

Forcefully causes the emitter to spit out an explicit number of particles instantly.

#### `system:toggle()`

Toggles whether the system is active or paused. Paused systems stop emitting but will continue to process/draw existing particles until they expire.

#### `system:reset()`

Flushes all active particles out of the lookup array and rewinds system-wide elapsed timers back to zero. Useful for re-triggering one-shot explosion schedules.
