# rsync-tail.yazi

Rsync selected files from [Yazi](https://yazi-rs.github.io/) to remote hosts via a destination picker.

Inspired by [GianniBYoung/rsync.yazi](https://github.com/GianniBYoung/rsync.yazi), with:

- `ya.which` picker for preset tailnet/SSH destinations
- optional custom destination input
- remembers last used target
- fixes Yazi `file://` URLs being passed to rsync as remote paths

## Install

```sh
ya pkg add j4y-w4lk3r/rsync-tail
```

Or copy this repo into `~/.config/yazi/plugins/rsync-tail.yazi/`.

## Configure

Add targets in `~/.config/yazi/init.lua`:

```lua
require("rsync-tail"):setup({
  remember = true,
  targets = {
    { on = "1", desc = "workstation → Downloads", dest = "host:/home/user/Downloads/" },
    { on = "2", desc = "nas → Downloads", dest = "nas:/home/user/Downloads/" },
    { on = "c", desc = "Custom destination…", dest = false },
  },
})
```

Bind in `~/.config/yazi/keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = [ "R" ]
run  = "plugin rsync-tail"
desc = "Rsync to remote host"
```

## Usage

1. Select files in Yazi (or hover one file)
2. Press `R`
3. Pick a destination or enter a custom `host:/path`

## Requires

- `rsync`
- passwordless SSH to remote hosts

For Tailscale MagicDNS, ensure hostnames resolve (e.g. `tailscale set --accept-dns=true` and/or `~/.ssh/config` entries pointing at `*.tail.d0j0.dev` names).

## License

MIT
