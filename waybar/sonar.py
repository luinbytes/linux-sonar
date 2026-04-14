#!/usr/bin/env python3
"""Sonar waybar widget — single pactl call, fixed-width output."""
import json, re, subprocess, sys

CHANNELS = [
    ("Game",      "G", "#4a9eff"),
    ("Chat",      "C", "#a855f7"),
    ("Media",     "M", "#22c55e"),
    ("AUX",       "A", "#f59e0b"),
    ("VoiceChat", "V", "#ef4444"),
]
SONAR_SINKS = {f"Sonar_{n}" for n, *_ in CHANNELS}


def get_sink_info() -> dict:
    """Single pactl call → {sink_name: {vol: int, muted: bool}}"""
    try:
        out = subprocess.run(
            ["pactl", "list", "sinks"],
            capture_output=True, text=True, timeout=3
        ).stdout
    except Exception:
        return {}

    info: dict = {}
    current: str | None = None
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("Name:"):
            current = s.split(None, 1)[1]
            continue
        if current not in SONAR_SINKS:
            continue
        entry = info.setdefault(current, {})
        if "vol" not in entry and s.startswith("Volume:"):
            m = re.search(r'(\d+)%', s)
            if m:
                entry["vol"] = int(m.group(1))
        elif s.startswith("Mute:"):
            entry["muted"] = "yes" in s
    return info


sinks = get_sink_info()
if not sinks:
    print(json.dumps({"text": "", "class": "inactive"}))
    sys.exit(0)

parts = []
tooltip_lines = []
for name, letter, color in CHANNELS:
    d = sinks.get(f"Sonar_{name}")
    if d is None:
        continue
    vol = d.get("vol", 0)
    muted = d.get("muted", False)
    alpha = "55%" if muted else "100%"
    # {vol:3d} → always 3 chars wide in monospace → no layout jitter
    parts.append(
        f"<span color='{color}' alpha='{alpha}'>{letter}·{vol:3d}</span>"
    )
    status = "muted" if muted else f"{vol}%"
    tooltip_lines.append(f"{name:<10} {status:>6}")

print(json.dumps({
    "text": "  ".join(parts),
    "tooltip": "\n".join(tooltip_lines),
    "class": "active",
}))
