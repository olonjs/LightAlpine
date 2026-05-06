#!/usr/bin/env python3
"""Extract Lighthouse JSON from HTML report (handles huge single-line embed)."""
import json
import sys
from pathlib import Path

def main() -> None:
    report = Path(sys.argv[1] if len(sys.argv) > 1 else "/home/dev/olon.it_2026-05-03_22-40-10.report.html")
    out = Path(sys.argv[2] if len(sys.argv) > 2 else str(report.parent / "lh-summary.txt"))
    text = report.read_text(encoding="utf-8", errors="replace")
    key = "window.__LIGHTHOUSE_JSON__ = "
    i = text.find(key)
    if i < 0:
        raise SystemExit(f"missing {key!r} in {report}")
    start = text.find("{", i)
    if start < 0:
        raise SystemExit("missing opening brace")
    decoder = json.JSONDecoder()
    # raw_decode sul buffer intero: non usare indexOf("</script>") (fragile con stringhe enormi).
    data, _end = decoder.raw_decode(text, start)

    perf = data.get("categories", {}).get("performance", {}).get("score")
    lines: list[str] = []
    lines.append(f"URL: {data.get('requestedUrl')}")
    lines.append(f"Lighthouse: {data.get('lighthouseVersion')}")
    lines.append(f"Performance score: {int(round(perf * 100)) if isinstance(perf, (int, float)) else 'n/a'}")

    core = [
        "first-contentful-paint",
        "largest-contentful-paint",
        "total-blocking-time",
        "cumulative-layout-shift",
        "speed-index",
        "interactive",
    ]
    lines.append("")
    lines.append("--- Core ---")
    audits = data.get("audits") or {}
    for aid in core:
        a = audits.get(aid) or {}
        dv = a.get("displayValue")
        nv = a.get("numericValue")
        sc = a.get("score")
        lines.append(f"{aid}: {dv or nv} | score {sc}")

    skip = set(core) | {
        "max-potential-fid",
        "metrics",
        "screenshot-thumbnails",
        "final-screenshot",
        "diagnostics",
        "network-requests",
        "network-rtt",
        "network-server-latency",
        "mainthread-work-breakdown",
        "bootup-time",
        "script-treemap-data",
        "resource-summary",
        "screenshots",
        "full-page-screenshot",
    }

    rows: list[tuple[float, float, str, str, float]] = []
    for aid, a in audits.items():
        if aid in skip:
            continue
        sc = a.get("score")
        if sc is None or sc >= 1:
            continue
        det = a.get("details") or {}
        ms = float(det.get("overallSavingsMs") or 0)
        b = float(det.get("overallSavingsBytes") or 0)
        if ms < 1 and b < 5000:
            continue
        rows.append((ms, b, aid, a.get("title") or aid, sc))

    rows.sort(reverse=True)
    lines.append("")
    lines.append("--- Opportunities (top) ---")
    for ms, b, aid, title, sc in rows[:18]:
        lines.append(
            f"[{aid}] {title} | ~{int(ms)}ms | ~{int(b / 1024)} KiB | score {sc:.3f}"
        )

    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(out.read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
