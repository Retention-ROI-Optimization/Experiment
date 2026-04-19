# Retention Latency Paper Experiment Bed

이 디렉토리는 원본 `Retention_ROI_Agent`에서 논문 재현에 꼭 필요한 핵심 모듈만 추려 만든 실험 전용 프로젝트입니다.
대시보드/API/추천 UI 코드는 제거하고, 아래 4가지만 남겼습니다.

- **시뮬레이터 코어**: `src/simulator/`
- **피처 엔지니어링 코어**: `src/features/`
- **정책/강도 엔진 코어**: `src/optimization/policy.py`, `src/optimization/timing.py`, `src/optimization/dose_response.py`
- **실험용 오케스트레이터**: `src/paper_latency/`, `main.py`

이 프로젝트는 논문에 적은 실험 설계를 **코드 레벨에서 구현**한 것입니다. 즉 아래 항목이 모두 들어 있습니다.

1. **41개 decision week 기반 rolling-origin 반복 평가**
2. **12주 burn-in 후 평가 시작**
3. **5개 simulator seed 반복**
4. **4개 scenario family 반복**
   - `complaint-heavy`
   - `promotion-heavy`
   - `dormancy-heavy`
   - `seasonal-shift`
5. **freshness 조건 비교**
   - `0일`, `1일`, `3일`, `7일`
6. **강한 baseline 비교**
   - `base-fresh`
   - `base-stale`
   - `stronger-but-stale`
   - `weaker-but-fresh`
   - `full-refresh`
   - `partial re-optimization`
7. **blocked paired design**
   - 같은 `seed × scenario family × decision week × budget` 블록 안에서 정책을 비교
8. **예산 slice 고정 비교**
   - `2,640,000`
   - `7,250,000`
   - `11,530,000`
9. **정책 평가 지표 산출**
   - `policy_value`
   - `stale_regret`
   - `relative_loss`
   - `target_overlap`
   - `missed_at_risk`
   - `window_miss_rate`
   - `partial_reopt_regret_recovery_ratio`
   - `partial_reopt_full_refresh_value_ratio`
   - `partial_reopt_optimization_call_ratio`
10. **95% bootstrap CI 요약**

---

## 1. 디렉토리 구조

```text
retention_latency_experiment_bed/
├── main.py
├── requirements.txt
├── requirements.original.txt
├── README.md
├── scripts/
│   ├── run_smoke_paper.sh
│   └── run_full_paper.sh
└── src/
    ├── simulator/
    ├── features/
    ├── optimization/
    └── paper_latency/
        ├── config.py
        ├── io_utils.py
        ├── scenario_family.py
        ├── model_variants.py
        ├── engine.py
        └── evaluation.py
```

실험 실행 후 산출물은 아래에 생성됩니다.

```text
artifacts/
├── raw_grid/              # seed별 시뮬레이션 원시 데이터
├── feature_cache/         # as-of-date별 feature snapshot 캐시
├── models/                # seed별 base/stronger/weaker 모델
└── results/
    ├── training/
    ├── paper_latency/
    │   ├── block_level_metrics.csv
    │   ├── summary_metrics.csv
    │   └── manifest.json
    └── *.json
```

---

## 2. 설계가 코드에 어떻게 매핑되는가

### A. rolling-origin, 41 decision week
- `src/paper_latency/evaluation.py::_decision_schedule()`
- `state_snapshots.csv`의 주간 snapshot 날짜를 정렬한 뒤,
  - 앞 12주를 `burn-in`
  - 나머지를 `decision week`
- 기본 설정에서는 총 53주 snapshot 중 **12주 burn-in + 41주 평가**가 되도록 설계했습니다.

### B. 5개 seed 반복
- `prepare_simulation_grid()`가 seed별로 `src/simulator/pipeline.py::run_simulation()`을 실행합니다.
- 기본 seed는 `41,42,43,44,45` 입니다.
- 결과는 `artifacts/raw_grid/seed_<seed>/` 아래에 저장됩니다.

### C. 4개 scenario family
- `src/paper_latency/scenario_family.py`
- 같은 원시 시뮬레이션 로그 위에, 논문 stress-test용 feature perturbation을 씌웁니다.
- 즉, seed는 **로그 생성 변동성**, scenario family는 **운영 환경 변동성**을 담당합니다.

### D. freshness 0/1/3/7일
- `run_rolling_latency_evaluation()`에서 decision week `t`에 대해
  - `fresh`: `t`
  - `stale-1`: `t-1일`
  - `stale-3`: `t-3일`
  - `stale-7`: `t-7일`
  의 feature snapshot을 각각 만듭니다.
- 단, 논문 취지에 맞게 **다른 엔진 요소는 decision-time fresh frame을 유지하고, churn score 입력만 stale로 바꿔 넣는 방식**으로 구현했습니다.

### E. stronger-but-stale / weaker-but-fresh
- `src/paper_latency/model_variants.py`
- `base`: 중간 강도의 XGBoost
- `stronger`: 더 깊고 큰 XGBoost
- `weaker`: 제한된 whitelist feature만 쓰는 Logistic Regression
- 비교 규칙:
  - `stronger-but-stale`: stronger 모델을 **3일 stale** score로 적용
  - `weaker-but-fresh`: weaker 모델을 **0일 fresh** score로 적용

### F. 동일 의사결정 엔진 고정
- `src/paper_latency/engine.py`
- fresh/stale baseline 모두 같은 policy engine을 사용합니다.
- 엔진 내부 구성:
  - churn score
  - uplift proxy
  - predicted CLV
  - survival timing proxy
  - intervention intensity 후보 생성
  - budget-constrained greedy selection

### G. partial re-optimization
- `src/paper_latency/engine.py::partial_reoptimization()`
- stale 정책을 먼저 만든 뒤,
  - `fresh - stale` score gap이 큰 고객,
  - 혹은 fresh risk가 매우 높은 고객
  만 다시 re-score하여 budget selection을 다시 수행합니다.
- 즉 논문에서 말한 **“위험 점수 급등 고객 중심 부분 재최적화”**를 코드화했습니다.

### H. 95% bootstrap CI
- `src/paper_latency/evaluation.py::_summarize_block_metrics()`
- block-level 결과를 모은 뒤 scenario/budget/policy/latency 단위로 bootstrap CI를 냅니다.

---

## 3. 설치

프로젝트 루트에서 아래를 실행합니다.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

xgboost 설치가 안 되는 환경이면 `base/stronger` 학습이 실패합니다.
그 경우에는 xgboost가 깔린 환경에서 실행해야 합니다.

---

## 4. 실행 순서

### 4-1. 가장 빠른 스모크 테스트

아래 명령은 **1개 seed, 2개 scenario family, 2개 decision week**만 돌립니다.
구조가 제대로 연결됐는지 먼저 확인할 때 쓰세요.

```bash
bash scripts/run_smoke_paper.sh
```

직접 치려면:

```bash
python main.py \
  --mode run-paper \
  --project-root . \
  --seeds 41 \
  --scenario-families complaint-heavy,promotion-heavy \
  --latencies 0,1,3,7 \
  --budgets 2640000,7250000,11530000 \
  --decision-week-limit 2 \
  --bootstrap-iterations 100 \
  --training-landmarks 4
```

---

### 4-2. seed별 시뮬레이션 데이터만 먼저 만들기

```bash
python main.py \
  --mode prepare-grid \
  --project-root . \
  --seeds 41,42,43,44,45
```

이미 원본 프로젝트의 `data/raw/`가 준비돼 있다면, 디버깅/스모크용으로는 먼저 복사해서 warm start할 수도 있습니다.

```bash
mkdir -p artifacts/raw_grid/seed_41
cp /path/to/Retention_ROI_Agent/data/raw/* artifacts/raw_grid/seed_41/
```

그 뒤에는 `--seeds 41`만 주고 학습/평가를 먼저 점검하면 됩니다.

이 명령은 아래를 만듭니다.

```text
artifacts/raw_grid/seed_41/
artifacts/raw_grid/seed_42/
...
```

각 seed 디렉토리 안에는 원본 프로젝트와 같은 형식의 아래 CSV들이 들어갑니다.

- `customers.csv`
- `events.csv`
- `orders.csv`
- `state_snapshots.csv`
- `campaign_exposures.csv`
- `treatment_assignments.csv`
- `customer_summary.csv`
- `cohort_retention.csv`

---

### 4-3. base / stronger / weaker 모델만 먼저 학습하기

```bash
python main.py \
  --mode train-variants \
  --project-root . \
  --seeds 41,42,43,44,45 \
  --burn-in-weeks 12 \
  --training-landmarks 12
```

이 명령은 seed별로 burn-in 구간의 landmark snapshot을 feature panel로 쌓아서 학습합니다.

산출물:

```text
artifacts/models/seed_<seed>/seed_<seed>_base_model.joblib
artifacts/models/seed_<seed>/seed_<seed>_stronger_model.joblib
artifacts/models/seed_<seed>/seed_<seed>_weaker_model.joblib
artifacts/results/training/seed_<seed>/seed_<seed>_training_panel.csv
artifacts/results/training/seed_<seed>/seed_<seed>_<variant>_metrics.json
```

---

### 4-4. rolling-origin 평가만 실행하기

```bash
python main.py \
  --mode run-rolling \
  --project-root . \
  --seeds 41,42,43,44,45 \
  --scenario-families complaint-heavy,promotion-heavy,dormancy-heavy,seasonal-shift \
  --latencies 0,1,3,7 \
  --budgets 2640000,7250000,11530000 \
  --burn-in-weeks 12 \
  --training-landmarks 12 \
  --bootstrap-iterations 1000
```

이 명령은 이미 준비된 raw grid + 모델을 사용해 논문의 핵심 비교를 전개합니다.

---

### 4-5. 논문 실험 전체를 한 번에 실행하기

```bash
bash scripts/run_full_paper.sh
```

직접 치려면:

```bash
python main.py \
  --mode run-paper \
  --project-root . \
  --seeds 41,42,43,44,45 \
  --scenario-families complaint-heavy,promotion-heavy,dormancy-heavy,seasonal-shift \
  --latencies 0,1,3,7 \
  --budgets 2640000,7250000,11530000 \
  --burn-in-weeks 12 \
  --training-landmarks 12 \
  --bootstrap-iterations 1000
```

---

## 5. 산출물 해석

### `artifacts/results/paper_latency/block_level_metrics.csv`
가장 중요한 원자료입니다.
각 행은 사실상 하나의 paired block 비교 결과입니다.

핵심 컬럼:

- `seed`
- `scenario_family`
- `decision_date`
- `budget`
- `policy_kind`
- `latency_days`
- `policy_value`
- `fresh_policy_value`
- `stale_regret`
- `relative_loss`
- `target_overlap`
- `missed_at_risk`
- `window_miss_rate`
- `partial_reopt_policy_value`
- `partial_reopt_regret_recovery_ratio`
- `partial_reopt_full_refresh_value_ratio`
- `partial_reopt_optimization_call_ratio`

### `artifacts/results/paper_latency/summary_metrics.csv`
논문 표/그림용 요약 파일입니다.
scenario family × budget × policy kind × latency 단위로 mean과 95% bootstrap CI가 정리됩니다.

---

## 6. 논문 설계별로 어떤 명령을 쓰면 되는가

### A. “41개 decision week, 5 seed, 4 family, 4 latency를 모두 반영한 전체 실험”

```bash
python main.py \
  --mode run-paper \
  --project-root . \
  --seeds 41,42,43,44,45 \
  --scenario-families complaint-heavy,promotion-heavy,dormancy-heavy,seasonal-shift \
  --latencies 0,1,3,7 \
  --budgets 2640000,7250000,11530000 \
  --burn-in-weeks 12 \
  --training-landmarks 12 \
  --bootstrap-iterations 1000
```

### B. “stronger-but-stale vs weaker-but-fresh 비교도 반드시 포함하고 싶다”
별도 명령이 필요 없습니다.
`run-rolling` 또는 `run-paper` 안에 자동 포함됩니다.
기본 비교 지연은 `3일`입니다.
바꾸고 싶으면 아래처럼 바꿉니다.

```bash
python main.py \
  --mode run-paper \
  --project-root . \
  --stronger-vs-weaker-latency-days 3
```

### C. “부분 재최적화 기준을 더 공격적으로 바꾸고 싶다”

```bash
python main.py \
  --mode run-paper \
  --project-root . \
  --partial-reopt-score-delta 0.08 \
  --partial-reopt-high-risk-threshold 0.78 \
  --partial-reopt-top-share 0.20
```

의미:
- `score-delta`: fresh와 stale 차이가 이 값 이상이면 재최적화 후보
- `high-risk-threshold`: fresh risk가 이 값 이상이면 강제 후보
- `top-share`: delta 상위 몇 %까지 재최적화할지

### D. “시간이 너무 오래 걸리니 일부만 먼저 돌리고 싶다”

```bash
python main.py \
  --mode run-paper \
  --project-root . \
  --seeds 41 \
  --scenario-families complaint-heavy,dormancy-heavy \
  --decision-week-limit 5 \
  --bootstrap-iterations 200
```

---

## 7. 주의할 점

1. **full reproduction은 계산량이 큽니다.**
   - feature snapshot을 여러 날짜에 대해 반복 생성합니다.
   - seed × family × decision week × latency가 모두 곱해집니다.

2. **feature cache를 지우지 않으면 재실행이 빨라집니다.**
   - `artifacts/feature_cache/`

3. **base/stronger는 xgboost 의존**입니다.

4. 이 실험 베드는 논문 설계를 재현하는 데 초점을 맞췄기 때문에,
   **대시보드/실시간 Redis UI는 포함하지 않았습니다.**

5. 이 프로젝트의 survival/dose-response는 원본 정책 엔진을 활용하되,
   논문 재현을 위해 **실험용 proxy/heuristic 결합**을 사용합니다.
   즉 실험 비교의 핵심은 **freshness의 상대적 정책 비용**을 재는 것입니다.

---

## 8. 내가 가장 먼저 권하는 실행 순서

가장 먼저 이 3줄만 실행하세요.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

그 다음 구조 점검:

```bash
bash scripts/run_smoke_paper.sh
```

문제가 없으면 전체:

```bash
bash scripts/run_full_paper.sh
```

