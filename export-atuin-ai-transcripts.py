#!/usr/bin/env python3
"""Export Atuin AI chat sessions to Markdown, one file per session.

Reads ~/.local/share/atuin/ai_sessions.db (or a path you pass as $1)
and writes one .md per session into an output dir (default:
./atuin-ai-transcripts).

Usage:
  python3 export-atuin-ai-transcripts.py [DB_PATH] [OUT_DIR]
"""
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timezone

DB = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/.local/share/atuin/ai_sessions.db")
OUT = sys.argv[2] if len(sys.argv) > 2 else "atuin-ai-transcripts"


def ts(sec: int) -> str:
    return datetime.fromtimestamp(sec, tz=timezone.utc).strftime(
        "%Y-%m-%d %H:%M:%S UTC")


def slug(s: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]", "_", s) or "root"


def tool_line(data: dict) -> list:
    name = data.get("name", "?")
    raw = json.dumps(data.get("input", {}), ensure_ascii=False)
    if len(raw) > 200:
        raw = raw[:200] + "…"
    return [f"> **tool** `{name}` {raw}", ""]


def result_line(data: dict) -> list:
    content = data.get("content", "").rstrip()
    if len(content) > 2000:
        content = content[:2000] + "\n… [truncated]"
    out = ["> **result**", ""]
    if content:
        out += [f"> {line}" if line else ">" for line in content.splitlines()]
    out.append("")
    return out


def export(db_path: str, out_dir: str) -> int:
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    os.makedirs(out_dir, exist_ok=True)

    sessions = db.execute(
        "SELECT id, directory, git_root, created_at, updated_at, archived_at "
        "FROM sessions ORDER BY created_at"
    ).fetchall()
    written = 0
    for sid, cwd, git_root, created, updated, archived in sessions:
        events = db.execute(
            "SELECT event_type, event_data, created_at FROM session_events "
            "WHERE session_id = ? ORDER BY created_at, rowid", (sid,)
        ).fetchall()

        date = ts(created)[:10]
        timepart = ts(created)[11:16]
        fname = f"{date}_{timepart}_{slug(os.path.basename(cwd or ''))}_{sid[:8]}.md"
        path = os.path.join(out_dir, fname)

        lines = [
            f"# Atuin AI session `{sid}`",
            "",
            f"- **cwd:** `{cwd or '?'}`",
        ]
        if git_root:
            lines.append(f"- **git root:** `{git_root}`")
        lines += [
            f"- **started:** {ts(created)}",
            f"- **last activity:** {ts(updated)}",
        ]
        if archived:
            lines.append(f"- **archived:** {ts(archived)}")
        lines.append("")

        for etype, data_raw, _ in events:
            try:
                data = json.loads(data_raw)
            except json.JSONDecodeError:
                data = {"content": data_raw}
            content = data.get("content", "")
            if etype == "user_message":
                lines += [f"## You\n\n{content}\n"]
            elif etype == "text":
                lines += [f"## Assistant\n\n{content}\n"]
            elif etype == "tool_call":
                lines += tool_line(data)
            elif etype == "tool_result":
                lines += result_line(data)
            elif etype == "out_of_band_output":
                if data.get("command"):
                    lines.append(f"> `{' '.join(data['command'].split())}`")
                lines += ["> " + l if l else ">" for l in content.splitlines()]
                lines.append("")
            elif etype == "system_context":
                lines += [f"*{content.strip()}*\n"]
            # other event types: skipped

        with open(path, "w") as f:
            f.write("\n".join(lines))
        written += 1
        print(f"wrote {path} ({len(events)} events)")

    print(f"\n{written} session(s) -> {os.path.abspath(out_dir)}")
    return written


if __name__ == "__main__":
    if not os.path.exists(DB):
        sys.exit(f"no such DB: {DB}")
    export(DB, OUT)
