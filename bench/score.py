#!/usr/bin/env python3
"""Speakorb 中文 bench 评分（骨架）。

用法:
    python3 bench/score.py bench/manifest.jsonl predictions.jsonl

predictions.jsonl 每行: {"id": "...", "text": "...", "latency_ms": 1234, "provider": "local"}
输出: 可用率、信息保真、术语召回、延迟分位；JSON 汇总到 stdout。
"""
import json
import sys
import difflib
from pathlib import Path


def normalize(text: str) -> str:
    out = []
    for ch in text:
        if ch in "，。！？、；：,.!?;:\n\r\t ":
            continue
        out.append(ch)
    return "".join(out)


def similarity(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, normalize(a), normalize(b)).ratio()


def load_jsonl(path: Path):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows


def percentile(values, p):
    if not values:
        return None
    values = sorted(values)
    idx = min(len(values) - 1, max(0, int(round((p / 100) * (len(values) - 1)))))
    return values[idx]


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    manifest = load_jsonl(Path(sys.argv[1]))
    preds = {row["id"]: row for row in load_jsonl(Path(sys.argv[2]))}
    usable = []
    fidelity = []
    latencies = []
    term_hits = 0
    term_total = 0

    for row in manifest:
        pid = row["id"]
        pred = preds.get(pid)
        if not pred or not pred.get("text"):
            usable.append(0)
            continue
        text = pred["text"]
        sim = similarity(text, row["ideal"])
        usable.append(1 if sim >= 0.85 else 0)
        fidelity.append(similarity(text, row["verbatim"]))
        if row.get("latency_ms"):
            latencies.append(row["latency_ms"])
        elif pred.get("latency_ms"):
            latencies.append(pred["latency_ms"])
        for term in row.get("terms", []):
            term_total += 1
            if term in text:
                term_hits += 1

    summary = {
        "items": len(manifest),
        "usable_rate": round(sum(usable) / len(usable), 4) if usable else None,
        "fidelity_avg": round(sum(fidelity) / len(fidelity), 4) if fidelity else None,
        "term_recall": round(term_hits / term_total, 4) if term_total else None,
        "latency_p50_ms": percentile(latencies, 50),
        "latency_p90_ms": percentile(latencies, 90),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
