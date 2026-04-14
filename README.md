# linux-sonar

SteelSeries Sonar for Linux. Per-app audio routing, ChatMix balance, and mic effects on PipeWire + WirePlumber with a GTK4/libadwaita GUI.

Built for the Arctis Nova 7 on Arch. Works with any PipeWire stereo output sink, just point the virtual channels at your `alsa_output.*` node.

By [@luinbytes](https://github.com/luinbytes) · [Portfolio](https://luinbytes.github.io)

## Features

Five virtual channels (Game, Chat, Media, AUX, VoiceChat) each appear as a regular audio sink. Route apps to any channel via the GUI or `routing.json`. Volumes persist across reboots through WirePlumber state files.

ChatMix slider maps to Game/Chat balance. Supports the Arctis Nova 7 hardware ChatMix wheel over USB-HID (~50 ms polling). The on-screen slider works with any headset.

Mic effects chain: RNNoise (LADSPA) > Gate > 8-band EQ > Compressor > Limiter. Runs as its own PipeWire filter-chain subprocess. Parameter changes debounce for 600 ms, then fade out, restart, fade back in. No clicks on the other end. Optional live auto-tune watches mic levels during silence and nudges gate threshold, compressor makeup, and RNNoise strength toward sane defaults.

Waybar integration included. Single-file Python app, ~3500 lines, no build step.

## Architecture

```
                          ┌──────────────────────────────────┐
                          │       ~/.config/pipewire/        │
                          │       10-sonar-sinks.conf        │
                          │                                  │
  app A  ──┐              │  5 × filter-chain virtual sinks  │
  app B  ──┤              │  (Game / Chat / Media / AUX /    │
  app C  ──┼──► Sonar_X ──┤   VoiceChat). Each is a passthru │──►  headset
  app D  ──┤              │  that pins to the headset via    │     (ALSA node)
  app E  ──┘              │  target.object                   │
                          └──────────────────────────────────┘

    ▲  pactl move-sink-input   ▲  wpctl set-volume / set-mute
    │                          │
    └──────────── sonar-mixer ─┘
                 (GUI + --daemon)
                       │
                       ├─► reads routing.json, enforces per-app routing
                       ├─► reads ChatMix HID wheel, applies to Game/Chat
                       ├─► writes mic-filter-chain.conf from mic-effects.json
                       └─► restarts sonar-mic-filterchain.service on change
```

Virtual sinks are five `libpipewire-module-filter-chain` blocks in `config/pipewire/10-sonar-sinks.conf`. Each passes through to the headset via `target.object`.

Per-app routing runs in `sonar-mixer --daemon`. Polls `wpctl status` + `pactl list sink-inputs` every ~1.5 s and moves streams whose preferred channel doesn't match their current sink. WirePlumber persists the move after the first route.

Mic path: raw mic feeds `sonar-mic-filterchain.service`, an isolated PipeWire subprocess running a filter-chain config generated from `mic-effects.json`. The chain is RNNoise > Calf Gate > Calf Equalizer8Band > Calf Compressor > Calf Limiter. Any subset of stages can be enabled.

## Dependencies

Arch packages (translate for your distro):

- `pipewire`, `pipewire-pulse`, `wireplumber`
- `python`, `python-gobject`, `gtk4`, `libadwaita`
- `calf` (gate, EQ, compressor, limiter)
- `rnnoise-ladspa` ([librnnoise_ladspa.so](https://github.com/werman/noise-suppression-for-voice))
- `libpulse` (for `pactl` and `parec`)
- `python-hid` (optional, ChatMix wheel only)
- `waybar` (optional, status bar integration)

## Install

```sh
git clone https://github.com/luinbytes/linux-sonar.git
cd linux-sonar
./install.sh
```

The installer copies `bin/sonar-mixer` to `~/.local/bin/`, drops PipeWire and WirePlumber configs, installs systemd user units, copies waybar scripts if `~/.config/waybar/` exists, restarts pipewire, generates the mic filter-chain config, and enables the daemon + mic services.

After install, run `sonar-mixer` to open the GUI.

Make sure `~/.local/bin` is in your `PATH`.

## Usage

**GUI**: `sonar-mixer`. Five channel strips with volume and mute, a ChatMix slider, a collapsible mic effects panel, and a live per-app routing panel at the bottom.

**CLI**:

| Flag                       | What it does |
| -------------------------- | ------------ |
| `sonar-mixer`              | Launch the GUI |
| `sonar-mixer --daemon`     | Headless routing + ChatMix + auto-tune daemon |
| `sonar-mixer --write-mic-config` | Regenerate mic filter-chain config from mic-effects.json |
| `sonar-mixer --set-mic-input <key>` | Switch raw mic input source |

**Config files** (`~/.config/sonar-mixer/`):

| File                     | Written by | Purpose |
| ------------------------ | ---------- | ------- |
| `routing.json`           | GUI        | Per-app channel map |
| `mic-effects.json`       | GUI        | Mic effect parameters + live-tune state |
| `mic-filter-chain.conf`  | `--write-mic-config` | Generated PipeWire filter-chain config |
| `chatmix-base.json`      | GUI        | Game/Chat volume snapshot for ChatMix baseline |

See `examples/routing.example.json` for the routing format.

**Waybar**:

```jsonc
"custom/sonar": {
    "exec": "~/.config/waybar/scripts/sonar.py",
    "interval": 2,
    "return-type": "json",
    "on-click": "sonar-mixer"
}
```

`sonar.py` shows all five channels. `sonar-channel.py <ChannelName>` shows one. Useful for splitting Game+Chat and Media+AUX across your bar.

## Adapting to other hardware

Three places reference the Arctis Nova 7. To use a different headset or DAC:

**1. ALSA output node.** Find yours with `pactl list sinks short | grep alsa_output`. Open `~/.config/pipewire/pipewire.conf.d/10-sonar-sinks.conf` and replace all five occurrences of `alsa_output.usb-SteelSeries_Arctis_Nova_7-00.analog-stereo` with your node. Restart with `systemctl --user restart pipewire`.

**2. Suspend-timeout rule.** Open `~/.config/wireplumber/wireplumber.conf.d/50-sonar-routing.conf` and replace the `node.name` match. Delete the rule entirely if suspend-pops aren't a problem.

**3. ChatMix wheel.** If your headset has no ChatMix HID, the daemon logs an error and continues fine. Use the on-screen slider instead. To add support for a different HID protocol, patch `_chatmix_daemon_thread` in `bin/sonar-mixer`. Patches welcome.

**Mic input** auto-discovers via `_MIC_INPUT_TARGETS` at the top of `bin/sonar-mixer`. Add your ALSA source name there.

## Troubleshooting

**Sinks don't appear.** Check `systemctl --user status pipewire` and `pactl list sinks short | grep Sonar`. Syntax errors in the config kill the sink silently. Check `journalctl --user -u pipewire`. A typo in `target.object` prevents the sink from loading.

**Per-app routing doesn't stick.** Ensure `systemctl --user status sonar-daemon` is active. WirePlumber must be allowed to persist stream properties. Check that `~/.local/state/wireplumber/stream-properties` exists and updates on route changes.

**Mic effects click on parameter change.** The subprocess is crashing on restart. Check `journalctl --user -u sonar-mic-filterchain` for a SIGSEGV. Usually a Calf plugin compatibility issue with your PipeWire version.

**EasyEffects breaks routing.** Its output pipeline intercepts every stream globally and bypasses per-channel routing. Disable the EasyEffects output pipeline. Its input pipeline is fine, though redundant with the RNNoise chain here.

## License

GPL-3.0.
