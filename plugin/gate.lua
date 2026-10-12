-- gate: run the focused pane's repository gate (its pre-commit checks) with
-- one key, and see how it went.
--
-- leader shift+t finds the repository the focused pane is in and runs its gate
-- in the background, its output followed in a float. The pane is badged
-- ● gate while it runs, then ✓ gate ok or ✗ gate failed. Closing the float
-- leaves the gate running; a toast says how it ended when the float is not on
-- screen. Pressed again while that repository's gate runs, it says so (and
-- shows the float again) instead of starting a second.
--
-- The gate runs in the repository's root with ranma's own environment, not the
-- pane shell's: a PATH or virtualenv only that shell set is not seen; put it in
-- the .ranma-gate. The float is the one `ranma open --float` opens, not
-- `ranma popup`: that is for scripts in panes, and a plugin's processes do not
-- know which ranma they run under.
--
-- The gate, the first that answers:
--   1. a `.ranma-gate` file at the root: one shell command, or one per line,
--      run in turn until one fails (blank lines and # comments skipped);
--   2. require("gate").setup { commands = { <repo name> = "<command>" } };
--   3. what the root holds, each found one run in turn:
--        Cargo.toml      cargo fmt --check && cargo clippy --all-targets
--                        -- -D warnings && cargo test
--        package.json    <pm> run lint / check / test, those that exist; pm
--                        from packageManager, else the lockfile, else npm
--        go.mod          go vet ./... && go test ./...
--        pyproject.toml  ruff check . and pytest, each when the project uses
--                        it (in .venv/bin, or configured in pyproject.toml)
--
-- The palette's `gate` command: no argument runs it; `log` shows the last
-- run's output again, `stop` ends a running gate, `clear` takes the badges off.
-- Options (settings panel, "gate" group): gate.timeout, gate.badges. The key
-- and the commands table are require("gate").setup's (key = false binds none).
-- When a gate ends, the event "user:gate_done" gets { name, root, ok, status,
-- duration, pane }. Logs: $XDG_STATE_HOME/ranma/gate/<root>.log.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Pane
-- handles", "Timers and processes", "Hooks").

ranma.option("gate.timeout", {
  type = "int", min = 0, max = 7200, step = 60, default = 1800, slider = false,
  name = "Time limit", desc = "Seconds before a gate that is still running is stopped; 0 for none.",
})
ranma.option("gate.badges", {
  type = "bool", default = true,
  name = "Badges", desc = "Mark the pane a gate ran from: ● running, ✓ ok, ✗ failed.",
})

local OWNER = "gate"
local gate, module_path = require("gate")
-- require gives the file it loaded (Lua 5.4); bin/ is beside lua/.
local VIEW = (module_path or package.searchpath("gate", package.path) or ""):gsub("lua/gate%.lua$", "bin/gate-view")
local DIR = (os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")) .. "/ranma/gate"

-- The float is the viewer's exec pane; a rule floats it as it opens.
ranma.rule { command = "*/bin/gate-view*", size = { 80, 70 } }

-- root -> { job, name, source, cmd, pane, started, log, status, viewer }
local runs = {}
-- The last run of each root, finished or not, for `gate log`.
local last = {}
-- The root whose float was just asked for: the next pane to open is it.
local pending = nil
local made_dir = false

local function q(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function badge(p, glyph, word, role)
  if not (p and p:alive()) then return end
  if glyph and ranma.get("gate.badges") then
    p:badge(OWNER, glyph, word, role)
  else
    p:badge(OWNER)
  end
end

local function viewer_shown(run)
  local v = run.viewer and ranma.pane(run.viewer)
  return v ~= nil and v.visible
end

local function view(run)
  pending = run.root
  ranma.action("exec sh " .. table.concat({
    q(VIEW), q(run.log), q(run.status), q(run.name), q(run.source), q(run.shown or run.cmd),
  }, " "))
end

local function files(root)
  if not made_dir then
    os.execute("mkdir -p " .. q(DIR))
    made_dir = true
  end
  local slug = root:gsub("[^%w._-]", "_")
  return DIR .. "/" .. slug .. ".log", DIR .. "/" .. slug .. ".status"
end

local function write(path, text)
  local f = io.open(path, "w")
  if f then
    f:write(text)
    f:close()
  end
end

-- How a run ended, in words: what its shell wrote ("0", the exit status, or
-- "stopped"), else what ranma saw (a timeout is a SIGKILL, no shell left to
-- write it).
local function outcome(run, r)
  local written = gate.read(run.status)
  written = written and written:match("^%s*(.-)%s*$")
  if written and written ~= "" then return written end
  if r.error then return r.error end
  if r.signal then return "signal " .. r.signal end
  return tostring(r.code)
end

local function finished(run, r)
  if runs[run.root] == run then runs[run.root] = nil end
  local status = outcome(run, r)
  local ok = r.code == 0 and status == "0"
  -- The float waits on this file; written here when the shell could not.
  if not gate.read(run.status) or gate.read(run.status) == "" then write(run.status, status) end
  local said = status:match("^%d+$") and ("exit " .. status) or status
  local took = os.time() - run.started
  if ok then
    badge(run.pane, "✓", "gate ok", "normal")
  else
    badge(run.pane, "✗", "gate failed", "urgent")
  end
  if not viewer_shown(run) then
    local text = ok and ("gate ok: " .. run.name .. " (" .. took .. "s)")
      or ("gate failed: " .. run.name .. " (" .. said .. ")")
    ranma.toast(text, { urgent = not ok })
  end
  ranma.emit("gate_done", {
    name = run.name, root = run.root, ok = ok, status = ok and "ok" or said, duration = took,
    pane = run.pane and run.pane.id,
  })
end

local function start(p, root)
  local running = runs[root]
  if running then
    ranma.notify("gate: already running in " .. running.name)
    if not viewer_shown(running) then view(running) end
    return
  end
  local cmd, source, shown = gate.find(root)
  if not cmd then return ranma.notify("gate: " .. source) end
  local log, status = files(root)
  -- Emptied before the float follows them, so it never shows the last run.
  os.remove(status)
  write(log, "")
  local run = {
    root = root, name = root:match("([^/]+)/*$") or root, source = source, cmd = cmd,
    shown = shown, pane = p, started = os.time(), log = log, status = status,
  }
  local timeout = ranma.get("gate.timeout")
  -- The shell writes how it ended, so the float learns it even when ranma
  -- reloads (which ends every job with SIGTERM, and on_exit never runs). The
  -- gate runs in a subshell: an `exit` in a .ranma-gate ends only it.
  local script = "trap 'echo stopped >" .. q(status) .. "; exit 143' TERM HUP\n"
    .. "( " .. cmd .. "\n) >" .. q(log) .. " 2>&1\n"
    .. "rc=$?\necho $rc >" .. q(status) .. "\nexit $rc"
  run.job = ranma.spawn(script, {
    cwd = root,
    timeout = timeout > 0 and timeout or nil,
    on_exit = function(r) finished(run, r) end,
  })
  runs[root] = run
  last[root] = run
  badge(p, "●", "gate", "accent")
  view(run)
end

-- The focused pane's repository root, given to `fn(pane, root)`; spawned, as
-- git may be slow on a big tree and a bind gets 200 ms.
local function with_root(fn)
  local p = ranma.pane()
  if not p then return ranma.notify("gate: no pane") end
  local cwd = p:cwd()
  if not cwd then return ranma.notify("gate: the pane's directory is unknown") end
  ranma.spawn({ "git", "rev-parse", "--show-toplevel" }, {
    cwd = cwd, timeout = 10,
    on_exit = function(r)
      local root = r.code == 0 and r.stdout and r.stdout:match("^([^\n]+)")
      if not root then return ranma.notify("gate: " .. cwd .. " is not in a git repository") end
      fn(p, root)
    end,
  })
end

local function run_gate()
  with_root(start)
end

local actions = {
  log = function()
    with_root(function(_, root)
      local run = runs[root] or last[root]
      if not run then
        -- From before a reload: the files are still there.
        local log, status = files(root)
        if not gate.exists(log) then return ranma.notify("gate: no run of this repository yet") end
        local cmd, source, shown = gate.find(root)
        run = { root = root, name = root:match("([^/]+)/*$") or root, source = source,
                cmd = cmd or "?", shown = shown, log = log, status = status }
        if not gate.exists(status) then write(status, "unknown: ranma reloaded while it ran") end
        last[root] = run
      end
      if not viewer_shown(run) then view(run) end
    end)
  end,
  stop = function()
    with_root(function(_, root)
      local run = runs[root]
      if not (run and ranma.kill(run.job)) then return ranma.notify("gate: none running here") end
      ranma.notify("gate: stopping " .. run.name)
    end)
  end,
  clear = function()
    for _, p in ipairs(ranma.panes()) do p:badge(OWNER) end
  end,
}

ranma.on("pane_open", function(ev)
  if not pending then return end
  local run = runs[pending] or last[pending]
  pending = nil
  if run then run.viewer = ev.pane end
end)

ranma.on("pane_close", function(ev)
  for _, run in pairs(runs) do
    if run.viewer == ev.pane then run.viewer = nil end
  end
end)

gate.run = run_gate
if gate.key then ranma.bind(gate.key, run_gate, { desc = "gate", exit = true }) end

ranma.command("gate", function(arg)
  if arg == nil or arg == "" then return run_gate() end
  local fn = actions[arg]
  if not fn then return ranma.notify("gate: unknown argument `" .. arg .. "` (log, stop, clear)") end
  fn()
end, {
  desc = "run this repository's gate", args = "[log|stop|clear]",
  complete = { "log", "stop", "clear" },
})
