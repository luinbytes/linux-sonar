# linux-sonar

A Linux equivalent of [SteelSeries Sonar](https://steelseries.com/gg/sonar) —
per-app audio routing, ChatMix balance, and a studio-style mic effects
chain — built on top of PipeWire and WirePlumber, with a GTK4/libadwaita GUI.

Originally written for a **SteelSeries Arctis Nova 7** headset on Arch
Linux (Hyprland), but the architecture is vendor-neutral: any PipeWire
setup with a stereo output sink works — you just point the virtual channels
at whatever `alsa_output.*` node you have.

## What it does

- **Five virtual channels** (Game / Chat / Media / AUX / VoiceChat) that
  each appear to apps as a regular audio sink. Per-channel volume + mute.
- **Per-app routing** — drag an app to any channel in the GUI, or edit
  `routing.json` directly. Routing preferences persist across reboots via
  WirePlumber's state file.
- **ChatMix** — a Game/Chat balance slider plus live hardware ChatMix wheel
  support (on headsets that expose one over HID, like the Arctis Nova 7).
- **Mic effects chain** — RNNoise (LADSPA) → Gate → 8-band EQ → Compressor
  → Limiter, running as its own PipeWire filter-chain subprocess. Live
  parameter updates are debounced and reloaded silently (fade out → restart
  → fade back in) so the other side of a call hears no click.
- **Live auto-tune** — a silent background worker that watches the mic
  during silence and nudges gate threshold / compressor makeup / RNNoise
  strength toward good baseline values. Completely optional, off by
  default.
- **Waybar integration** — two small JSON-output scripts: one showing all
  five channels at once, one showing a single channel.
- **Single-file Python app** — ~3500 lines, GTK4 + libadwaita, no build
  step. Easy to audit and patch.

## How it works

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

- **Virtual sinks** are 5 `libpipewire-module-filter-chain` blocks in
  `config/pipewire/10-sonar-sinks.conf`. Each is a passthrough filter
  whose `playback.props.target.object` is pinned to the Arctis output
  node, so anything routed into `Sonar_Game` ends up on the headset.
- **Per-app routing** is enforced in userspace by the `sonar-mixer
  --daemon` process, which polls `wpctl status` + `pactl list sink-inputs`
  every ~1.5 s and runs `pactl move-sink-input` on any stream whose
  preferred channel (from `routing.json`) doesn't match its current sink.
  WirePlumber's state file persists the move, so after the first route,
  subsequent app starts land on the correct sink without the daemon
  having to do anything.
- **Mic path**: the headset's raw mic feeds a separate
  `sonar-mic-filterchain.service` — an isolated `pipewire` subprocess
  running a filter-chain config generated from `mic-effects.json`. The
  chain is RNNoise (LADSPA) → Calf Gate → Calf Equalizer8Band → Calf
  Compressor → Calf Limiter, with any subset of stages enabled. The GUI
  debounces slider changes (~600 ms) and does a silent restart of this
  service: fade `Sonar_Mic` volume to 0, restart the subprocess, mute
  the new node as soon as it appears, 80 ms settle, fade back up.
- **ChatMix HID** (optional): reads the Arctis Nova 7's ChatMix wheel
  over USB-HID and mixes it into the Game/Chat channel volumes at
  ~50 ms intervals.

## Hardware

Everything in this repo is **hardcoded for the SteelSeries Arctis Nova 7**:

- `config/pipewire/10-sonar-sinks.conf` pins every channel to
  `alsa_output.usb-SteelSeries_Arctis_Nova_7-00.analog-stereo`.
- `config/wireplumber/50-sonar-routing.conf` disables suspend timeout on
  the same node.
- `sonar-mixer` knows how to talk to the Arctis Nova 7 ChatMix wheel
  over HID (vendor-specific).

To adapt to a different headset, see
[Adapting to other hardware](#adapting-to-other-hardware) below.

## Dependencies

All Arch packages (translate as needed for your distro):

- `pipewire`, `pipewire-pulse`, `wireplumber` — the audio stack
- `python`, `python-gobject`, `gtk4`, `libadwaita` — the GUI
- `calf` — the LV2 plugin bundle (gate, EQ, compressor, limiter)
- `rnnoise-ladspa` or equivalent — [librnnoise_ladspa.so](https://github.com/werman/noise-suppression-for-voice)
- `libpulse` — for `pactl` and `parec`
- `python-hid` — **optional**, only for ChatMix wheel support
- `waybar` — **optional**, for the status bar integration

## Install

```sh
git clone https://github.com/luinbytes/linux-sonar.git
cd linux-sonar
./install.sh
```

The installer:

1. Copies `bin/sonar-mixer` → `~/.local/bin/sonar-mixer`
2. Copies PipeWire / WirePlumber configs to `~/.config/pipewire/pipewire.conf.d/`
   and `~/.config/wireplumber/wireplumber.conf.d/`
3. Copies systemd user units to `~/.config/systemd/user/`
4. Copies waybar scripts (if `~/.config/waybar/` exists)
5. Restarts `pipewire` + `wireplumber` so the new sinks appear
6. Runs `sonar-mixer --write-mic-config` to generate the mic filter-chain config
7. Enables and starts `sonar-daemon.service` and `sonar-mic-filterchain.service`

After install, run `sonar-mixer` to open the GUI.

Make sure `~/.local/bin` is in your `PATH` (most shells already do this).

## Usage

**GUI**: `sonar-mixer`. You'll see five channel strips (volume + mute),
a ChatMix slider, a mic effects panel (collapsed by default — click the
header to expand), and a live per-app routing panel at the bottom.

**CLI**:

| Flag                       | What it does |
| -------------------------- | ------------ |
| `sonar-mixer`              | Launch the GUI |
| `sonar-mixer --daemon`     | Run the headless routing + ChatMix + live-auto-tune daemon (used by systemd) |
| `sonar-mixer --write-mic-config` | Regenerate `~/.config/sonar-mixer/mic-filter-chain.conf` from `mic-effects.json` |
| `sonar-mixer --set-mic-input <key>` | Switch which raw mic is fed into the filter chain |

**Config files** (all under `~/.config/sonar-mixer/`):

| File                     | Written by | Purpose |
| ------------------------ | ---------- | ------- |
| `routing.json`           | GUI        | Per-app preferred channel map |
| `mic-effects.json`       | GUI        | Mic effect parameters + live-tune state |
| `mic-filter-chain.conf`  | `--write-mic-config` | Generated PipeWire filter-chain config |
| `chatmix-base.json`      | GUI        | Game/Chat volume snapshot used as the ChatMix baseline |

See `examples/routing.example.json` for the routing format.

**Waybar**: the recommended module, once scripts are installed:

```jsonc
"custom/sonar": {
    "exec": "~/.config/waybar/scripts/sonar.py",
    "interval": 2,
    "return-type": "json",
    "on-click": "sonar-mixer"
}
```

`waybar/sonar.py` shows all five channels at once.
`waybar/sonar-channel.py <ChannelName>` shows a single channel — useful
for putting Game+Chat on one side of your bar and Media+AUX on the other.

## Adapting to other hardware

Three places hardcode the Arctis Nova 7. To point this at a different
headset/DAC/speakers:

**1. The ALSA output node**. Find yours:

```sh
pactl list sinks short | grep alsa_output
# e.g.  alsa_output.pci-0000_00_1f.3.analog-stereo
```

Open `~/.config/pipewire/pipewire.conf.d/10-sonar-sinks.conf` and replace
all five occurrences of
`alsa_output.usb-SteelSeries_Arctis_Nova_7-00.analog-stereo` with your node
name. Then:

```sh
systemctl --user restart pipewire
```

**2. The suspend-timeout rule**. Open
`~/.config/wireplumber/wireplumber.conf.d/50-sonar-routing.conf` and
replace the `node.name` match with your ALSA node. (Or delete the rule
entirely if suspend-pops aren't a problem for your hardware.)

**3. The ChatMix wheel** (optional). If your headset doesn't expose a
ChatMix wheel over USB-HID, the daemon will log `ChatMix error: unable
to open device, retrying…` and otherwise work fine — you can still use
the on-screen ChatMix slider. If your headset has a *different* HID
protocol you want to support, the code lives in
`_chatmix_daemon_thread` in `bin/sonar-mixer`; patches welcome.

**Mic input** is auto-discovered via `_MIC_INPUT_TARGETS` at the top of
`bin/sonar-mixer` — add your device's ALSA source name to that dict.

## Troubleshooting

**The Sonar sinks don't appear.** Check
`systemctl --user status pipewire` and run
`pactl list sinks short | grep Sonar`. If the 10-sonar-sinks.conf file
is syntactically wrong, PipeWire logs the error — `journalctl --user
-u pipewire`. Any typo in `target.object` prevents the sink from
materializing.

**Per-app routing doesn't stick.** The daemon needs to be running:
`systemctl --user status sonar-daemon`. WirePlumber also needs to be
allowed to persist stream properties (its default) — check
`~/.local/state/wireplumber/stream-properties` exists and is being
updated.

**Mic effects click on every parameter change.** The debounce window
is 600 ms and the fade is ~60 ms out / 80 ms in — if you're hearing a
click, the subprocess is crashing on restart. Check
`journalctl --user -u sonar-mic-filterchain` for a SIGSEGV. This is
usually a plugin compatibility issue (old Calf vs current PipeWire).

**`EasyEffects` breaks routing.** EasyEffects' output pipeline
intercepts every stream globally and bypasses per-channel routing. If
you use EasyEffects, disable its *output* pipeline (the input pipeline
is fine, though redundant with the RNNoise in this project).

## License

GPL-3.0. See [LICENSE](LICENSE).

## Acknowledgements

- SteelSeries Sonar for the UX inspiration.
- The PipeWire and WirePlumber teams for making this kind of thing
  possible without kernel modules.
- [noise-suppression-for-voice](https://github.com/werman/noise-suppression-for-voice)
  for the RNNoise LADSPA plugin.
- [Calf Studio Gear](https://calf-studio-gear.org/) for the Gate / EQ /
  Compressor / Limiter LV2 plugins.
