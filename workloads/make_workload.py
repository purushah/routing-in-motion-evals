#!/usr/bin/env python3
"""Build the routing-eval workload: 500 GSM8K + 350 MMLU-STEM + 150 HumanEval, shuffled (seed 42).

Outputs (committed for reproducibility):
  requests.jsonl  {"id", "conversation_id", "slice", "prompt"}
  answers.jsonl   {"id", "slice", ...grading fields per slice}
  smoke.jsonl     first 12 requests (2 per slice-ish) for cheap smoke runs

Grading fields: gsm8k -> {"answer": "42"}; mmlu -> {"answer": "B"};
humaneval -> {"entry_point", "test"} (unit-test grading in grade.py).
"""
import gzip
import io
import json
import random
import urllib.request
from pathlib import Path

SEED = 42
N_GSM8K, N_MMLU, N_HUMANEVAL = 500, 350, 150
OUT = Path(__file__).parent

GSM8K_URL = "https://raw.githubusercontent.com/openai/grade-school-math/master/grade_school_math/data/test.jsonl"
HUMANEVAL_URL = "https://github.com/openai/human-eval/raw/master/data/HumanEval.jsonl.gz"
MMLU_CONFIGS = ["college_mathematics", "college_physics", "college_computer_science", "high_school_statistics"]
MMLU_API = "https://datasets-server.huggingface.co/rows?dataset=cais%2Fmmlu&config={cfg}&split=test&offset={off}&length=100"


def fetch(url: str, attempts: int = 5) -> bytes:
    import time

    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "routing-eval/0.1"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 — retry any transient network error
            if attempt == attempts - 1:
                raise
            wait = 2**attempt
            print(f"  retry {attempt + 1}/{attempts} for {url[:80]} after {e} (sleep {wait}s)")
            time.sleep(wait)
    raise RuntimeError("unreachable")


def gsm8k(rng: random.Random):
    rows = [json.loads(l) for l in fetch(GSM8K_URL).decode().splitlines() if l.strip()]
    rng.shuffle(rows)
    out = []
    for i, row in enumerate(rows[:N_GSM8K]):
        final = row["answer"].split("####")[-1].strip().replace(",", "")
        out.append(
            (
                {
                    "slice": "gsm8k",
                    "prompt": row["question"].strip()
                    + "\n\nSolve step by step, then give ONLY the final number on the last line as: ANSWER: <number>",
                },
                {"answer": final},
            )
        )
    return out


def mmlu(rng: random.Random):
    rows = []
    per_cfg = N_MMLU // len(MMLU_CONFIGS) + 25
    for cfg in MMLU_CONFIGS:
        got, off = [], 0
        while len(got) < per_cfg and off < 300:
            data = json.loads(fetch(MMLU_API.format(cfg=cfg, off=off)).decode())
            batch = data.get("rows", [])
            if not batch:
                break
            got.extend(r["row"] for r in batch)
            off += 100
        rows.extend(got[:per_cfg])
    rng.shuffle(rows)
    out = []
    for row in rows[:N_MMLU]:
        letters = ["A", "B", "C", "D"]
        choices = "\n".join(f"{letters[i]}. {c}" for i, c in enumerate(row["choices"]))
        prompt = (
            row["question"].strip()
            + "\n\n"
            + choices
            + "\n\nThink briefly, then answer with ONLY the letter on the last line as: ANSWER: <letter>"
        )
        out.append(({"slice": "mmlu", "prompt": prompt}, {"answer": letters[row["answer"]]}))
    return out


def humaneval(rng: random.Random):
    raw = gzip.decompress(fetch(HUMANEVAL_URL)).decode()
    rows = [json.loads(l) for l in raw.splitlines() if l.strip()]
    rng.shuffle(rows)
    out = []
    for row in rows[:N_HUMANEVAL]:
        prompt = (
            "Complete the following Python function. Reply with ONLY the complete function "
            "definition (including the signature shown) inside one ```python code block.\n\n"
            + row["prompt"]
        )
        out.append(
            (
                {"slice": "humaneval", "prompt": prompt},
                {"entry_point": row["entry_point"], "test": row["test"], "he_prompt": row["prompt"]},
            )
        )
    return out


def main():
    rng = random.Random(SEED)
    items = gsm8k(rng) + mmlu(rng) + humaneval(rng)
    rng.shuffle(items)
    requests, answers = [], []
    for i, (req, ans) in enumerate(items):
        rid = f"w{i:04d}"
        requests.append({"id": rid, "conversation_id": rid, "slice": req["slice"], "prompt": req["prompt"]})
        answers.append({"id": rid, "slice": req["slice"], **ans})
    (OUT / "requests.jsonl").write_text("\n".join(json.dumps(r) for r in requests) + "\n")
    (OUT / "answers.jsonl").write_text("\n".join(json.dumps(a) for a in answers) + "\n")
    (OUT / "smoke.jsonl").write_text("\n".join(json.dumps(r) for r in requests[:12]) + "\n")
    by_slice = {}
    for r in requests:
        by_slice[r["slice"]] = by_slice.get(r["slice"], 0) + 1
    print(f"wrote {len(requests)} requests: {by_slice}")


if __name__ == "__main__":
    main()
