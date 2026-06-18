---@diagnostic disable: duplicate-set-field

function lovr.conf(t)

  -- Set the project version and identity
  t.version = '0.0.1'
  t.identity = 'default'

  -- Set save directory precedence
  t.saveprecedence = true

  -- Enable or disable different modules
  t.modules.audio = false
  t.modules.data = false
  t.modules.event = true
  t.modules.graphics = true
  t.modules.headset = false
  t.modules.math = true
  t.modules.physics = true
  t.modules.system = true
  t.modules.thread = false
  t.modules.timer = true

  -- Audio
  --t.audio.spatializer = nil
  --t.audio.samplerate = 48000
  --t.audio.start = true

  -- Graphics
  t.graphics.debug = false
  t.graphics.vsync = false
  t.graphics.stencil = false
  t.graphics.antialias = false
  t.graphics.shadercache = false

  -- Math settings
  t.math.globals = true

  -- Thread settings
  t.thread.workers = -1

  -- Configure the desktop window
  --t.window.width = 1080
  --t.window.height = 600
  t.window.width = 960
  t.window.height = 1045
  --t.window.width = 1920
  --t.window.height = 1080
  --t.window.fullscreen = true
  t.window.resizable = true
  t.window.title = 'particles'
  t.window.icon = nil
end
