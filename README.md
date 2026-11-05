# hyprglance

A Mac-style window switcher for Hyprland, built on Quickshell.

Hold `Super`, tap `Tab` to walk through your windows with live previews, release `Super` to switch. Click a preview to jump straight to it, even while `Super` is held.

## Requirements

- Hyprland 0.56 or newer with a Lua config (`hyprland.lua`)
- Quickshell 0.3 or newer

The classic `hyprland.conf` is not supported yet: hyprglance relies on the Lua key event API to detect when `Super` is released.

## Install

### Nix

Add the flake and enable the Home Manager module:

```nix
{
  inputs.hyprglance.url = "github:Sn4pe/hyprglance";

  # in your Home Manager configuration
  imports = [ inputs.hyprglance.homeManagerModules.default ];

  programs.hyprglance = {
    enable = true;
    settings.scope = "all";
  };
}
```

This installs hyprglance and starts it as a systemd user service. Then load the keybindings from your Hyprland Lua config. The module path is exposed as `config.programs.hyprglance.luaModule`:

```nix
''
  dofile("${config.programs.hyprglance.luaModule}").setup()
''
```

### Manual

Install Quickshell, clone this repository and start it with your session:

```lua
hl.on("hyprland.start", function()
  hl.dispatch(hl.dsp.exec_cmd("qs -p ~/src/hyprglance"))
end)
dofile(os.getenv("HOME") .. "/src/hyprglance/hyprglance.lua").setup()
```

## Usage

- `Super + Tab` / `Super + Shift + Tab`: open, then move forward or back
- Release `Super`: switch to the selected window
- Click: switch to that window
- `Escape`: close without switching

`setup()` takes the modifier, the key and a safety timeout after which an open switcher closes itself:

```lua
dofile(path).setup({ mod = "ALT", key = "Tab", timeout = 30000 })
```

## Configuration

hyprglance reads `~/.config/hyprglance/config.json` and applies changes as soon as the file is saved. Every key is optional; these are the defaults:

```json
{
  "scope": "output",
  "order": "recent",
  "includeCurrent": true,
  "thumbnailWidth": 240,
  "showTitles": true,
  "fontFamily": "",
  "fontSize": 13,
  "radius": 16,
  "showDelay": 50,
  "theme": "~/.config/stylix/palette.json"
}
```

`scope` picks which windows appear: `output` for the focused monitor, `workspace` for the focused workspace, or `all`. `order` is `recent` for most recently used first, or `workspace` to keep them grouped by workspace number. An empty `fontFamily` uses the system sans-serif. `showDelay` is how long, in milliseconds, `Super` has to stay held before the strip appears, so a quick tap switches without flashing it. Set it to `0` to show it at once.

`theme` points to any base16 scheme in JSON, such as the `palette.json` that Stylix writes. Without one, hyprglance uses Catppuccin Mocha.

## Roadmap

- A settings window
- An overview of every workspace, in the spirit of Mission Control
- Support for `hyprland.conf`

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
