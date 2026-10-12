# gate.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: run the focused pane's repository gate, its pre-commit checks, with one key.

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/plugins/gate.lua`:

```lua
return { "masshirodev/gate.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/gate.ranma ~/.config/ranma/pack/plugins/start/gate.ranma
```

Needs: git, and the tools the gate itself runs (cargo, yarn/npm/pnpm/bun, go, ruff, pytest). GNU `tail` for the float.

## What it does

```text
gate: run the focused pane's repository gate (its pre-commit checks) with
one key, and see how it went.

leader shift+t finds the repository the focused pane is in and runs its gate
in the background, its output followed in a float. The pane is badged
● gate while it runs, then ✓ gate ok or ✗ gate failed. Closing the float
leaves the gate running; a toast says how it ended when the float is not on
screen. Pressed again while that repository's gate runs, it says so (and
shows the float again) instead of starting a second.

The gate runs in the repository's root with ranma's own environment, not the
pane shell's: a PATH or virtualenv only that shell set is not seen; put it in
the .ranma-gate. The float is the one `ranma open --float` opens, not
`ranma popup`: that is for scripts in panes, and a plugin's processes do not
know which ranma they run under.

The gate, the first that answers:
  1. a `.ranma-gate` file at the root: one shell command, or one per line,
     run in turn until one fails (blank lines and # comments skipped);
  2. require("gate").setup { commands = { <repo name> = "<command>" } };
  3. what the root holds, each found one run in turn:
       Cargo.toml      cargo fmt --check && cargo clippy --all-targets
                       -- -D warnings && cargo test
       package.json    <pm> run lint / check / test, those that exist; pm
                       from packageManager, else the lockfile, else npm
       go.mod          go vet ./... && go test ./...
       pyproject.toml  ruff check . and pytest, each when the project uses
                       it (in .venv/bin, or configured in pyproject.toml)

The palette's `gate` command: no argument runs it; `log` shows the last
run's output again, `stop` ends a running gate, `clear` takes the badges off.
Options (settings panel, "gate" group): gate.timeout, gate.badges. The key
and the commands table are require("gate").setup's (key = false binds none).
When a gate ends, the event "user:gate_done" gets { name, root, ok, status,
duration, pane }. Logs: $XDG_STATE_HOME/ranma/gate/<root>.log.

ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Pane
handles", "Timers and processes", "Hooks").
```

## Binds and commands

| Key / command | Does |
| --- | --- |
| `leader shift+t` | Run the focused pane's repository gate, or show the running one. |
| `gate` (palette) | The same. |
| `gate log` | Show the last run's output and how it ended. |
| `gate stop` | Stop the running gate of this repository. |
| `gate clear` | Take the gate badges off every pane. |

## Options

In ranma's settings panel under `gate`, or with hako's `opts` (`{ "masshirodev/gate.ranma", opts = { ... } }`), or `ranma.set { gate = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `gate.timeout` | `1800` | Seconds before a gate that is still running is stopped; 0 for none. |
| `gate.badges` | `true` | Mark the pane a gate ran from: ● running, ✓ ok, ✗ failed. |

The key and the per-repository commands are a table, which an option cannot hold, so they are `setup`'s. With hako, in its `config`:

```lua
return {
  "masshirodev/gate.ranma",
  config = function()
    require("gate").setup {
      key = "shift+t",                -- the default; false binds none
      commands = {                    -- repo directory name (or full root) -> command
        kumiko = "yarn run lint && yarn run check && yarn run test:affected",
        ranma = "cargo test",
      },
    }
  end,
}
```

or in `init.lua` after the plugin loads. An unknown name in `setup` is an error, as in ranma's own config. A `.ranma-gate` file in the repository wins over both.

## License

MIT or Apache-2.0, as ranma.
