#!/usr/bin/env python3
"""Grade a run's results.csv against workloads/answers.jsonl; adds graded_correct column.

Usage: grade.py --run-dir runs/<run-id> --answers workloads/answers.jsonl

Grading: gsm8k = final "ANSWER: <number>" (or last number) matches; mmlu = final
"ANSWER: <letter>" (or last standalone A-D) matches; humaneval = extracted ```python``` block
passes the reference unit tests in a subprocess with a timeout.
"""
import argparse
import csv
import json
import re
import subprocess
import sys
import tempfile

ANSWER_RE = re.compile(r"ANSWER:\s*([A-Da-d]|-?[\d,]*\.?\d+)", re.IGNORECASE)
NUMBER_RE = re.compile(r"-?[\d,]*\.?\d+")
LETTER_RE = re.compile(r"\b([A-D])\b")
CODE_RE = re.compile(r"```(?:python)?\s*(.*?)```", re.DOTALL)


def norm_num(s):
    try:
        return float(str(s).replace(",", "").strip())
    except ValueError:
        return None


def grade_gsm8k(answer_text, expected):
    m = ANSWER_RE.findall(answer_text or "")
    got = norm_num(m[-1]) if m else None
    if got is None:
        nums = NUMBER_RE.findall(answer_text or "")
        got = norm_num(nums[-1]) if nums else None
    exp = norm_num(expected)
    return got is not None and exp is not None and abs(got - exp) < 1e-6


def grade_mmlu(answer_text, expected):
    m = ANSWER_RE.findall(answer_text or "")
    if m and m[-1].upper() in "ABCD":
        return m[-1].upper() == expected
    letters = LETTER_RE.findall((answer_text or "")[-200:])
    return bool(letters) and letters[-1] == expected


TOXIC_RE = re.compile(r"ANSWER:\s*(TOXIC|SAFE)", re.IGNORECASE)
LABEL_RE = re.compile(r"ANSWER:\s*([A-Za-z][A-Za-z0-9_ /-]*)", re.IGNORECASE)


def norm_label(s):
    return re.sub(r"[^a-z0-9]+", "_", (s or "").strip().lower()).strip("_")


def grade_toxicchat(answer_text, expected):
    m = TOXIC_RE.findall(answer_text or "")
    if m:
        return m[-1].upper() == expected
    # fallback: last standalone TOXIC/SAFE token near the end
    tail = (answer_text or "")[-200:].upper()
    for tok in ("TOXIC", "SAFE"):
        if tail.rstrip().endswith(tok):
            return tok == expected
    return False


def grade_banking77(answer_text, expected):
    m = LABEL_RE.findall(answer_text or "")
    return bool(m) and norm_label(m[-1]) == norm_label(expected)


def grade_humaneval(answer_text, ans, timeout=15):
    m = CODE_RE.search(answer_text or "")
    code = m.group(1) if m else (answer_text or "")
    program = f"{code}\n\n{ans['test']}\n\ncheck({ans['entry_point']})\n"
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
        f.write(program)
        path = f.name
    try:
        r = subprocess.run(
            [sys.executable, path], capture_output=True, timeout=timeout, text=True
        )
        return r.returncode == 0
    except subprocess.TimeoutExpired:
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--answers", required=True)
    args = ap.parse_args()

    answers = {}
    with open(args.answers) as fh:
        for line in fh:
            if line.strip():
                a = json.loads(line)
                answers[a["id"]] = a

    path = f"{args.run_dir}/results.csv"
    rows = list(csv.DictReader(open(path)))
    counts = {"graded": 0, "correct": 0, "ungradable": 0}
    for row in rows:
        ans = answers.get(row.get("workload_id", ""))
        if not ans:
            row["graded_correct"] = ""
            counts["ungradable"] += 1
            continue
        text = row.get("answer", "")
        if ans["slice"] == "gsm8k":
            ok = grade_gsm8k(text, ans["answer"])
        elif ans["slice"] == "mmlu":
            ok = grade_mmlu(text, ans["answer"])
        elif ans["slice"] == "toxicchat":
            ok = grade_toxicchat(text, ans["answer"])
        elif ans["slice"] == "banking77":
            ok = grade_banking77(text, ans["answer"])
        else:
            ok = grade_humaneval(text, ans)
        row["graded_correct"] = int(ok)
        counts["graded"] += 1
        counts["correct"] += int(ok)

    cols = list(rows[0].keys()) if rows else []
    if "graded_correct" not in cols:
        cols.append("graded_correct")
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    acc = counts["correct"] / counts["graded"] if counts["graded"] else 0
    print(f"{path}: graded={counts['graded']} correct={counts['correct']} acc={acc:.3f} ungradable={counts['ungradable']}")


if __name__ == "__main__":
    main()
