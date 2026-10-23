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
local EMIT_EPSILON = 1e-9
local INSTANCE_CAPACITY_HINT = 8192

local particles = {}

-- LÖVR 0.18 stored vectors as userdata; 0.19 uses tables. Both expose the
-- components through x/y/z(/w), so component access is the portable test.
local function is_vector(v)
  return type(v) == 'userdata' or (type(v) == 'table' and v.x ~= nil)
end

-- LÖVR 0.19's legacy global `Vec4` is the same 3D table vector as `Vec3`
-- (the fourth component is dropped), so a color/row vector needs its `w`
-- assigned explicitly. On 0.18 `Vec4` is already 4D; assigning `w` is a
-- harmless no-op there.
local function new_vec4(x, y, z, w)
  local v = Vec4(x, y, z, w)
  v.w = w or 1
  return v
end

---Create a 4-component color/vector. Use this instead of the legacy global
-- `Vec4` on LÖVR 0.19, where `Vec4` is aliased to the 3D vector and drops `w`.
function particles.vec4(x, y, z, w)
  return new_vec4(x, y, z, w)
end

local function make_vector(vec_constructor, dimensions, ...)
  if dimensions == 4 then
    return new_vec4(...)
  end
  return vec_constructor(...)
end

-- 0.19's Vec3(existing) returns the same table (copy constructors were
-- deprecated), so copies must be explicit. This also avoids mutating option
-- tables supplied by callers.
local function copy_vector(v, vec_constructor, dimensions)
  if dimensions == 4 then
    return new_vec4(v.x, v.y, v.z, v.w or 1)
  end
  return vec_constructor(v.x, v.y, v.z)
end

local function as_vector(v, vec_constructor, dimensions)
  if is_vector(v) then
    return copy_vector(v, vec_constructor, dimensions)
  end
  if dimensions == 4 then
    return new_vec4(v, v, v, 1)
  end
  return vec_constructor(v)
end

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
  if val == nil then
    if default then return copy_vector(default, vec_constructor, dimensions) end
    return make_vector(vec_constructor, dimensions, 0, 0, 0, dimensions == 4 and 1 or nil)
  end
  if is_vector(val) then
    return copy_vector(val, vec_constructor, dimensions)
  elseif type(val) == 'table' then
    if val.min and val.max then
      local minV = as_vector(val.min, vec_constructor, dimensions)
      local maxV = as_vector(val.max, vec_constructor, dimensions)
      local components = {'x', 'y', 'z', 'w'}
      local args = {}
      for i = 1, dimensions do
        args[i] = minV[components[i]] + math.random() * (maxV[components[i]] - minV[components[i]])
      end
      return make_vector(vec_constructor, dimensions, unpack(args))
    elseif #val == 2 and type(val[1]) == 'number' and type(val[2]) == 'number' then
      -- Two numbers are the {min, max} shorthand; arrays of vectors are choices.
      local minV = make_vector(vec_constructor, dimensions, val[1])
      local maxV = make_vector(vec_constructor, dimensions, val[2])
      local components = {'x', 'y', 'z', 'w'}
      local args = {}
      for i = 1, dimensions do
        args[i] = minV[components[i]] + math.random() * (maxV[components[i]] - minV[components[i]])
      end
      return make_vector(vec_constructor, dimensions, unpack(args))
    elseif #val > 0 then
      return as_vector(val[math.random(#val)], vec_constructor, dimensions)
    end
  end
  return as_vector(val, vec_constructor, dimensions)
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
    pos.x, pos.y, pos.z = rx * size.x * 0.5, ry * size.y * 0.5, rz * size.z * 0.5
  elseif shape == 'sphere' then
    local radius = random_value(shape_size, 1)
    local theta = math.random() * TWO_PI
    local phi = math.acos(math.random() * 2 - 1)
    local r = edge_only and 1 or (math.random() ^ (1 / 3))
    r = r * radius
    pos.x = r * math.sin(phi) * math.cos(theta)
    pos.y = r * math.sin(phi) * math.sin(theta)
    pos.z = r * math.cos(phi)
  elseif shape == 'disc' then
    local radius = random_value(shape_size, 1)
    local theta = math.random() * TWO_PI
    local r = edge_only and radius or (math.sqrt(math.random()) * radius)
    pos.x, pos.y, pos.z = r * math.cos(theta), 0, r * math.sin(theta)
  end

  return pos
end

-- Instanced rendering -----------------------------------------------------

local CUBE_VERTICES = {
  { -0.5, -0.5, -0.5 }, { 0.5, -0.5, -0.5 }, { 0.5, 0.5, -0.5 }, { -0.5, 0.5, -0.5 },
  { -0.5, -0.5, 0.5 }, { 0.5, -0.5, 0.5 }, { 0.5, 0.5, 0.5 }, { -0.5, 0.5, 0.5 }
}

local CUBE_INDICES = {
  5, 6, 7, 5, 7, 8, -- +Z
  1, 4, 3, 1, 3, 2, -- -Z
  2, 3, 7, 2, 7, 6, -- +X
  1, 5, 8, 1, 8, 4, -- -X
  4, 8, 7, 4, 7, 3, -- +Y
  1, 2, 6, 1, 6, 5  -- -Y
}

-- `Color` is a built-in varying: the generated vertex main() fills it before calling lovrmain(),
-- so assigning it here gives each instance its own RGBA color.
local INSTANCED_VERTEX_SHADER = [[
  buffer TransformBuffer { mat4 Transforms[]; };
  buffer ColorBuffer { vec4 Colors[]; };

  vec4 lovrmain() {
    Color = Colors[InstanceIndex];
    return Projection * View * Transforms[InstanceIndex] * VertexPosition;
  }
]]

local INSTANCED_FRAGMENT_SHADER = [[
  vec4 lovrmain() {
    return Color;
  }
]]

local instanced_shader
local instanced_cube
local instanced_supported = true

local function get_instanced_resources()
  if not instanced_supported or not (lovr and lovr.graphics) then
    return nil, nil
  end

  if not instanced_shader then
    local ok, shader = pcall(lovr.graphics.newShader, INSTANCED_VERTEX_SHADER, INSTANCED_FRAGMENT_SHADER)
    if not ok then
      instanced_supported = false
      return nil, nil
    end
    instanced_shader = shader
  end

  if not instanced_cube then
    local ok, mesh = pcall(function()
      local cube = lovr.graphics.newMesh({ { 'VertexPosition', 'vec3' } }, CUBE_VERTICES)
      cube:setIndices(CUBE_INDICES)
      return cube
    end)
    if not ok then
      instanced_supported = false
      return nil, nil
    end
    instanced_cube = mesh
  end

  return instanced_shader, instanced_cube
end

-- GPU simulation ----------------------------------------------------------

local PARTICLE_FORMAT = {
  { 'position', 'vec4' },   -- xyz + birth time
  { 'velocity', 'vec4' },   -- xyz + lifetime
  { 'colorStart', 'vec4' },
  { 'colorEnd', 'vec4' },
  { 'sizeStart', 'vec4' },  -- xyz + rotation speed
  { 'sizeEnd', 'vec4' },    -- xyz
  { 'axis', 'vec4' }        -- xyz + flags
}

-- Particles are integrated analytically on the GPU, so no per-frame state upload is needed.
-- Flags: 1 = color gradient, 2 = size gradient, 4 = fade alpha.
local COMPUTE_SHADER = [[
  layout(local_size_x = 64) in;

  struct Particle {
    vec4 position;
    vec4 velocity;
    vec4 colorStart;
    vec4 colorEnd;
    vec4 sizeStart;
    vec4 sizeEnd;
    vec4 axis;
  };

  buffer ParticleBuffer { Particle Particles[]; };
  buffer TransformBuffer { mat4 Transforms[]; };
  buffer ColorBuffer { vec4 Colors[]; };

  uniform float Now;
  uniform vec3 Gravity;
  uniform float Drag;
  uniform vec3 Emitter;
  uniform uint ParticleCount;

  void lovrmain() {
    uint i = GlobalThreadID.x;
    if (i >= ParticleCount) return;

    Particle p = Particles[i];
    float age = Now - p.position.w;
    float lifetime = p.velocity.w;

    if (age < 0.0 || age >= lifetime) {
      Transforms[i] = mat4(0.0);
      Colors[i] = vec4(0.0);
      return;
    }

    float t = age / lifetime;
    vec3 displacement;
    if (Drag > 0.0) {
      vec3 terminal = Gravity / Drag;
      displacement = terminal * age + (p.velocity.xyz - terminal) * (1.0 - exp(-Drag * age)) / Drag;
    } else {
      displacement = p.velocity.xyz * age + 0.5 * Gravity * age * age;
    }

    vec3 position = p.position.xyz + Emitter + displacement;
    float angle = p.sizeStart.w * age;
    vec3 size = mix(p.sizeStart.xyz, p.sizeEnd.xyz, t);

    int flags = int(p.axis.w);
    vec4 color = p.colorStart;
    if ((flags & 1) != 0) {
      color = mix(p.colorStart, p.colorEnd, t);
    } else if ((flags & 4) != 0) {
      color.a = p.colorStart.a * (1.0 - t);
    }

    vec3 axis = p.axis.xyz;
    float axisLength = length(axis);
    axis = axisLength > 0.0 ? axis / axisLength : vec3(0.0, 1.0, 0.0);
    float c = cos(angle);
    float s = sin(angle);
    float ic = 1.0 - c;
    float x = axis.x;
    float y = axis.y;
    float z = axis.z;
    mat3 rotation = mat3(
      vec3(ic * x * x + c,     ic * x * y + s * z, ic * x * z - s * y),
      vec3(ic * x * y - s * z, ic * y * y + c,     ic * y * z + s * x),
      vec3(ic * x * z + s * y, ic * y * z - s * x, ic * z * z + c)
    );

    Transforms[i] = mat4(
      vec4(rotation[0] * size.x, 0.0),
      vec4(rotation[1] * size.y, 0.0),
      vec4(rotation[2] * size.z, 0.0),
      vec4(position, 1.0)
    );
    Colors[i] = color;
  }
]]

local compute_shader
local compute_supported = true

local function get_compute_shader()
  if compute_shader then return compute_shader end
  if not compute_supported or not (lovr and lovr.graphics) then return nil end

  local ok, shader = pcall(lovr.graphics.newShader, COMPUTE_SHADER)
  if not ok then
    compute_supported = false
    return nil
  end

  compute_shader = shader
  return shader
end

local function init_gpu_system(system)
  local render_shader, cube = get_instanced_resources()
  local simulate_shader = get_compute_shader()
  if not render_shader or not cube or not simulate_shader then return false end

  local capacity = math.max(1, math.floor(system.max_particles or 1000))
  local particle_buffer = lovr.graphics.newBuffer(PARTICLE_FORMAT, capacity)
  local transform_buffer = lovr.graphics.newBuffer('mat4', capacity)
  local color_buffer = lovr.graphics.newBuffer('vec4', capacity)
  if not particle_buffer or not transform_buffer or not color_buffer then return false end

  -- Reversed so table.remove() hands out slot 1 first, keeping the drawn instance count small.
  local free = {}
  for i = 1, capacity do free[i] = capacity - i + 1 end

  local row = {}
  system._gpu_capacity = capacity
  system._particle_buffer = particle_buffer
  system._transform_buffer = transform_buffer
  system._color_buffer = color_buffer
  system._free_slots = free
  system._death_times = {}
  system._active_count = 0
  system._slot_high = 0
  system._emit_row = row
  system._emit_list = { row }
  system._emitter_offset = Vec3(0, 0, 0)
  system._render_shader = render_shader
  system._cube = cube
  system._compute_shader = simulate_shader
  if not is_vector(system.gravity) then
    system._gpu_gravity = random_vec3(system.gravity, Vec3(0, -0.5, 0))
  end
  return true
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
    color_start = new_vec4(1, 1, 1, 1),
    color_end = nil,
    size_start = Vec3(0.1, 0.1, 0.1),
    size_end = nil,
    fade = true,

    -- Rotation settings
    rotation_speed = 0,

    -- Rendering
    render_mode = "instanced", -- "instanced" (one draw) or "immediate" (one box per particle)
    simulation = "auto",       -- "auto", "gpu", or "cpu"
    blend_mode = nil,          -- applied to the Pass only when not nil
    depth_write = nil,         -- applied to the Pass only when not nil

    -- Burst profiles
    bursts = nil,

    -- Custom Update Modifier Hook
    custom_update = nil,

    -- Internal State
    particles = {},
    particle_pool = {},
    timer = 0,
    elapsed_time = 0,
    active = true,
    destroyed = false,

    -- Instanced renderer resources (created lazily on the first draw)
    _instanced_failed = false,
    _instance_capacity = nil,
    _transform_buffer = nil,
    _color_buffer = nil,
    _matrices = {},
    _colors = {}
  }

  -- Merge configurations
  for k, v in pairs(options or {}) do
    system[k] = v
  end

  if is_vector(system.position) then
    system.position = copy_vector(system.position, Vec3, 3)
  else
    system.position = Vec3(system.position)
  end

  -- Pick the simulation backend. GPU simulation keeps particle state in buffers and integrates
  -- analytically on the GPU; it requires the instanced renderer and is incompatible with
  -- custom_update (which needs per-particle Lua state).
  local simulation = system.simulation or "auto"
  if simulation == "auto" then
    if system.custom_update == nil and system.render_mode ~= "immediate" and lovr and lovr.graphics then
      simulation = "gpu"
    else
      simulation = "cpu"
    end
  end

  if simulation ~= "gpu" or system.custom_update ~= nil or system.render_mode == "immediate"
      or not (lovr and lovr.graphics) then
    simulation = "cpu"
  end

  if simulation == "gpu" then
    local ok, initialized = pcall(init_gpu_system, system)
    if not ok or not initialized then simulation = "cpu" end
  end

  system.simulation = simulation

  function system:burst(count)
    if self.destroyed then return end
    for _ = 1, (count or 1) do
      self:emit()
    end
  end

  function system:emit()
    if self.destroyed then return end
    if self.simulation == "gpu" then
      self:_emitGPU()
      return
    end
    if #self.particles >= self.max_particles then return end

    local local_offset = get_shape_offset(self.shape, self.shape_size, self.shape_edge)
    local spawn_pos
    if self.space == "local" then
      spawn_pos = Vec3(local_offset.x, local_offset.y, local_offset.z)
    else
      spawn_pos = Vec3(
        self.position.x + local_offset.x,
        self.position.y + local_offset.y,
        self.position.z + local_offset.z
      )
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

    p.color_start = random_vec4(self.color_start, new_vec4(1, 1, 1, 1))
    p.color_end = self.color_end and random_vec4(self.color_end) or nil
    -- Start from the same sample as color_start so the gradient starts at t = 0.
    p.color = copy_vector(p.color_start, Vec4, 4)

    p.size_start = random_vec3(self.size_start, Vec3(0.1, 0.1, 0.1))
    p.size_end = self.size_end and random_vec3(self.size_end) or nil
    p.size = copy_vector(p.size_start, Vec3, 3)

    p.rotation = 0
    p.rotation_speed = random_value(self.rotation_speed, 0)
    p.rotation_axis = Vec3(math.random(), math.random(), math.random()):normalize()

    table.insert(self.particles, p)
  end

  function system:reset()
    if self.destroyed then return end
    if self.simulation == "gpu" then
      self:_resetGPU()
    else
      -- Return particles to pool
      for _, p in ipairs(self.particles) do
        table.insert(self.particle_pool, p)
      end
      self.particles = {}
    end
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
    if self.destroyed then return end

    self.elapsed_time = self.elapsed_time + dt

    if self.active then
      -- Sample the rate per emitted particle instead of per frame. Re-rolling the interval
      -- every frame made range specs jitter, and a slow frame used to swallow bursts.
      self.timer = self.timer + dt
      while true do
        local current_rate = random_value(self.rate, 10)
        if current_rate <= 0 then
          self.timer = 0
          break
        end

        local emit_interval = 1 / current_rate
        if self.timer < emit_interval - EMIT_EPSILON then break end
        if self.simulation == "gpu" then
          if #self._free_slots == 0 then
            self.timer = 0
            break
          end
        elseif #self.particles >= self.max_particles then
          self.timer = 0
          break
        end

        self:emit()
        self.timer = self.timer - emit_interval
      end

      if self.bursts then
        for _, b in ipairs(self.bursts) do
          if b.time then
            if self.elapsed_time >= b.time and not b.fired then
              self:burst(b.count)
              b.fired = true
            end
          elseif b.interval and b.interval > 0 then
            b.last_fired = b.last_fired or 0
            -- Catch up on every interval that elapsed; a long frame used to swallow them.
            while self.elapsed_time - b.last_fired >= b.interval do
              self:burst(b.count)
              b.last_fired = b.last_fired + b.interval
            end
          end
        end
      end
    elseif self.bursts then
      -- Don't queue up interval bursts while paused.
      for _, b in ipairs(self.bursts) do
        if b.interval then b.last_fired = self.elapsed_time end
      end
    end

    if self.simulation == "gpu" then
      if self._active_count > 0 then
        self:_reapGPUSlots()
      end
      return
    end

    -- Use the gravity vector as-is (so runtime mutation works); only sample range/choice specs.
    local current_gravity = self.gravity
    if not is_vector(current_gravity) then
      current_gravity = random_vec3(current_gravity, Vec3(0, -0.5, 0))
    end
    local gx, gy, gz = current_gravity.x * dt, current_gravity.y * dt, current_gravity.z * dt
    local drag = nil
    if self.drag and self.drag > 0 then
      drag = 1 - self.drag * dt
    end
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
        p.velocity.x = p.velocity.x + gx
        p.velocity.y = p.velocity.y + gy
        p.velocity.z = p.velocity.z + gz
        if drag then
          p.velocity.x = p.velocity.x * drag
          p.velocity.y = p.velocity.y * drag
          p.velocity.z = p.velocity.z * drag
        end
        p.position.x = p.position.x + p.velocity.x * dt
        p.position.y = p.position.y + p.velocity.y * dt
        p.position.z = p.position.z + p.velocity.z * dt

        -- Angular Mechanics
        if p.rotation_speed ~= 0 then
          p.rotation = p.rotation + p.rotation_speed * dt
        end

        -- Color Transition Gradient
        if p.color_end then
          p.color.x = p.color_start.x + (p.color_end.x - p.color_start.x) * t
          p.color.y = p.color_start.y + (p.color_end.y - p.color_start.y) * t
          p.color.z = p.color_start.z + (p.color_end.z - p.color_start.z) * t
          p.color.w = p.color_start.w + (p.color_end.w - p.color_start.w) * t
        elseif self.fade then
          p.color.w = p.color_start.w * (1 - t)
        end

        -- Scale size progression
        if p.size_end then
          p.size.x = p.size_start.x + (p.size_end.x - p.size_start.x) * t
          p.size.y = p.size_start.y + (p.size_end.y - p.size_start.y) * t
          p.size.z = p.size_start.z + (p.size_end.z - p.size_start.z) * t
        end

        if self.custom_update then
          self.custom_update(p, dt, t)
        end
        i = i + 1
      end
    end
  end

  function system:_emitGPU()
    local slot = table.remove(self._free_slots)
    if not slot then return end

    local offset = get_shape_offset(self.shape, self.shape_size, self.shape_edge)
    local ox, oy, oz = offset:unpack()
    local x, y, z
    if self.space == "local" then
      x, y, z = ox, oy, oz
    else
      local px, py, pz = self.position:unpack()
      x, y, z = px + ox, py + oy, pz + oz
    end

    local lifetime = random_value(self.lifetime, 5)
    lifetime = lifetime * (1 - LIFETIME_VARIATION + math.random() * LIFETIME_VARIATION * 2)

    local base = random_vec3(self.velocity, Vec3(0, 1, 0))
    local spread = random_vec3(self.spread, Vec3(0, 0, 0))
    local vx = base.x + (math.random() * 2 - 1) * spread.x
    local vy = base.y + (math.random() * 2 - 1) * spread.y
    local vz = base.z + (math.random() * 2 - 1) * spread.z

    local color_start = random_vec4(self.color_start, new_vec4(1, 1, 1, 1))
    local color_end = self.color_end and random_vec4(self.color_end) or color_start
    local size_start = random_vec3(self.size_start, Vec3(0.1, 0.1, 0.1))
    local size_end = self.size_end and random_vec3(self.size_end) or size_start
    local sx, sy, sz = size_start:unpack()
    local ex, ey, ez = size_end:unpack()
    local speed = random_value(self.rotation_speed, 0)
    local axis = Vec3(math.random(), math.random(), math.random()):normalize()
    local ax, ay, az = axis:unpack()

    local flags = 0
    if self.color_end then flags = flags + 1 end
    if self.size_end then flags = flags + 2 end
    if self.fade then flags = flags + 4 end

    local row = self._emit_row
    row.position = new_vec4(x, y, z, self.elapsed_time)
    row.velocity = new_vec4(vx, vy, vz, lifetime)
    row.colorStart = color_start
    row.colorEnd = color_end
    row.sizeStart = new_vec4(sx, sy, sz, speed)
    row.sizeEnd = new_vec4(ex, ey, ez, 0)
    row.axis = new_vec4(ax, ay, az, flags)

    self._particle_buffer:setData(self._emit_list, slot)
    self._death_times[slot] = self.elapsed_time + lifetime
    self._active_count = self._active_count + 1
    if slot > self._slot_high then self._slot_high = slot end
  end

  function system:_reapGPUSlots()
    local now = self.elapsed_time
    local deaths = self._death_times
    local free = self._free_slots
    local count = self._active_count
    for slot = 1, self._slot_high do
      local death = deaths[slot]
      if death and death <= now then
        deaths[slot] = nil
        free[#free + 1] = slot
        count = count - 1
      end
    end
    while self._slot_high > 0 and deaths[self._slot_high] == nil do
      self._slot_high = self._slot_high - 1
    end
    self._active_count = count
  end

  function system:_resetGPU()
    self._particle_buffer:clear()
    self._active_count = 0
    self._slot_high = 0
    self._death_times = {}
    local free = {}
    for i = 1, self._gpu_capacity do free[i] = self._gpu_capacity - i + 1 end
    self._free_slots = free
  end

  function system:_drawGPU(pass)
    local count = self._slot_high
    if count == 0 then return end

    local gravity = self.gravity
    if not is_vector(gravity) then
      gravity = self._gpu_gravity or Vec3(0, -0.5, 0)
    end

    local emitter = self._emitter_offset
    if self.space == "local" then
      emitter.x, emitter.y, emitter.z = self.position.x, self.position.y, self.position.z
    else
      emitter.x, emitter.y, emitter.z = 0, 0, 0
    end

    pass:setShader(self._compute_shader)
    pass:send('ParticleBuffer', self._particle_buffer)
    pass:send('TransformBuffer', self._transform_buffer)
    pass:send('ColorBuffer', self._color_buffer)
    pass:send('Now', self.elapsed_time)
    pass:send('Gravity', gravity)
    pass:send('Drag', self.drag or 0)
    pass:send('Emitter', emitter)
    pass:send('ParticleCount', count)
    pass:compute(math.ceil(count / 64))

    pass:setShader(self._render_shader)
    pass:send('TransformBuffer', self._transform_buffer)
    pass:send('ColorBuffer', self._color_buffer)
    pass:draw(self._cube, nil, count)
    pass:setShader(nil)
  end

  function system:_ensureInstanceBuffers(count)
    if self._instance_capacity and self._instance_capacity >= count then return true end

    local max = self.max_particles or count
    local capacity = math.min(max, INSTANCE_CAPACITY_HINT)
    if self._instance_capacity then
      capacity = math.max(capacity, self._instance_capacity * 2)
    end
    capacity = math.max(capacity, count, 1)

    local ok = pcall(function()
      self._transform_buffer = lovr.graphics.newBuffer('mat4', capacity)
      self._color_buffer = lovr.graphics.newBuffer('vec4', capacity)
    end)
    if not ok then return false end

    self._instance_capacity = capacity
    self._matrices = {}
    self._colors = {}
    return true
  end

  function system:_writeInstances(count)
    local matrices = self._matrices
    local colors = self._colors
    local is_local = self.space == "local"
    local ex, ey, ez
    if is_local then
      ex, ey, ez = self.position:unpack()
    end

    local i = 0
    for _, p in ipairs(self.particles) do
      -- unpack() is one C call per vector; Mat4:set does the T * R * S composition in C.
      local x, y, z = p.position:unpack()
      if is_local then
        x, y, z = x + ex, y + ey, z + ez
      end
      local sx, sy, sz = p.size:unpack()
      local ax, ay, az = p.rotation_axis:unpack()

      local matrix = p._matrix
      if not matrix then
        matrix = Mat4()
        p._matrix = matrix
      end
      matrix:set(x, y, z, sx, sy, sz, p.rotation, ax, ay, az)

      i = i + 1
      matrices[i] = matrix
      colors[i] = p.color
    end

    self._transform_buffer:setData(matrices, 1, 1, count)
    self._color_buffer:setData(colors, 1, 1, count)
  end

  function system:_drawInstanced(pass)
    local count = #self.particles
    local shader, cube = get_instanced_resources()
    if not shader or not self:_ensureInstanceBuffers(count) then return false end
    if not pcall(self._writeInstances, self, count) then return false end

    pass:setShader(shader)
    pass:send('TransformBuffer', self._transform_buffer)
    pass:send('ColorBuffer', self._color_buffer)
    pass:draw(cube, nil, count)
    pass:setShader(nil)
    return true
  end

  function system:draw(pass)
    if self.destroyed then return end
    local count
    if self.simulation == "gpu" then
      count = self._slot_high
    else
      count = #self.particles
    end
    if count == 0 then return end

    if self.blend_mode then pass:setBlendMode(self.blend_mode) end
    if self.depth_write ~= nil then pass:setDepthWrite(self.depth_write) end

    if self.simulation == "gpu" then
      self:_drawGPU(pass)
      return
    end

    if self.render_mode ~= "immediate" and not self._instanced_failed then
      if self:_drawInstanced(pass) then return end
      self._instanced_failed = true
    end

    local is_local = self.space == "local"
    local emitter = self.position

    for _, p in ipairs(self.particles) do
      local x, y, z = p.position.x, p.position.y, p.position.z
      if is_local then
        x, y, z = x + emitter.x, y + emitter.y, z + emitter.z
      end

      pass:setColor(p.color.x, p.color.y, p.color.z, p.color.w)
      if p.rotation ~= 0 and p.rotation_axis then
        local axis = p.rotation_axis
        pass:box(x, y, z, p.size.x, p.size.y, p.size.z, p.rotation, axis.x, axis.y, axis.z)
      else
        pass:box(x, y, z, p.size.x, p.size.y, p.size.z)
      end
    end
  end

  function system:toggle()
    self.active = not self.active
  end

  function system:getParticleCount()
    if self.simulation == "gpu" then
      return self._active_count
    end
    return #self.particles
  end

  function system:isActive()
    return self.active
  end

  function system:setActive(active)
    self.active = not not active
  end

  function system:getElapsedTime()
    return self.elapsed_time
  end

  function system:destroy()
    if self.destroyed then return end
    self:reset()
    self.particles = {}
    self.particle_pool = nil
    if self.simulation == "gpu" then
      self._particle_buffer = nil
      self._transform_buffer = nil
      self._color_buffer = nil
      self._free_slots = nil
      self._death_times = nil
      self._emit_row = nil
      self._emit_list = nil
      self._emitter_offset = nil
      self._gpu_gravity = nil
    else
      self._transform_buffer = nil
      self._color_buffer = nil
      self._instance_capacity = nil
      self._matrices = nil
      self._colors = nil
    end
    self.destroyed = true
  end

  return system
end

return particles
