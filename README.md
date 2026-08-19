# Routing in Motion — evaluation artifact

Evaluation harness, workloads, analysis scripts, and raw run data for the paper
**"Routing in Motion: Durable and Observable Model Selection in Stateful Stream
Processing"** (submitted to IEEE BigData 2026). The system under evaluation is the
pluggable in-chat model routing feature of Apache Flink Agents
([apache/flink-agents#964](https://github.com/apache/flink-agents/pull/964)).

Every number in the paper is derived from the engine's own EventLog by the scripts in
`analysis/`; the complete measurement ledger, including negative results, corrections,
and the full audit trail (e.g., the alias-drift correction and the two key-stability
bugs the recovery audit found), is `analysis/RESULTS.md`.

## Layout

| Path | Contents |
|---|---|
| `harness/` | Flink eval jobs (source + `pom.xml`): `EvalJob` (per-request arms), `BatchedEvalJob` (windowed judge), strategies (`JudgeStrategy`, `MlRouterStrategy`, `NondetStrategy`, `LengthPlusKeywordStrategy`), `AnthropicChatModelSetup` |
| `workloads/` | Request/answer JSONL for all workloads + deterministic builders (`make_workload.py`, `make_workload_rq1b.py`, both seed 42) |
| `analysis/` | `parse_eventlog.py`, `grade.py`, `costs.py` + `prices.yaml` (pinned Aug 2026), `recovery_join.py`, `rq5_divergence.py`, `RESULTS.md` |
| `infra/` | Counting backend (RQ4 invocation ledger), RouteLLM sidecar, LiteLLM configs + observation hooks (RQ5), Kafka compose file |
| `*.sh` | Exact launchers for every experiment phase (RQ1/1b/2/3/4/5, batch sweeps, seeds, kill/restore, rescaled-restore, in-flight-kill, hash-split, and store-write trials) |
| `figures/` | Figure-generation scripts |
| **Release asset** | `runs-eventlogs.tar.gz` — raw per-run EventLogs, results.csv, checkpoints metadata for all ~150 runs (482 MB unpacked) |

## Routing-strategy classes in the harness

`JudgeStrategy` (LLM judge), `MlRouterStrategy` (RouteLLM BERT sidecar),
`LengthPlusKeywordStrategy` (custom heuristic), `NondetStrategy` (weighted coin flip),
`WeightedStrategy` (general per-candidate weights — the canary/A-B class; two-candidate
splits are evaluated, multi-way is supported but unexercised), and `HashSplitStrategy`
(sticky split keyed on request *content* — engine-generated ids regenerate on replay, so
id-keyed stickiness is not restart-stable without the durable store). The determinism 2×2
(weighted-random vs. hash split × store vs. no store) is documented in
`analysis/RESULTS.md`.

## Reproducing

1. **Build the system under test:** check out apache/flink-agents PR #964, `mvn install
   -DskipTests` (JDK 17) to publish `0.4-SNAPSHOT` locally.
2. **Build the harness:** `cd harness && mvn package -DskipTests` → a shaded jar.
3. **Workloads:** committed JSONLs are used as-is; `workloads/make_workload_rq1b.py`
   regenerates the RQ1b workloads (downloads sources into `workloads/data/`, seed 42).
   The ToxicChat sample is **not** committed (see licenses below); the builder
   reconstructs it deterministically.
4. **Keys:** the launchers read `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` from the
   environment (the original runs read them from local files; adjust the two
   `export` lines). Local arms need [Ollama](https://ollama.com) with
   `qwen2.5:0.5b` and `qwen3:1.7b`; recovery trials need Kafka
   (`docker compose -f infra/docker-compose.yml up -d kafka`).
5. **Run an arm end-to-end:** `./run_arm.sh <run-id> <arm> workloads/requests.jsonl`,
   then `analysis/parse_eventlog.py` + `analysis/grade.py` (the phase scripts show the
   exact flags for every reported run).

**Epoch caveat:** live-API arms call provider *aliases*. The paper pins access dates
(Aug 7–10, 2026 for the headline arms) and `analysis/RESULTS.md` documents a measured
+1pp drift of one alias within a week — reproductions should expect point estimates to
move with provider updates; the substrate results (attribution, overhead, scaling,
recovery) do not depend on alias behavior.

## Dataset licenses and attribution

- **GSM8K** (Cobbe et al., 2021, MIT), **MMLU** (Hendrycks et al., 2021, MIT),
  **HumanEval** (Chen et al., 2021, MIT) — items embedded in `workloads/*.jsonl`.
- **Banking77** (Casanueva et al., 2020, CC BY 4.0) — sampled items embedded in
  `workloads/rq1b-banking77.jsonl`.
- **ToxicChat** (Lin et al., 2023, CC BY-NC 4.0) — **not redistributed**; regenerate
  via the builder. Note: contains real, unfiltered toxic user prompts.

Run EventLogs contain model outputs from OpenAI, Anthropic, and local Qwen models,
published for research reproducibility.

## Code license

Apache License 2.0 (see `LICENSE`).
