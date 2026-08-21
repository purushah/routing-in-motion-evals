# Consolidated eval results (final data for main.tex) — 2026-08-07

## Table 1a — RQ1, close-models regime (gpt-4o-mini ↔ gpt-4o), n=1000/arm
| arm | acc | $/1k | % big $ | mix (big) |
|---|---|---|---|---|
| always-small | 86.9% | 0.157 | 6.0% | 0 |
| routed-rules | 88.0% | 1.887 | 71.8% | 615 |
| routed-mf | 89.8% | 1.985 | 75.6% | 500 |
| routed-custom | 89.6% | 2.373 | 90.4% | 784 |
| routed-judge | 90.9% | 2.956 | 112.6% | 978 (judge tokens incl.) |
| always-big | 91.7% | 2.626 | 100% | 1000 |
Oracle (route to mini iff mini correct): 94.5% acc — ABOVE always-big — at 13% big-rate
(mini right on 27 items big gets wrong). Headroom exists; generic policies capture little.

## Table 1b — RQ1, wide/modern regime (gpt-4.1-nano ↔ gpt-5.1 chat; +gpt-5-mini rung), n=1000/arm
| arm | acc | $/1k | % of 5.1 $ | mix (5.1) |
|---|---|---|---|---|
| always-nano (4.1-nano) | 85.1% | 0.090 | 8.4% | 0 |
| routed-mf (thr 0.8251) | 85.0% | 0.571 | 53.2% | 500 |
| routed-rules | 88.0% | 0.875 | 81.5% | 615 |
| routed-judge (4o-mini judge) | 88.2% | 1.096 | 102.1% | 976 |
| always-big (gpt-5.1) | 88.3% | 1.073 | 100% | 1000 |
| always-mini (gpt-5-mini, reasoning) | **95.1%** | 1.054 | 98.2% | 0 |
HEADLINES: (1) routed-rules matches the flagship's quality (88.0 vs 88.3) at 81.5% of its cost.
(2) Tier inversion: the reasoning-mode mini dominates the chat-mode flagship on BOTH axes —
size-based routing intuitions misfire on 2026 lineups; the frontier axis is reasoning mode.
Methods note: gpt-5-family requires default temperature (1.0); 4o/4.1 arms ran at integration
default 0.1 (API constraint, disclosed).

## Table 2 — RQ2 decision overhead (identical backend both candidates), n=1000/arm, local
| arm | decision_ms p50/p95/p99 | e2e Δ vs direct [95% CI] |
|---|---|---|
| rules | 0.016 / 0.05 / 0.07 | −3ms [−142,+140] (indistinguishable) |
| RouteLLM BERT (sidecar) | 71 / 100 / 121 | +132ms [−16,+292] |
| LLM judge (qwen3:1.7b, schema-constrained) | 491 / 908 / 1003 | +527ms [+412,+677] |
| judge, WINDOWED batch=20 | amortized ≈313/req (judge tokens 111/req vs ~500–700 solo) | window wait p50 6.3s |
Batch row: 42 judge calls for 840 requests (tail 160 dropped at end-of-input — timer semantics;
report completed batches). Windowing = substrate capability per-request proxies cannot express.
decision_ms persisted with decision (replay reports original).

## Table 3 — RQ3 scaling (routed-rules)
Stub 200ms backend (operator scaling), median of 3: p1 4.8 | p2 9.5 | p4 18.7 | p8 35.6 rec/s
→ speedups 1.00 / 1.97 / 3.88 / 7.37 (near-linear).
Real Ollama single server: 0.41 / 0.19 / 0.36 / 0.22 rec/s → saturates at p≥2 (report as the
single-box ceiling; production backends are horizontally scaled API fleets).
NOTE: requires fan-out map (upstream pins operator parallelism to source parallelism).

## RQ4 — recovery (scope: mechanism from code; outcome claims removed per author decision)
- No-store control: 47% of replayed decisions diverged (nondet strategy) — quantifies stateless re-routing.
- Recovery testing FOUND+FIXED a bug in our own durable path: route call id embedded the random
  request UUID → store lookups never hit (0/138 replayed; decision_ms fingerprint). Fixed 30121abb.
- Even with deterministic ids, rolled-back work re-ran (0/134) — durable replay scope narrower than
  end-to-end; upstream diagnostic pending. Paper asserts persisted-durable-decision MECHANISM only;
  "cannot drift" wording removed; dummy 100% table removed.
- Checkpoint observation: aligned barriers stall behind multi-second LLM calls (only early
  checkpoints complete) → discussion note; unaligned checkpoints as remedy.

## Table 5 — RQ5 LiteLLM head-to-head (nano↔5.1, same regex policy both arms) — FINAL
| property (observed at the engine) | proxy (LiteLLM) | ours |
|---|---|---|
| policy parity (accuracy) | 89.2% | 89.0% ✓ identical policy |
| backends visible to engine accounting | 0 of 2 (one "auto" pseudo-model) | 2 of 2 (305 gpt-5.1 / 195 nano) |
| routing decisions in engine event log | 0 | 500 |
| backend after engine kill/restart | **46.3% diverged** (99/214 replayed; proxy-side truth log) | durable-decision mechanism (design) |
| added network hop | not measurable at these latencies (−122ms noise; API variance ≫ localhost hop) | — |
Notes: LiteLLM masks the answering backend in response.model even in random mode — the
attribution finding demonstrated by the baseline itself; divergence ground truth required
instrumenting the proxy with a success callback (something its users can't rely on).

## Cost ledger
≈$50–55 total spent (incl. failed/rerun arms and both regimes) vs <$500 ceiling.

## Bug/finding ledger (for discussion section + upstream filings)
1. Judge prompt hijacked by embedded instructions → schema-constrained verdicts (harness; paper §discussion)
2. Framework retries don't cover routing decisions → strategies self-retry (v2 design note)
3. Operator parallelism pinned to source parallelism (upstream; ISSUES #8)
4. KafkaActionStateStore: 100ms admin timeout (fixed locally 6599313c; upstream PR candidate)
5. KafkaActionStateStore: accidental Beam Preconditions import (upstream)
6. Action-state keys break on '_' in Flink key (upstream; ISSUES #9)
7. OpenAI integration temperature default breaks gpt-5 family (upstream)
8. Route durable-call id nondeterminism (OUR bug; fixed 30121abb; goes into PR #964)
9. Aligned checkpoints stall behind long LLM calls (observation)
10. Bounded finished sources + in-flight work = loss on restore (framework semantics observation)

## Reviewer-driven experiments (2026-08-08, post mock-review) — 12 runs, ~$14
### B. Repeats (wide regime, 3 seeds each)
| arm | acc r1/r2/r3 | mean±sd | $/1k mean |
|---|---|---|---|
| routed-rules | 88.0 / 88.8 / 88.7 | 88.5±0.4 | 0.885 |
| always-big (gpt-5.1) | 88.3 / 88.3 / 88.1 | 88.2±0.1 | 1.078 |
| always-mini (gpt-5-mini) | 95.1 / 95.1 / 95.6 | 95.3±0.3 | 1.055 |
Rules vs big: +0.3pp (indistinguishable); cost ratio 82.1%. Tier inversion reproduces on all seeds.

### A. Candidate set fixed (mini IN the set): routed-rules nano<->gpt-5-mini
90.1% @ $0.690/1k = 65% of always-mini's cost (95.3% @ $1.055), 615 mini / 385 nano.
Beats the flagship (88.2%) at 64% of its cost. Answers "why not just pin mini?": routing
the dominant model captures most of its quality at 2/3 cost; policy headroom remains.

### C. Temperature-equalized (T=1.0 on non-gpt-5 arms)
always-nano: 85.1 -> 84.7 (-0.4pp); routed-rules: 88.5 (mean) -> 87.9 @ $0.907.
Both within ~1 SE: the 0.1-vs-1.0 confound does NOT carry the headline.

### Anthropic arms (third provider; via OpenAI-compat endpoint api.anthropic.com/v1)
| arm | acc | $/1k | notes |
|---|---|---|---|
| always-haiku (claude-haiku-4-5) | 94.0% | 1.310 | $1/$5 model ~ matches gpt-5-mini, crushes gpt-5.1 |
| always-sonnet (claude-sonnet-5) | 97.6% | 2.232 | best quality overall (intro price $2/$10 thru Aug 31) |
| routed rules nano<->sonnet (CROSS-PROVIDER) | 92.1% | 1.546 | 69% of sonnet cost; engine attributes 615 sonnet + 385 nano across two vendors |
Tier inversion is CROSS-PROVIDER: haiku (94.0) also dominates gpt-5.1 (88.2) on quality at similar cost.
Honest note: haiku dominates the cross-provider routed arm too — generic-policy headroom theme persists.

### New finding (Issue #11)
claude-sonnet-5 rejects `temperature` outright ("deprecated for this model"); integration cannot
omit the parameter (always sends 0.1 default) -> every call 400s; router fallback silently absorbed
all traffic onto haiku — caught immediately via fallback-source ModelRoutingEvents (observability demo).
Harness fix: AnthropicChatModelSetup strips the parameter. Third provider sampling constraint
(gpt-5: mandatory default; sonnet-5: parameter rejected).

### Cost ledger update
+~$14 (12 runs) -> total ~= $65-70.

## RQ4 POST-FIX RESULT (2026-08-08) — the missing measurement, now measured
Root cause of the residual 0/134: ActionStateUtil.generateUUIDForAction embeds
UUID(action.hashCode()); Action.hashCode -> JavaFunction.hashCode -> Arrays.hashCode(Class[])
-> Class identity hash = per-JVM => every durable key changes across restart. FRAMEWORK-WIDE
bug (Issue #12; fixed locally bfb78d4f: use plan-unique action.getName()).
Post-fix kill/restore trial 1 (routed-nondet coin flip, Kafka store, 5s checkpoints, 400 items,
kill -9 at 200 responses, restore chk-2): 90 re-processed previously-decided items ->
**90/90 replayed, 0 diverged (0.0%)**, all 90 with BYTE-IDENTICAL persisted decision_ms
(fingerprint positive verdict). vs no-store control 47%, expected ~50% under re-derivation.
Trials 2-3 running for a 3/3 aggregate.
Fingerprint methodology now validated in BOTH directions: negative (caught 2 bugs: our
route-id UUID + framework identity-hash key) and positive (byte-identical replay post-fix).

## Invocation-ledger trial (2026-08-10, external-review item #3)
Counting HTTP backend (separate process, persistent JSONL ledger, 200ms fixed latency) as both
candidates; routed-nondet + Kafka store; kill -9 at 202/400, restore.
RESULT: **400/400 requests invoked exactly once at the backend across the entire kill/restore**
(zero duplicate invocations anywhere); replayed-window items 4/4 with 0 additional invocations;
0% routing divergence. Backend-side ground truth that recovery re-issued no calls and double-
billed nothing. Caveat: window small (4) in this trial; calls genuinely in-flight at kill would
legitimately re-issue (at-least-once side effects) — none occurred here.

## RQ3-D distributed sweep (2026-08-10, external-review item #5) — running
Standalone Flink 2.3.0 cluster on this host: 1 JobManager + 4 TaskManagers (separate JVMs,
2 slots each), REST 8082, checkpoints 5s, thin job jar (-Pcluster profile, flink deps provided,
143MB; needed rest content-length raise to 300MB). Same RQ3 design: 400 stub:200, routed-rules,
p=1/2/4/8 x3. Throughput from CLI Job Runtime.

RQ3-D RESULTS: p1/2/4/8 medians 84.0/43.7/24.5/14.9s for 400 req ->
4.8/9.2/16.3/26.8 rec/s; raw speedups 1.00/1.92/3.43/5.63 (fixed ~4.5s deploy overhead);
overhead-subtracted 7.7x at p8, matching embedded curve. Note: needed rest content-length
raise (143MB thin jar > 100MB default) — practitioner footnote.

## Batch v2 rerun (2026-08-10, end-of-input flush fix)
BoundedOneInput.endInput() flush added to Batcher (processing-time timers do not fire at
end of bounded input — root cause of the 160/1000 loss). rq2-judge-batched-v2:
50 windows x20, 1000/1000 routed, amortized judge 247ms/req (was 313 over 42 windows),
p50 wait 4.9s (was 6.3), judge tokens 111/req (unchanged). Smoke proved the endInput path
(45 requests, 5-min timeout: tail-5 flushed only by endInput).

## Batch sizing-at-rate sweep (2026-08-12) — FINAL
API judge (gpt-4o-mini), local chat backends, lambda=8/s, N in {20,50,100,200,400}:
  N:        20    50    100   200   400
  toks/req: 105   102   101   100   100     <- saturates by N~20 (solo judge: 500-700)
  judge_s:  0.9   1.7   2.8   4.9   6.3     <- grows with N (serialization pressure)
  wait_s:   1.5   3.5   7.9   14.0  25.8    <- fits fill model N/(2*lambda) closely
  parse:    1000/1000 at every N; verdict escalation drifts 60-91% with N (not neutral)
Local qwen3:1.7b judge: clean at N=20 (111 t/req), TOTAL collapse at N>=50 (100% parse_failed,
judge calls 225-429s) -> judge capability sets the ceiling; economics set the optimum (N~20-50).
Rate dimension (local judge, N=20): wait p50 8.0/6.2/4.8s at lambda=2/8/32 — batching latency
FALLS as traffic rises (fill component vanishes). 4-lane run confounded by single Ollama server
(lanes parallelize the engine; the model server serializes) — same isolation lesson as RQ3.
Harness scars: judge HTTP timeout 120s, Ollama num_ctx default, missing retry guard — all
chat-scale defaults that broke at batch scale.
Verdict for paper: live sweet spot N~20-50; offline-range N=100-400 buys nothing on a stream;
Ks -> provider Batch APIs (50% off, larger T, durable job-id as future work).

## RQ1b streaming-native workloads (2026-08-15) — ToxicChat + Banking77, 3 seeds
Workloads (workloads/make_workload_rq1b.py, seed 42, exact-dup prompts dropped):
  toxicchat: lmsys/toxic-chat 0124 test, BALANCED 362 toxic + 362 safe -> 716 items
             (real user->chatbot traffic, >=3-annotator majority labels; ANSWER: TOXIC|SAFE)
  banking77: PolyAI test, 12/intent x77 -> 923 items (77-way; label list rides in prompt,
             message FIRST so eventlog truncation keeps prefixes unique; ANSWER: <intent>)
Arms per workload (parallelism 8, pinned-anthropic.jar): nano=gpt-4.1-nano, mini=gpt-5-mini,
big=gpt-5.1, judge=routed-judge(4o-mini over nano/big). Runs rq1b-{tc,b77}-{arm}[-r2|-r3].

acc mean±sd over 3 seeds (usd/1k from seed 1):
  toxicchat: nano 86.5±0.2 ($0.018) | mini 82.4±0.3 ($0.38) | big 77.2±0.5 ($0.33)
             | judge 81.7±0.1 ($0.20)
  banking77: nano 49.2±0.4 ($0.054) | mini 78.8±0.3 ($0.44) | big 79.8±0.6 ($0.79)
             | judge 56.4±0.9 ($0.28)

Findings:
1. ToxicChat INVERSION: capability tier anti-correlates with moderation accuracy.
   Toxic recall nano 75% > mini 70% > big 55% (safe-acc flat ~98%); flagship under-flags
   borderline toxicity. Majority-vote McNemar nano-vs-big p=6.7e-10; nano-vs-judge p=2.1e-7
   (judge escalated 41% of traffic to the model with WORSE verdicts). Second independent
   tier!=fit instance, now on real user traffic. Right routing decision = all-nano:
   18x cheaper AND most accurate.
2. Banking77 steep ladder then plateau: nano 49% -> mini 79% (+30pts), mini vs big
   p=0.14 (indistinguishable) at 55% of big's cost. Surface judge FAILS here: escalated
   only 17% (77-way confusion invisible from surface) -> 56.4%, barely above nano.
   Live demo of the "weak judge over hidden difficulty" quadrant.
Paper angle: per-WORKLOAD tier selection is the first-order routing win on streaming-native
traffic; per-request surface routing helps neither workload — difficulty is either flat
(moderation) or hidden (77-way intent). Judge-quality ceiling matches RQ2's finding.
Pilot decision rule was big-beats-nano>=3-4pts; both passed in unexpected directions.

DECISION (2026-08-16): ToxicChat DROPPED from the paper (user call) — inversion is
policy-fit, attackable as prompt engineering; no per-request ladder for routing. Data
retained here + runs kept for talk/v2. Banking77 is the sole RQ1b candidate.

## RQ1b judge fairness check + oracle headroom (2026-08-16)
User challenged the b77 judge number. Root cause found: routerBuilder() candidate
DESCRIPTIONS were hardcoded for the math workload ("code, SQL, math...") — the judge
routed by them faithfully, so 17% escalation was a misconfiguration artifact, NOT
evidence of hidden difficulty. EvalJob gained --small-desc/--big-desc (harness rebuilt
against rebased 0.4-SNAPSHOT); reruns with banking-appropriate descriptions:
  judge-v2 (nano/gpt-5.1):  61.4% @ $0.437/1k, escalation 38% (was 56.4% @ 17%)
  judge-v3 (nano/gpt-5-mini): 60.0% @ $0.305/1k, escalation 38%
Oracle headroom (per-item union, seed 1): nano|big 82.6%, mini|big 84.5%, nano|mini
81.5% vs always-big 79.8% — a PERFECT nano/big router gains only +2.8pts. Banking77 has
minimal per-request headroom (models fail the same confusion items); with judge overhead
(~$0.15/1k) every judge config is dominated by the always-mini anchor (78.8% @ $0.44).
CORRECTED paper framing: not "surface judge fails on hidden difficulty" but "the
efficient frontier here is an anchor, not a router: per-workload tier selection wins,
and the oracle bound shows per-request routing could add at most ~3pts."

DECISION UPDATE (2026-08-16): ToxicChat back IN as a 3-4 sentence cautionary
policy-fit note (user call) — tier upgrade silently drops toxic recall 75->55%,
only per-model in-pipeline measurement catches it. Not a headline claim.

## Dollar-matched random control — MEASURED (2026-08-16, panel round 1 fix)
rq1w-rand80b-r{1,2,3}: NondetStrategy escalate_p=0.80 over nano/gpt-5.1 (rebuilt jar;
NOTE pinned-anthropic.jar silently IGNORES --escalate-p — rand80-r* runs are 50/50, discard).
acc 88.3/88.7/88.8 -> 88.6±0.3 at $0.886/0.888/0.912 (~$0.90/1k) — genuinely dollar-matched
(rules $0.885) and a statistical TIE with rules 88.5±0.4. The paper's old interpolation (~87.5)
was WRONG: random escalation misses the expensive long items, so 80% random escalations cost
what 61.5% targeted ones do, and coverage of hard items scales with rate. Paper now states:
targeting buys same accuracy at 61.5% vs 80% escalation, not more accuracy per dollar.

## Dollar-matched control CORRECTION (2026-08-16, panel round 2)
Skeptic reviewer caught that rand80b's 88.6% EXCEEDS the convex-mixture ceiling
(0.2*84.5 + 0.8*88.2 = 87.5; a uniform random mix cannot beat its better anchor 88.2).
Root cause: EPOCH DRIFT — big-subset accuracy inside rand80b runs is 89.0-89.3%, i.e. the
gpt-5.1 alias improved ~+1pp between the pinned week (Aug 7-10) and Aug 15-16. Cross-epoch
comparison invalid. Paper now states the dollar-matched result as the CONVEX BOUND (any
item-independent random policy <= better anchor 88.2 < rules 88.5 — stronger than the old
interpolation and experiment-free), with the drift run cited as live proof of why access
dates are pinned. rand80b runs retained as the drift evidence.

## RQ4 RESCALED-restore trials (2026-08-16) — envelope extension
rq4-rescale-t{1,2,3}: identical to certified trials but restore at p=4 from a p=2
checkpoint (key-group redistribution), routed-nondet, Kafka store, pinned-rq4.jar.
Replayed 39/8/62 = 109 decisions; 109/109 same model AND byte-identical decision_ms;
0% divergence. Durable-call scoping invariant under key-group redistribution.
Paper envelope updated: same-OR-different parallelism single-process restores certified;
multi-node remains outside. Script: rq4_rescale_trial.sh. Kafka via Rancher Desktop
(open -a "Rancher Desktop"; docker compose -f infra/docker-compose.yml up -d kafka).

## RQ4 IN-FLIGHT-kill trials (2026-08-17) — the at-least-once boundary, exercised
rq4-inflight-t{1,2}: counting backend at 4s latency (phase-stamped ledger: recv/resp/
resp_err), p=4, kill at ~40 responses with calls genuinely in flight. Script
rq4_inflight_trial.sh; analysis analysis/inflight_join.py.
Per trial 400 unique prompts, 404 recvs. Combined: 8 re-issued calls = 6 in-flight at
kill (3 detected as broken pipes, 3 as resp-into-dead-socket) + 2 completed after the
last checkpoint (the documented orphaned-payload window). All other 792 prompts invoked
EXACTLY once. **8/8 re-issues called the SAME model as the first attempt** (coin-flip
strategy; P(chance)=2^-8≈0.4%) — a mid-call crash re-issues the chat but REPLAYS the
persisted decision, because the decision's durable write completes before the call
starts. Double-billed tokens upper bound: 144 across 800 requests (0.9 tokens/req).
Note: broken-pipe detection undercounts in-flight (TCP may accept writes to a dead
peer); classification uses resp-after-kill-ts as well.

## Store-write cost isolation (2026-08-17) — reviewer ask
rq_storewrite.sh: routed-nondet vs stub:200 backends, p=1, 400 items, 3 repeats per arm.
  store OFF: p50 207.0/207.5/211.6ms (pooled 208.8)
  store ON (kafka, 5s ckpt): p50 231.6/232.2/232.3ms (pooled 232.0), p99 266-388
  DELTA: +23.2ms/routed request [bootstrap 95% CI 22.5, 24.3] = ~11.6ms per durable
  write (2 writes/request: route + chat), Kafka acks on localhost.
Reading: durability costs ~23ms per routed request — ~11% of a 200ms stub call,
negligible against real LLM latencies (0.5-30s), and consistent with RQ2's e2e CIs
(±140ms API variance) never resolving it.

## Configured-LiteLLM proxy arm (2026-08-17) — reviewer ask (Table IV fairness)
Setup: LiteLLM 1.95.0, litellm-policy-configured.yaml + litellm_hook_configured.py
(same regex policy + post-call hook rewriting response.model to the true deployment),
backends = local counting server (attribution is transport mechanics; no API cost).
Findings (mechanical, epoch-free):
  1. The post-call hook FIRES (content mutation survives) but LiteLLM pins the
     OpenAI-standard body `model` field to the client-requested alias afterwards —
     response.model rewrite does NOT survive, so no configuration OR custom hook can
     surface deployment identity in the body field this version.
  2. The deployment IS surfaced in gateway-specific headers (x-litellm-model-name:
     openai/count-big, x-litellm-model-api-base, spend headers) — the admin-plane
     concession the paper already makes.
  3. Engine-side: the original 500-request run recorded model_name="auto" for all 500
     responses (re-verified from its eventlog). A 100-request rerun through the
     configured proxy with pinned-rq4.jar recorded no model_name at all (that jar
     variant does not propagate the field — harness quirk, noted).
Conclusion for Table IV: the accounting gap is ARCHITECTURAL, not configurational —
any client whose accounting reads the standard body field (ours, and any OpenAI-SDK
consumer) attributes to the alias under best-practice config too; per-backend
attribution in the pipeline requires a gateway-specific header integration and join.
This SHARPENS the paper's claim rather than softening it.

## Weighted-routing determinism 2x2 (2026-08-19) — hash-split no-store trials
New harness strategies: WeightedStrategy (general per-candidate weights; canary/A-B class)
+ HashSplitStrategy (sticky split keyed on request CONTENT — deliberately not the engine
request id, which regenerates on replay per RQ4 bug one). New arms routed-weighted /
routed-hashsplit; jar rebuilt (NOTE: rebased framework's Ollama client 404s vs local
Ollama — trials use the counting backend instead).
rq4-hashsplit-t1b/t2: kill/restore WITHOUT action-state store, 50% hash split:
2/2 and 40/40 re-processed decisions identical, 0% divergence.
COMPLETED 2x2 (divergence across restart):
                      durable store     no store
  weighted random     0% (111/111)      47% (56/118)
  hash split          0% (trivially)    0% (42/42 measured)
Reading: deterministic sticky splits need no store; weighted-random (canary/A-B) is
exactly the routing class whose assignments a restart reshuffles without the durable
decision — restart contaminates the experiment. Also: rate-matched random control
(86.9) sits ON the convex mixture line (predicted 86.8) — weighted routing IS the
budget dial; targeting lifts you above the line (rules 88.5).

## Server-hardware validation on a Kubernetes pod, AWS EKS (2026-08-19)
Setup: pod (16 CPU) from user's yflink image on m6i.8xlarge (32-vCPU Xeon) node,
pinned-rq4.jar via kubectl cp, in-pod KRaft Kafka 3.9.0 (localhost, same topology as Mac),
runs in the server-runs release asset. Latency-sensitive results vs the Mac laptop:
  rules decision_ms:  p50 0.019ms (Mac 0.016) — same class; p99 0.33 vs 0.07 (warmup tail)
  engine overhead over stub:200: 0.8ms (Mac 8.8ms) — server BETTER
  store-write delta: +3.4ms/req [3.4,3.5] = ~1.7ms/write (Mac +23.2 = ~11.6/write) — 7x BETTER
  RQ3 speedups p1/2/4/8: 1/1.95/3.59/6.32 (Mac 1/1.98/3.90/7.42) — same near-linear shape
  (p8 mildly lower under the 16-CPU pod limit)
Verdict: every structural claim reproduces; the laptop numbers are CONSERVATIVE (durability
cheaper on servers). No paper number needs replacement; a one-line validation note suffices.

## Server RQ4 suite — full reproduction on server hardware (2026-08-20)
All 10 trials on the server pod (m6i.8xlarge, in-pod Kafka, counting backend, NEW rebased
jar, 15s checkpoints): fingerprint 69/69 (3 trials, model + byte-identical decision_ms),
rescaled p2->4 45/45, weighted no-store 41% divergence (9/22; coin-flip class), hash-split
no-store 44/44 model-identical, in-flight 8/8 reissues kept the persisted decision (4+4,
all broken-pipe-detected). Every Mac recovery claim reproduces on the current framework on
server hardware. Runs: release asset, runs/om-*.

## Server RQ2 rerun (2026-08-20, rebuilt pod, rebased framework) — COMPLETE
m6i.8xlarge (32 vCPU, CPU-only Ollama 0.32.14), n=1000/arm, identical backend both candidates
(qwen2.5:0.5b), judge qwen3:1.7b, BERT sidecar threshold 0.8251. All arms rc=0, 1000/1000 parsed.
| arm | decision_ms p50/p95/p99 | e2e delta vs direct [95% CI] |
|---|---|---|
| rules | 0.027 / 0.05 / 0.09 | -56ms [-158,+65] (indistinguishable) |
| RouteLLM BERT | 37.8 / 62 / 81 | -73ms [-199,+56] (indistinguishable) |
| LLM judge | 776 / 982 / 1159 | +737ms [+583,+866] |
| judge windowed N=20 | amortized 641ms/req; 110 judge tok/req; wait p50 12.8s p95 14.2s | 50 windows, 0 parse failures |
Direct e2e median 1665ms. vs Mac: rules/BERT same class (BERT faster: 38 vs 71ms); judge slower
(776 vs 491 — server CPU vs Apple silicon); batched TOKEN saving identical (110 vs 111/req),
but amortized LATENCY saving shrinks (776->641, 17%, vs 491->247, 50%) because the 20-request
judge call itself costs ~12.8s on CPU; window wait is judge-bound (fill ~0.8s at this rate),
NOT fill-bound as on Mac. Batched lost no tail (1000/1000; endInput flush held on rebased fw).
BERT note: routellm installed clean on py3.9 after pip upgrade; sidecar needed dummy
OPENAI_API_KEY (module-import quirk) — decision path fully local.

## CORRECTION (2026-08-20, raw-data audit): solo-judge token figure
The "~500-700 judge tokens/request solo" figure (quoted at the Table-2 batch row, the batch
sweep, and echoed in the paper/deck) is NOT supported by any run on disk. Measured solo judge
tokens/request (prompt+completion, medians): om-rq2-judge 212 (max 531), Mac rq2-judge-v4 212,
API rq1w-judge 224 (max 546). The correct batched saving is ~2x (212-224 -> 105-110), not ~5x.
Earlier "500-700" appears to have been an early-probe estimate that propagated; judge-probe runs
recorded no token columns. Paper, fig5 annotation, and deck corrected to ~2x on 2026-08-20.
