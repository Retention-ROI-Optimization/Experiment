#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT_DIR"
python main.py \
  --mode run-hierarchical \
  --project-root "$ROOT_DIR" \
  --seeds 41,42,43 \
  --scenario-families complaint-heavy,promotion-heavy,dormancy-heavy,seasonal-shift \
  --latencies 1,3,7 \
  --budgets 2640000,7250000,11530000 \
  --burn-in-weeks 12 \
  --training-landmarks 12 \
  --decision-week-limit 16 \
  --bootstrap-iterations 300 \
  --partial-reopt-score-delta 0.10 \
  --partial-reopt-high-risk-threshold 0.80 \
  --partial-reopt-top-share 0.15 \
  --alpha-grid 0.05,0.10,0.20 \
  --conformal-min-cal-size 200 \
  --hierarchical-max-call-ratio 0.15 \
  --force
