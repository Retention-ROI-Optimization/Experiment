# 실험 결과 요약 및 해석

`summary_metrics.csv`(84행 × 35열)와 `block_level_metrics.csv`(4,032행 × 19열)의 원본 결과를 목적별로 7개의 요약 csv로 재구성하고, 각 표에서 읽어낼 수 있는 핵심 인사이트를 정리한 문서입니다.

> ⚠️ **주의**: 본 문서의 모든 수치는 원본 결과 파일을 **집계·재구성한 값**이며, 시뮬레이션을 재실행해 얻은 것이 아닙니다. 원본 수치와 완전히 일치합니다.

---

## 실험 설계 개요

| 축 | 수준 수 | 값 |
|---|---|---|
| scenario_family | 4 | complaint-heavy, dormancy-heavy, promotion-heavy, seasonal-shift |
| budget | 3 | 2.64M, 7.25M, 11.53M |
| policy_kind | 4 | base-stale, full-refresh, stronger-but-stale, weaker-but-fresh |
| latency_days | 4 | 0, 1, 3, 7 (base-stale에만 해당, 나머지는 정의된 지연값만 사용) |
| block_count | 48 | 의사결정 블록 수 (seed 3 × decision_date 16) |

조합상 총 84개의 summary 행, 4,032개의 block-level 행으로 구성됩니다.

---

## 정리된 파일 목록

| 파일 | 내용 | 행 수 |
|---|---|---|
| `01_summary_clean.csv` | 원본 84행 정돈본 — CI를 ±반폭으로 압축, 금액 M 단위, 비율 % 단위 | 84 |
| `02_by_scenario_policy.csv` | 시나리오 × 정책 평균 | 16 |
| `03_policy_overall.csv` | 정책별 전체 평균 (가장 압축된 비교표) | 4 |
| `04_latency_effect.csv` | base-stale에서 지연일(0/1/3/7)이 성능에 미치는 영향 | 4 |
| `05_budget_effect.csv` | 예산 3단계 × 정책별 성능 | 12 |
| `06_block_stats.csv` | block-level에서 seed 간 변동성 (평균·표준편차·min·max) | 84 |
| `07_policy_vs_full_refresh.csv` | full-refresh를 기준선으로 한 정책 간 상대 성능 비율 | 12 |

---

## 핵심 지표 요약

### 1. 정책별 전체 성능 (`03_policy_overall.csv`)

모든 시나리오·예산·지연일을 평균낸 결과입니다.

| policy_kind | policy_value (M) | stale_regret (M) | relative_loss (%) | target_overlap (%) | missed_at_risk (%) | window_miss (%) | selected_customers |
|---|---:|---:|---:|---:|---:|---:|---:|
| base-stale | 144.13 | -0.70 | -0.57 | 91.1 | 12.3 | 0.569 | 797.4 |
| full-refresh | 143.42 | 0.00 | 0.00 | 100.0 | 0.0 | 0.000 | 805.0 |
| stronger-but-stale | **149.55** | -6.13 | -4.27 | 78.4 | 32.8 | 1.338 | 751.7 |
| weaker-but-fresh | 91.87 | 51.55 | 38.08 | 74.0 | 4.0 | 0.000 | 1,219.6 |

**읽는 법**
- `stale_regret`의 **음수**는 stale 정책이 fresh 기준보다 policy_value가 더 높게 나왔다는 의미 — 이는 stale 정책이 좋다는 뜻이 아니라, 오래된 정보로 점수를 매긴 탓에 평가가 **낙관적으로 편향**됐음을 시사합니다. 실제 타게팅 품질은 `target_overlap`·`missed_at_risk`로 봐야 합니다.
- `target_overlap`은 fresh 기준과 타겟 고객 집합이 얼마나 겹치는지(100%가 이상).
- `missed_at_risk`는 fresh 기준에서는 타겟이었어야 할 고위험 고객을 놓친 비율.

### 2. 시나리오 × 정책 (`02_by_scenario_policy.csv`)

시나리오 간 정책 순위는 **거의 변하지 않습니다**. 4개 시나리오 모두에서 `stronger-but-stale`이 policy_value 최고, `weaker-but-fresh`가 최저. 즉 실험 결과는 특정 시나리오에 의존하지 않는 일반적 패턴입니다.

### 3. 지연일(latency)의 영향 (`04_latency_effect.csv`, base-stale만)

| latency_days | target_overlap (%) | missed_at_risk (%) | window_miss (%) |
|---:|---:|---:|---:|
| 0 | 100.0 | 0.0 | 0.000 |
| 1 | 88.6 | 15.8 | 0.303 |
| 3 | 88.2 | 16.3 | 0.444 |
| 7 | 87.5 | 17.1 | **1.529** |

- **지연 1일만 생겨도** target_overlap이 100% → 88.6%로 급락하고, 위험 고객 15.8%를 놓칩니다. 초기 낙폭이 가장 큽니다.
- 1일 → 7일로 늘어날수록 열화는 느려지지만 `window_miss`(개입 시점을 놓친 비율)는 0.3% → 1.5%로 **5배 증가**. 장기 지연의 진짜 비용은 이 지표에서 드러납니다.

### 4. 예산 효과 (`05_budget_effect.csv`)

`weaker-but-fresh`의 `relative_loss`는 예산이 커질수록 감소합니다:

| budget | weaker-but-fresh relative_loss |
|---:|---:|
| 2.64M | 51.8% |
| 7.25M | 37.9% |
| 11.53M | 24.5% |

예산이 작을 때 약한 모델의 손실이 가장 큽니다. 자원이 제한된 환경일수록 **모델 품질**이 신선도보다 중요해지는 구조입니다.

### 5. partial re-optimization 효과 (base-stale, `01_summary_clean.csv`)

base-stale 상황에서 부분 재최적화의 평균 성과:
- **최적화 호출 비율**: 약 **4.89%** — 전체 고객의 5% 미만만 재계산
- **full-refresh 가치 회복률**: **99.55%** — 전부 재최적화했을 때 대비 99.55%의 가치를 달성

즉 연산량은 1/20 수준으로 줄이면서도 성능은 거의 그대로 유지. 운영 관점에서 가장 실용적인 레버리지 지점입니다.

---

## 해석 — 정책별 특성 요약

| 정책 | 강점 | 약점 | 적합한 상황 |
|---|---|---|---|
| **full-refresh** | 품질·신선도 모두 최상 기준선 | 연산 비용 가장 큼 | 연산 자원 충분, 정확도 최우선 |
| **base-stale** | full-refresh와 policy_value 거의 동등(144.13 vs 143.42M), overlap 91% 유지, partial reopt 시 5%만 재계산해도 99.5% 가치 회복 | 미세하게 고위험 고객 누락(12%) | **실무 기본 선택지** |
| **stronger-but-stale** | policy_value 최고(+4.3%) | target_overlap 78%, missed_at_risk 33%로 타게팅 정합성 크게 훼손 | 평가 점수만 볼 때 매력적이나 실제 배포엔 위험 |
| **weaker-but-fresh** | window_miss 0%, 개입 시점 정확 | policy_value 38% 손실, 저예산에선 52% 손실 | 신선도가 결정적인 고빈도·저예산 운영 |

### 주목할 지점
1. **stale_regret 음수 해석**: 일부 stale 정책(특히 stronger-but-stale)에서 stale_regret이 음수로 나오지만 이는 성능 향상이 아니라 **stale 데이터로 자기 점수를 매긴 낙관적 편향**입니다. `target_overlap`·`missed_at_risk`를 함께 봐야 실제 품질이 보입니다.
2. **지연 비용의 비선형성**: 지연 0→1일에서 품질이 가장 크게 망가지고, 이후 추가 지연은 완만하게 악화. 실시간성 투자 우선순위는 **"지연이 발생하느냐 아니냐"** 가 **"얼마나 짧게 유지하느냐"** 보다 중요.
3. **partial re-optimization의 비용 대비 효과**: 5% 미만의 재최적화 호출로 99.5% 가치 회복은 매우 유리한 트레이드오프 — 실무 배치에서 설계 핵심이 될 수 있는 지점.

---

## block-level 변동성 (`06_block_stats.csv`)

block-level에서는 seed 3개 × decision_date 16개 = 48개 블록 내 변동성을 볼 수 있습니다. `policy_value_std_M`과 `policy_value_min_M / max_M` 컬럼으로 조합별 결과의 분산 정도를 확인할 수 있으며, 평균값만으로 가려진 불안정성을 점검할 때 참고하세요.

---

## 방법론 주석

- **CI 압축**: 원본의 `*_ci_low`, `*_ci_high` 두 컬럼을 `±반폭` 하나로 합쳤습니다. 필요 시 `mean ± halfwidth`로 원래 구간을 복원할 수 있습니다.
- **단위 통일**: 금액은 백만(M), 비율은 %로 표기했습니다.
- **정렬**: 모든 표는 `scenario_family → budget → policy_kind → latency_days` 순으로 정렬되어 있습니다.
