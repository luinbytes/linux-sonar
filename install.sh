#!/usr/bin/env bash
# linux-sonar installer — copies the project files into your user config
# directories, reloads PipeWire/WirePlumber, and enables the systemd services.
#
# Safe to re-run: every step is idempotent.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

# ── 1. Main binary ──────────────────────────────────────────────────────
say "Installing sonar-mixer to ~/.local/bin/"
mkdir -p "$HOME/.local/bin"
install -m 755 "$REPO_DIR/bin/sonar-mixer" "$HOME/.local/bin/sonar-mixer"

# ── 2. PipeWire virtual sinks ───────────────────────────────────────────
say "Installing PipeWire virtual sink config"
mkdir -p "$HOME/.config/pipewire/pipewire.conf.d"
install -m 644 "$REPO_DIR/config/pipewire/10-sonar-sinks.conf" \
    "$HOME/.config/pipewire/pipewire.conf.d/10-sonar-sinks.conf"

# These creation-time targets must be set by Pulse before WirePlumber links them.
say "Installing PipeWire-Pulse stream routing config"
mkdir -p "$HOME/.config/pipewire/pipewire-pulse.conf.d"
install -m 644 "$REPO_DIR/config/pipewire/60-sonar-stream-routing.conf" \
    "$HOME/.config/pipewire/pipewire-pulse.conf.d/60-sonar-routing.conf"

# ── 3. WirePlumber default routing ──────────────────────────────────────
say "Installing WirePlumber routing config"
mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
install -m 644 "$REPO_DIR/config/wireplumber/50-sonar-routing.conf" \
    "$HOME/.config/wireplumber/wireplumber.conf.d/50-sonar-routing.conf"

# ── 4. systemd user units ───────────────────────────────────────────────
say "Installing systemd user services"
mkdir -p "$HOME/.config/systemd/user"
install -m 644 "$REPO_DIR/systemd/sonar-daemon.service" \
    "$HOME/.config/systemd/user/sonar-daemon.service"
install -m 644 "$REPO_DIR/systemd/sonar-mic-filterchain.service" \
    "$HOME/.config/systemd/user/sonar-mic-filterchain.service"

# ── 5. Waybar scripts (optional) ────────────────────────────────────────
if [[ -d "$HOME/.config/waybar" ]]; then
    say "Installing waybar scripts"
    mkdir -p "$HOME/.config/waybar/scripts"
    install -m 755 "$REPO_DIR/waybar/sonar.py"         "$HOME/.config/waybar/scripts/sonar.py"
    install -m 755 "$REPO_DIR/waybar/sonar-channel.py" "$HOME/.config/waybar/scripts/sonar-channel.py"
else
    warn "Waybar not detected — skipping waybar scripts. Copy them manually from waybar/ if you use a different bar."
fi

# ── 6. Reload PipeWire stack to pick up the new sinks/routing ───────────
say "Restarting PipeWire stack (this briefly cuts audio)"
systemctl --user restart wireplumber.service pipewire.service pipewire-pulse.service

# Give PipeWire a moment to spin the new filter-chain sinks
sleep 1

# ── 7. Generate initial mic filter-chain config ─────────────────────────
say "Generating initial mic filter-chain config"
"$HOME/.local/bin/sonar-mixer" --write-mic-config

# ── 8. Enable and start services ────────────────────────────────────────
say "Enabling systemd services"
systemctl --user daemon-reload
systemctl --user enable --now sonar-daemon.service
systemctl --user enable --now sonar-mic-filterchain.service

say "Done."
cat <<EOF

  Next steps:
    • Run 'sonar-mixer' to open the GUI.
    • If you're NOT using a SteelSeries Arctis Nova 7, edit:
        ~/.config/pipewire/pipewire.conf.d/10-sonar-sinks.conf
      and replace the 'target.object' lines with your own ALSA output node
      (find it with: pactl list sinks short | grep alsa_output).
      Then: systemctl --user restart pipewire
    • Waybar module (if you want channel volumes in your bar):
        "custom/sonar": {
            "exec": "~/.config/waybar/scripts/sonar.py",
            "interval": 2,
            "return-type": "json",
            "on-click": "sonar-mixer"
        }

EOF
