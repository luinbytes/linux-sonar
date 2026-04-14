#!/usr/bin/env python3
"""Single-channel Sonar waybar widget. Usage: sonar-channel.py <ChannelName>"""
import json, re, subprocess, sys

CHANNEL_META = {
    "Game":      ("G", "#4a9eff"),
    "Chat":      ("C", "#a855f7"),
    "Media":     ("M", "#22c55e"),
    "AUX":       ("A", "#f59e0b"),
    "VoiceChat": ("V", "#ef4444"),
}

name = sys.argv[1] if len(sys.argv) > 1 else "Game"
letter, color = CHANNEL_META.get(name, ("?", "#888"))
sink = f"Sonar_{name}"


def get_sink_state(target: str) -> tuple[int | None, bool]:
    """Single `pactl list sinks` call → (volume_pct, muted) for `target`."""
    try:
        out = subprocess.run(
            ["pactl", "list", "sinks"],
            capture_output=True, text=True, timeout=3
        ).stdout
    except Exception:
        return None, False

    vol: int | None = None
    muted = False
    in_target = False
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("Name:"):
            in_target = s.split(None, 1)[1] == target
            continue
        if not in_target:
            continue
        if vol is None and s.startswith("Volume:"):
            m = re.search(r'(\d+)%', s)
            if m:
                vol = int(m.group(1))
        elif s.startswith("Mute:"):
            muted = "yes" in s
            if vol is not None:
                break
    return vol, muted


vol, muted = get_sink_state(sink)

if vol is None:
    print(json.dumps({"text": "", "class": "inactive"}))
    sys.exit(0)

alpha = "55%" if muted else "100%"

print(json.dumps({
    "text": f"<span color='{color}' alpha='{alpha}'>{letter}·{vol:3d}</span>",
    "tooltip": f"{name}: {'muted' if muted else f'{vol}%'}",
    "class": "muted" if muted else "active",
}))
