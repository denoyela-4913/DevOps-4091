#!/usr/bin/env bash
# Campagne de stress AWS : plusieurs charges x plusieurs runs, puis synthèse (aggregate-stress.sh de docker).
# Appel (depuis Exercice_3/aws/) : ./run-tests-aws.sh [--rates "100 300"] [--runs 2] [--cycles 3]
# Résultats : results/stress-r<RATE>/<CFG>/run-*.json et SYNTHESE.md (docker/results/aws -> ../../aws/results)
set -u
cd "$(cd "$(dirname "$0")" && pwd)" || exit 1
RATES="100 300"; RUNS=2; export CYCLES=3 CFG=${CFG:-aws}
while [ $# -gt 0 ]; do case $1 in --rates) RATES=$2; shift 2;; --runs) RUNS=$2; shift 2;; --cycles) CYCLES=$2; shift 2;; *) shift;; esac; done
export CYCLES
ln -sfn ../../aws/results ../docker/results/aws
for run in $(seq 1 "$RUNS"); do
  for r in $RATES; do RATE=$r ./test-stress-aws.sh "results/stress-r$r/$CFG"; done
done
for r in $RATES; do ../docker/tests/aggregate-stress.sh --dir "stress-r$r" aws; done
