-- main.lua
local particles = require 'init'

local systems = {}

function lovr.load()
  -- 1. FIRE FOUNTAIN: Dynamic Color Gradients + Sphere Emitter Volume + Air Drag
  table.insert(systems, particles.new({
    position = Vec3(-1.5, 0.5, -3),
    shape = "sphere",
    shape_size = 0.4,           -- Radius of the sphere
    shape_edge = false,         -- Emit throughout the whole volume
    rate = 45,
    lifetime = {1.5, 2.5},      -- Random range for lifetimes
    velocity = Vec3(0, 1.8, 0),
    spread = Vec3(0.3, 0.2, 0.3),
    gravity = Vec3(0, 0.4, 0),  -- Heat floating upwards
    drag = 0.5,                 -- Simulates air resistance slowing things down
    color_start = Vec4(1, 0.8, 0, 1), -- Yellow
    color_end = Vec4(0.2, 0.05, 0.05, 0.0), -- Shifts to faded dark ash smoke
    size_start = Vec3(0.08, 0.08, 0.08),
    size_end = Vec3(0.25, 0.25, 0.25)    -- Expands outwards like real smoke plumes
  }))

  -- 2. MOVING LOCAL AURA RING: Local Space Tracking + Disc Ring Edge Emitter
  table.insert(systems, particles.new({
    position = Vec3(1.5, 1, -3),
    space = "local",            -- Particles stick to and travel along with the emitter position!
    shape = "disc",
    shape_size = 0.5,           -- Radius of ring
    shape_edge = true,          -- Forces emission only along the outer ring rim edge
    rate = 60,
    lifetime = 1.0,
    velocity = Vec3(0, 0, 0),   -- Floats locally
    spread = Vec3(0.1, 0.8, 0.1),
    gravity = Vec3(0, 0, 0),
    color_start = Vec4(0, 1, 0.8, 0.8),
    color_end = Vec4(0, 0.2, 1, 0),
    size_start = 0.04,          -- Shorthand scales work uniformly
    size_end = 0.01,
    rotation_speed = {-3, 3}    -- Random spinning speeds between -3 and +3 rad/s
  }))

  -- 3. EXPLOSIVE BURST SYSTEM: AcidRain Style Bursts + Custom Code Modifiers
  table.insert(systems, particles.new({
    position = Vec3(0, 1.5, -4),
    rate = 0,                   -- Disable constant rate emission...
    bursts = {
      { time = 0, count = 100 },       -- Fire an initial 100 particle explosion wave instantly
      { interval = 2.0, count = 40 }   -- Repeat a burst of 40 particles every 2 seconds
    },
    lifetime = 2.0,
    velocity = Vec3(0, 0.5, 0),
    spread = Vec3(2.5, 2.5, 2.5),      -- Blow out violently in all directions
    gravity = Vec3(0, -0.8, 0),
    color_start = Vec4(1, 0.3, 0.7, 1),
    color_end = Vec4(0.3, 0, 0.5, 0),
    size_start = 0.15,
    size_end = 0.02,
    rotation_speed = {1, 5},
    
    -- Ultimate capability: inject custom equations directly into the engine update loop
    custom_update = function(p, dt, progress)
      -- Let's make particles spiral/zigzag outwards using a sine wave modifier over time
      p.position.x = p.position.x + math.sin(p.age * 10) * 0.02
    end
  }))
end

function lovr.update(dt)
  -- Animate System 2's position back and forth horizontally to demonstrate local space
  local system2 = systems[2]
  if system2 then
    system2.position.x = 1.5 + math.sin(lovr.timer.getTime() * 2) * 0.8
  end

  for _, system in ipairs(systems) do
    system:update(dt)
  end
end

function lovr.draw(pass)
  for _, system in ipairs(systems) do
    system:draw(pass)
  end
end

function lovr.keypressed(key)
  -- Spacebar resets the systems to re-trigger one-shot bursts
  if key == 'space' then
    for _, system in ipairs(systems) do
      system:reset()
    end
  else
    for _, system in ipairs(systems) do
      system:toggle()
    end
  end
end
