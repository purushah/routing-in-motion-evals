#!/bin/sh
# Server RQ2 rerun (Kubernetes pod, AWS m6i.8xlarge, 2026-08-20): decision-overhead arms, n=1000,
# identical backend both candidates (qwen2.5:0.5b), judge qwen3:1.7b.
cd /tmp/eval
export HOME=/tmp OLLAMA_MODELS=/tmp/ollama-models
JAR=harness.jar
REQS=workloads/requests.jsonl
SAME="--small qwen2.5:0.5b --big qwen2.5:0.5b"

head -5 $REQS > workloads/smoke5.jsonl
java -jar $JAR --run-id om-smoke --arm routed-rules --runs-dir runs \
  --requests-file workloads/smoke5.jsonl $SAME > runs_om-smoke.stdout.log 2>&1
echo "[$(date +%H:%M:%S)] smoke rc=$?"

run() {
  id=$1; arm=$2; shift 2
  echo "[$(date +%H:%M:%S)] START $id ($arm) $*"
  java -jar $JAR --run-id "$id" --arm "$arm" --runs-dir runs --requests-file $REQS $SAME "$@" \
    > "runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] DONE $id rc=$?"
}
run om-rq2-direct always-small
run om-rq2-rules  routed-rules
run om-rq2-judge  routed-judge --judge-model qwen3:1.7b

echo "[$(date +%H:%M:%S)] START om-rq2-judge-batched"
java -cp $JAR org.apache.flink.agents.eval.BatchedEvalJob \
  --run-id om-rq2-judge-batched --requests-file $REQS $SAME --judge-model qwen3:1.7b \
  --batch-size 20 --batch-timeout-ms 5000 --runs-dir runs \
  > runs_om-rq2-judge-batched.stdout.log 2>&1
echo "[$(date +%H:%M:%S)] DONE batched rc=$?"

# mf arm only if the RouteLLM sidecar is up on :8765
if curl -s --max-time 2 http://127.0.0.1:8765/health >/dev/null 2>&1; then
  run om-rq2-mf routed-mf
else
  echo "sidecar not up; skipping om-rq2-mf"
fi
touch /tmp/eval/RQ2_DONE
