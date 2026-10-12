# AGENTS.md

gate.ranma is a ranma plugin in Lua: `plugin/gate.lua` runs gates and shows
them, `lua/gate.lua` decides which command is a repository's gate and holds
`setup`, and `bin/gate-view` is the float that follows a run's log. The header
comment of `plugin/gate.lua` is the reference that `README.md` repeats. ranma's
API is https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md
(`ranma --dump-types` prints it as LuaLS annotations).

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit, and an option goes in the README's table.
- Use only API the latest ranma release has: CI loads the plugin into it.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server.
  CI (`.github/workflows/ci.yml`) loads it into the latest ranma release on
  every push and fails if it does not.
- Try gates on small throwaway repositories, never on a real project's: those
  are slow, and saving a `.lua` file here reloads any ranma that loads it.
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.
