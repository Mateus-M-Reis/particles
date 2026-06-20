---@diagnostic disable: duplicate-set-field
---@diagnostic disable: duplicate-doc-field

---@meta -- Diz ao LSP que isso é apenas para definições de tipo, se colocar em arquivo separado

---@class Vec3
---@field x number A coordenada X do vetor
---@field y number A coordenada Y do vetor
---@field z number A coordenada Z do vetor

---@class Vec4
---@field x number A coordenada X do vetor
---@field y number A coordenada Y do vetor
---@field z number A coordenada Z do vetor
---@field w number A coordenada W do vetor

-- Constants
local LIFETIME_VARIATION = 0.1
local TWO_PI = math.pi * 2

local particles = {}

-- Consolidated random helper for scalar values
local function random_value(val, default)
  if val == nil then return default end
  if type(val) == 'number' then
    return val
  elseif type(val) == 'table' then
    if val.min and val.max then
      return val.min + math.random() * (val.max - val.min)
    elseif #val == 2 and type(val[1]) == 'number' and type(val[2]) == 'number' then
      return val[1] + math.random() * (val[2] - val[1])
    elseif #val > 0 then
      return val[math.random(#val)]
    end
  end
  return val
end

-- Consolidated random helper for vector types (Vec3 or Vec4)
local function random_vector(val, default, vec_constructor, dimensions)
  if val == nil then return default and vec_constructor(default) or vec_constructor(0, 0, 0, dimensions == 4 and 1 or nil) end
  if type(val) == 'userdata' or (type(val) == 'table' and val.x) then
    return vec_constructor(val)
  elseif type(val) == 'table' then
    if val.min and val.max then
      local minV, maxV = vec_constructor(val.min), vec_constructor(val.max)
      local components = {'x', 'y', 'z', 'w'}
      local args = {}
      for i = 1, dimensions do
        args[i] = minV[components[i]] + math.random() * (maxV[components[i]] - minV[components[i]])
      end
      return vec_constructor(unpack(args))
    elseif #val == 2 then
      local minV, maxV = vec_constructor(val[1]), vec_constructor(val[2])
      local components = {'x', 'y', 'z', 'w'}
      local args = {}
      for i = 1, dimensions do
        args[i] = minV[components[i]] + math.random() * (maxV[components[i]] - minV[components[i]])
      end
      return vec_constructor(unpack(args))
    elseif #val > 0 then
      return vec_constructor(val[math.random(#val)])
    end
  end
  return vec_constructor(val)
end

local function random_vec3(val, default)
  return random_vector(val, default, Vec3, 3)
end

local function random_vec4(val, default)
  return random_vector(val, default, Vec4, 4)
end

-- Generates 3D spatial emission offset based on configured shape
local function get_shape_offset(shape, shape_size, edge_only)
  local pos = Vec3(0, 0, 0)
  shape = shape or 'point'

  if shape == 'box' then
    local size = random_vec3(shape_size, Vec3(1, 1, 1))
    local rx, ry, rz = math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1
    if edge_only then
      local axis = math.random(1, 3)
      local sign = math.random() > 0.5 and 1 or -1
      if axis == 1 then rx = sign elseif axis == 2 then ry = sign else rz = sign end
    end
    pos:set(rx * size.x * 0.5, ry * size.y * 0.5, rz * size.z * 0.5)
  elseif shape == 'sphere' then
    local radius = random_value(shape_size, 1)
    local theta = math.random() * TWO_PI
    local phi = math.acos(math.random() * 2 - 1)
    local r = edge_only and 1 or (math.random() ^ (1 / 3))
    r = r * radius
    pos:set(
      r * math.sin(phi) * math.cos(theta),
      r * math.sin(phi) * math.sin(theta),
      r * math.cos(phi)
    )
  elseif shape == 'disc' then
    local radius = random_value(shape_size, 1)
    local theta = math.random() * TWO_PI
    local r = edge_only and radius or (math.sqrt(math.random()) * radius)
    pos:set(r * math.cos(theta), 0, r * math.sin(theta))
  end

  return pos
end

function particles.new(options)
  local system = {
    -- Base settings
    position = Vec3(0, 0, 0),
    space = "world",            -- "world" or "local"
    max_particles = 1000,

    -- Emitter properties
    rate = 10,
    shape = "point",
    shape_size = Vec3(0.1, 0.1, 0.1),
    shape_edge = false,

    -- Kinematics
    lifetime = 5,
    velocity = Vec3(0, 1, 0),
    spread = Vec3(1, 1, 1),
    gravity = Vec3(0, -0.5, 0),
    drag = 0,

    -- Appearance progressions over lifetime
    color_start = Vec4(1, 1, 1, 1),
    color_end = nil,
    size_start = Vec3(0.1, 0.1, 0.1),
    size_end = nil,
    fade = true,

    -- Rotation settings
    rotation_speed = 0,

    -- Burst profiles
    bursts = nil,

    -- Custom Update Modifier Hook
    custom_update = nil,

    -- Internal State
    particles = {},
    particle_pool = {},
    timer = 0,
    elapsed_time = 0,
    active = true
  }

  -- Merge configurations
  for k, v in pairs(options or {}) do
    system[k] = v
  end

  system.position = Vec3(system.position)

  function system:burst(count)
    for _ = 1, (count or 1) do
      self:emit()
    end
  end

  function system:emit()
    if #self.particles >= self.max_particles then return end

    local local_offset = get_shape_offset(self.shape, self.shape_size, self.shape_edge)
    local spawn_pos
    if self.space == "local" then
      spawn_pos = Vec3(local_offset)
    else
      spawn_pos = Vec3(self.position):add(local_offset)
    end

    local p_lifetime = random_value(self.lifetime, 5)
    local base_vel = random_vec3(self.velocity, Vec3(0, 1, 0))
    local spread_amt = random_vec3(self.spread, Vec3(0, 0, 0))

    local p_velocity = Vec3(
      base_vel.x + (math.random() * 2 - 1) * spread_amt.x,
      base_vel.y + (math.random() * 2 - 1) * spread_amt.y,
      base_vel.z + (math.random() * 2 - 1) * spread_amt.z
    )

    -- Get particle from pool or create new one
    local p = table.remove(self.particle_pool) or {}

    p.position = spawn_pos
    p.velocity = p_velocity
    p.lifetime = p_lifetime * (1 - LIFETIME_VARIATION + math.random() * LIFETIME_VARIATION * 2)
    p.age = 0

    p.color_start = random_vec4(self.color_start, Vec4(1, 1, 1, 1))
    p.color_end = self.color_end and random_vec4(self.color_end) or nil
    p.color = random_vec4(self.color_start, Vec4(1, 1, 1, 1))

    p.size_start = random_vec3(self.size_start, Vec3(0.1, 0.1, 0.1))
    p.size_end = self.size_end and random_vec3(self.size_end) or nil
    p.size = random_vec3(self.size_start, Vec3(0.1, 0.1, 0.1))

    p.rotation = 0
    p.rotation_axis = Vec3(math.random(), math.random(), math.random()):normalize()
    p.rotation_speed = random_value(self.rotation_speed, 0)

    table.insert(self.particles, p)
  end

  function system:reset()
    -- Return particles to pool
    for _, p in ipairs(self.particles) do
      table.insert(self.particle_pool, p)
    end
    self.particles = {}
    self.timer = 0
    self.elapsed_time = 0
    if self.bursts then
      for _, b in ipairs(self.bursts) do
        b.fired = false
        b.last_fired = nil
      end
    end
  end

  function system:update(dt)
    self.elapsed_time = self.elapsed_time + dt

    if self.active then
      local current_rate = random_value(self.rate, 10)
      if current_rate > 0 then
        self.timer = self.timer + dt
        local emitInterval = 1 / current_rate
        while self.timer >= emitInterval do
          self:emit()
          self.timer = self.timer - emitInterval
        end
      end

      if self.bursts then
        for _, b in ipairs(self.bursts) do
          if b.time then
            if self.elapsed_time >= b.time and not b.fired then
              self:burst(b.count)
              b.fired = true
            end
          elseif b.interval then
            b.last_fired = b.last_fired or 0
            if self.elapsed_time - b.last_fired >= b.interval then
              self:burst(b.count)
              b.last_fired = self.elapsed_time
            end
          end
        end
      end
    end

    local current_gravity = random_vec3(self.gravity, Vec3(0, -0.5, 0))
    local i = 1
    while i <= #self.particles do
      local p = self.particles[i]
      p.age = p.age + dt

      if p.age >= p.lifetime then
        -- Swap with last particle and pop (O(1) instead of O(n))
        self.particles[i] = self.particles[#self.particles]
        table.remove(self.particles)
        -- Return particle to pool
        table.insert(self.particle_pool, p)
        -- Don't increment i since we swapped
      else
        local t = p.age / p.lifetime

        -- Translational Mechanics
        p.velocity:add(current_gravity * dt)
        if self.drag and self.drag > 0 then
          p.velocity:mul(1 - self.drag * dt)
        end
        p.position:add(p.velocity * dt)

        -- Angular Mechanics
        if p.rotation_speed ~= 0 then
          p.rotation = p.rotation + p.rotation_speed * dt
        end

        -- Color Transition Gradient
        if p.color_end then
          p.color:set(
            p.color_start.x + (p.color_end.x - p.color_start.x) * t,
            p.color_start.y + (p.color_end.y - p.color_start.y) * t,
            p.color_start.z + (p.color_end.z - p.color_start.z) * t,
            p.color_start.w + (p.color_end.w - p.color_start.w) * t
          )
        elseif self.fade then
          p.color.w = p.color_start.w * (1 - t)
        end

        -- Scale size progression
        if p.size_end then
          p.size:set(
            p.size_start.x + (p.size_end.x - p.size_start.x) * t,
            p.size_start.y + (p.size_end.y - p.size_start.y) * t,
            p.size_start.z + (p.size_end.z - p.size_start.z) * t
          )
        end

        if self.custom_update then
          self.custom_update(p, dt, t)
        end
        i = i + 1
      end
    end
  end

  function system:draw(pass)
    for _, p in ipairs(self.particles) do
      pass:push()

      if self.space == "local" then
        pass:translate(self.position.x + p.position.x, self.position.y + p.position.y, self.position.z + p.position.z)
      else
        pass:translate(p.position.x, p.position.y, p.position.z)
      end

      if p.rotation ~= 0 then
        pass:rotate(p.rotation, p.rotation_axis.x, p.rotation_axis.y, p.rotation_axis.z)
      end

      pass:setColor(p.color.x, p.color.y, p.color.z, p.color.w)
      pass:box(0, 0, 0, p.size.x, p.size.y, p.size.z)
      pass:pop()
    end
  end

  function system:toggle()
    self.active = not self.active
  end

  function system:getParticleCount()
    return #self.particles
  end

  function system:isActive()
    return self.active
  end

  function system:setActive(active)
    self.active = active
  end

  function system:getElapsedTime()
    return self.elapsed_time
  end

  function system:destroy()
    self:reset()
    self.particle_pool = nil
  end

  return system
end

return particles
