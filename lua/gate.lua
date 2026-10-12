-- gate: which command is a repository's gate, and the configuration that
-- cannot be an option (a table of commands, and the key). plugin/gate.lua runs
-- it; see its header for what the plugin does.

local M = {}

M.DEFAULT_KEY = "shift+t"

-- What setup set: repo name (or root path) -> a shell command, and the key
-- the plugin binds (false for none).
M.commands = {}
M.key = M.DEFAULT_KEY

-- Set while plugin/gate.lua loads: what the key runs.
M.run = nil

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

M.read = read
M.exists = exists

-- Lines of a .ranma-gate as one command: each line that is not blank or a
-- `#` comment runs in turn, and the first that fails stops the gate. Also the
-- lines as written, for the float to show.
local function lines(text)
  local cmds = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:find("^#") then cmds[#cmds + 1] = line end
  end
  if #cmds == 0 then return nil end
  local shown = table.concat(cmds, "\n")
  if #cmds == 1 then return cmds[1], shown end
  local run = {}
  for i, c in ipairs(cmds) do run[i] = "{ " .. c .. "\n}" end
  return table.concat(run, " && "), shown
end

-- yarn, npm, pnpm or bun: packageManager first, then the lockfile.
local function runner(root, pkg)
  local pm = type(pkg.packageManager) == "string" and pkg.packageManager:match("^(%a+)@")
  if pm == "yarn" or pm == "npm" or pm == "pnpm" or pm == "bun" then return pm end
  if exists(root .. "/yarn.lock") then return "yarn" end
  if exists(root .. "/pnpm-lock.yaml") then return "pnpm" end
  if exists(root .. "/bun.lock") or exists(root .. "/bun.lockb") then return "bun" end
  return "npm"
end

local function node(root)
  local text = read(root .. "/package.json")
  if not text then return nil end
  local ok, pkg = pcall(ranma.json.decode, text)
  if not ok or type(pkg) ~= "table" or type(pkg.scripts) ~= "table" then return nil end
  local pm, parts = runner(root, pkg), {}
  -- Always `<pm> run <script>`: Yarn 1 has a builtin `check` that verifies
  -- node_modules and typechecks nothing, so bare `yarn check` passes silently.
  for _, s in ipairs({ "lint", "check", "test" }) do
    if pkg.scripts[s] then parts[#parts + 1] = pm .. " run " .. s end
  end
  return #parts > 0 and table.concat(parts, " && ") or nil
end

-- ruff and pytest, each when the project uses it: in its .venv, or named in
-- pyproject.toml (or its own config file).
local function python(root)
  local text = read(root .. "/pyproject.toml")
  if not text then return nil end
  local parts = {}
  local function tool(name, args, configured)
    local venv = ".venv/bin/" .. name
    if exists(root .. "/" .. venv) then
      parts[#parts + 1] = venv .. args
    elseif configured then
      parts[#parts + 1] = name .. args
    end
  end
  tool("ruff", " check .", text:find("[tool.ruff", 1, true) or exists(root .. "/ruff.toml")
    or exists(root .. "/.ruff.toml"))
  tool("pytest", "", text:find("[tool.pytest", 1, true) or exists(root .. "/pytest.ini"))
  return #parts > 0 and table.concat(parts, " && ") or nil
end

local DETECT = {
  { "Cargo.toml", function()
    return "cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test"
  end },
  { "package.json", node },
  { "go.mod", function() return "go vet ./... && go test ./..." end },
  { "pyproject.toml", python },
}

-- The gate of the repository at `root`: the command, where it came from, and
-- the command as the float shows it; or nil and why there is none.
function M.find(root)
  local file = read(root .. "/.ranma-gate")
  if file then
    local cmd, shown = lines(file)
    if cmd then return cmd, ".ranma-gate", shown end
    return nil, ".ranma-gate has no command in it"
  end
  local name = root:match("([^/]+)/*$") or root
  local set = M.commands[root] or M.commands[name]
  if set then return set, "setup", set end
  local cmds, found = {}, {}
  for _, d in ipairs(DETECT) do
    if exists(root .. "/" .. d[1]) then
      local cmd = d[2](root)
      if cmd then
        cmds[#cmds + 1] = cmd
        found[#found + 1] = d[1]
      end
    end
  end
  if #cmds == 0 then
    return nil, "no gate: add a .ranma-gate, or a command for " .. name .. " in setup"
  end
  local cmd = table.concat(cmds, " && ")
  return cmd, table.concat(found, " + "), cmd
end

local KNOWN = { commands = true, key = true }

-- require("gate").setup { commands = { ranma = "cargo test" }, key = "shift+t" }
-- While ranma loads (init.lua, or a hako spec's config). Strict, like ranma's
-- own config: an unknown name is an error.
function M.setup(opts)
  opts = opts or {}
  for k in pairs(opts) do
    if not KNOWN[k] then
      error("gate.setup: unknown option `" .. tostring(k) .. "` (commands, key)", 2)
    end
  end
  if opts.commands ~= nil then
    if type(opts.commands) ~= "table" then error("gate.setup: commands is a table", 2) end
    for name, cmd in pairs(opts.commands) do
      if type(name) ~= "string" or type(cmd) ~= "string" then
        error("gate.setup: commands maps a repo name to a shell command", 2)
      end
    end
    M.commands = opts.commands
  end
  if opts.key ~= nil then
    if opts.key ~= false and type(opts.key) ~= "string" then
      error("gate.setup: key is a chord or false", 2)
    end
    if M.key then ranma.unbind(M.key) end
    M.key = opts.key
    if M.key and M.run then
      ranma.bind(M.key, M.run, { desc = "gate", exit = true })
    end
  end
end

return M
