# Project Context — HPV VHA Microsimulation (Aim 2)

This document consolidates decisions and audits made during initial project setup. It is reference knowledge for Claude; the operating instructions live in the project's custom-instructions field.

Two sections:
1. **Natural History Audit** — where the code diverges from the grant's stated disease model, and what was changed in the v3 rewrite.
2. **Excel ↔ Code Parameter Mapping** — current alignment between the parameter spreadsheet and the simulation code, with gaps in both directions.

---

# Part 1: Natural History Audit

Original audit of `2026_02_16_helper.R` + `2026_02_16_simulator.R` against the funded grant's stated model. The v3 rewrite (`helper_v3.R` / `simulator_v3.R`) addresses most Tier A items; this section is preserved for context on *why* those changes were made.

## 1. State machine — fundamental mismatch (resolved in v3)

**Grant (Research Plan, Aim 2):** "Agents move through five health states (Healthy, HPV Infection, Persistent Infection, HPV-associated OPC, Death) according to probabilistic rules…"

**Original code:** `healthy → infected → cancer_active → cancer_survivor → dead` — no `Persistent Infection` state; a duration gate inside `infected` controlled cancer eligibility, and a non-grant `cancer_survivor` state was added.

**Why this mattered:**
- "Infected" and "Persistent" are clinically distinct categories with different transition rules. Most HPV infections clear within 12–24 months; the small subset that persist carry fundamentally different cancer risk.
- The grant explicitly says **"Vaccination reduces the probability of HPV infection and persistence"** — vaccination should act at two points: acquisition AND the acute→persistent transition. The original code could only act at acquisition.

**v3 resolution:** `persistent` is now a real state. Transition rule: `infected → persistent` if duration crosses `persistence_threshold_years` (default 2y). Cancer eligibility moved to "in persistent state" with its own clock.

## 2. Agent attributes — grant attributes missing, non-grant attributes present (resolved in v3)

| Attribute | Grant says | Original code | v3 |
|---|---|---|---|
| Age | ✓ | ✓ | ✓ |
| Sex | ✓ | ✗ | ✓ (added) |
| Vaccination | ✓ | ✓ | ✓ |
| Smoking | ✓ | ✓ | ✓ |
| Alcohol | ✓ | ✗ | ✓ (added as `alcohol_heavy`) |
| VISN | ✓ | ✗ | ✗ (deferred; needed if VISN-stratified outputs required) |
| MSM | ✗ | ✓ | ✗ (removed; reviewer questioned VA-data measurability) |
| Vaccine hesitancy | ✗ | ✓ | ✗ (removed; collapsed into uptake probability) |

## 3. Risk factor effects — at least one mechanism missing (resolved in v3)

| Effect | Grant says | Original | v3 |
|---|---|---|---|
| Vaccination ↓ acquisition | ✓ | ✓ | ✓ (`VE_acquisition`) |
| Vaccination ↓ persistence | ✓ | ✗ | ✓ (`VE_persistence`) |
| Smoking ↑ progression | ✓ | ✓ | ✓ |
| Alcohol ↑ progression | ✓ | ✗ | ✓ |
| Smoking ↑ acquisition | not in grant | ✓ | ✓ (retained; biologically defensible) |

## 4. Cancer transition — original generated implausibly high incidence (resolved in v3)

Original logic: after passing a 10-year duration gate, an annual 5% cancer hazard fired forever with smoking/prior-infection multipliers. Combined with 95% per-year persistence after duration >5y, this produced a cumulative cancer probability of ~79% by age 65 for anyone acquiring HPV at 25 — roughly two orders of magnitude too high vs. actual lifetime HPV-attributable OPC risk in high-risk men (<1%).

**Two compounding issues:**
1. **Constant annual hazard.** Geometric distribution makes cancer near-certain over long follow-up. Biology suggests Weibull-like hazard near-zero for the first 10–15 years post-persistence, peaking in a window.
2. **`p_persistence_to_opc` was mis-named.** Coded as per-year probability past the gate; with Weibull semantics it should be time-to-event shape/scale parameters.

**v3 resolution:** At the moment an agent enters `persistent`, time-to-cancer is sampled from `Weibull(shape, scale)` and stored on the agent. Cancer triggers when `persistent_duration ≥ time_to_cancer`. Sex, smoking, alcohol, and smoking×alcohol synergy shrink the scale (faster progression). Nature Comms paper (referenced in Excel Sheet 5) should anchor the Weibull parameters.

## 5. OPC survival was far too low (resolved in v3)

Original `opc_mortality = 0.3` annual → 5y OS ≈ 17%. Published HPV+ OPC 5-year OS is ~75–85% (Ang 2010 NEJM, cited in the grant). Combined with the over-incidence above, the original model produced an order-of-magnitude excess of OPC deaths — which makes any expanded-vaccination scenario look implausibly cost-effective.

**v3 resolution:** `opc_mortality_annual = 0.045` → 5y OS ≈ 79%. Excess survivor mortality (`opc_survivor_excess_mortality = 0.01`) applies after 5y for late effects. Stage-specific survival is deferred (Tier B).

## 6. Latency was a hard cutoff, not a distribution (resolved in v3)

Original `MIN_LATENCY_FOR_CANCER <- 10` was a sharp threshold: 0% at year 9.99, full hazard at year 10.01. This means small changes to the threshold could fully determine policy outputs (e.g., set to 15 and no Veteran vaccinated at 40 can develop cancer in a 30-year horizon).

**v3 resolution:** Weibull sampling at persistence onset gives a smooth distribution.

## 7. HPV treated as a single undifferentiated entity (documentation issue)

HPV16 alone causes ~90% of HPV+ OPC. Code parameters labeled as "HPV" actually need to refer to oncogenic-types-that-drive-OPC, dominated by HPV16. Vaccine efficacy against HPV16 acquisition specifically is what matters for the OPC pathway.

**Recommended documentation note:** Every parameter sourced for Excel should specify whether it refers to HPV16, oncogenic types, or all HPV — and oral-HPV-specific values should be preferred over genital.

## 8. Oral vs. genital HPV not distinguished (documentation issue)

Reviewer 1 flagged this. Oral HPV has different acquisition routes (oral sex, deep kissing), clearance kinetics, and sex distribution than genital. No structural change needed if the model is implicitly oral throughout, but every Excel parameter should be sourced from oral-HPV studies (HIM Study Kreimer 2013, NHANES oral rinse data) — not cervical or genital.

## 9. Pre-existing infection seeding (partially resolved in v3)

Original: 40% prevalence with uniform 1–7y duration. v3: sex-stratified prevalence keyed to NHANES (`baseline_prev_male = 0.06`, `baseline_prev_female = 0.011`), right-skewed duration via geometric distribution, and prevalent infections past the threshold are placed in `persistent` with already-accrued time. Still needs final age-stratified prevalence values.

## 10. Cancer survivor state — biological meaning unclear (resolved in v3)

Original: separate `cancer_survivor` state after 5y in `cancer_active`. Issues: not in grant's 5-state model; "5 years in active treatment" isn't the standard survivorship definition; survivors got background mortality (incorrect — they have excess mortality from second primaries, treatment late effects, recurrence).

**v3 resolution:** No separate state. Within the `cancer` state, agents past `CANCER_SURVIVOR_THRESHOLD = 5` get lower annual costs (`COST_ANNUAL_SURVIVOR`) and reduced excess mortality (`opc_survivor_excess_mortality`).

## 11. Within-year event ordering (documented in v3)

Order each year: aging → vaccination → acquisition → clearance/persistence → persistent→cancer transition → annual cancer costs → mortality → QALY accumulation → state snapshot. Sub-annual time steps would resolve any within-year conflation; for an annual model, this order is documented.

## 12. Re-infection biology questionable (resolved in v3)

Original `prev_infection_multiplier = 1.2` on cancer progression had no clear literature anchor. Re-infection in HPV typically refers to a different type; there's no biological reason a second HPV16 infection would progress faster. **v3:** removed.

---

# Part 2: Excel ↔ R Code Parameter Mapping

Reference: `2026_05_05_parameters.xlsx` vs. v3 simulation code.

Status key: ✅ implemented · ⚠️ partially / approximated · ❌ not in code · 🆕 added in v3

## Sheet 1 — Pre-existing Infection

| Excel parameter | v3 code variable | Current value | Status | Notes |
|---|---|---|---|---|
| Prevalence of any HPV at sim start | `baseline_prev_male`, `baseline_prev_female` | 0.06 / 0.011 (placeholder) | 🆕 | Sex-stratified per NHANES (Gillison). Excel calls for "Range, by age" — still need age-stratified values. |
| Of currently infected, fraction already persistent | derived from `persistence_threshold_years` + duration draw | computed | 🆕 | Agents whose seeded `infection_duration` is ≥ threshold start in `persistent` with accrued time. |
| Duration distribution of pre-existing infections | `init_duration_geom_p` | 0.4 (mean ~1.5y) | 🆕 | Right-skewed via geometric. Could swap for empirical distribution if available. |

## Sheet 2 — Acquisition

| Excel parameter | v3 code variable | Current value | Status | Notes |
|---|---|---|---|---|
| Annual incidence of incident oral oncogenic HPV | `p_acquisition_male`, `p_acquisition_female` | 0.04 / 0.01 (placeholder) | 🆕 | Sex-stratified. HIM Study Kreimer for men; NHANES for women. Still need age stratification. |
| Smoking RR on acquisition | `smoking_acquisition_RR` | 1.5 | ✅ | |
| Per-step probability conversion (annual to quarterly) | — | — | ❌ | Annual time steps retained; reviewer concern noted. |

## Sheet 3 — Clearance

| Excel parameter | v3 code variable | Current value | Status | Notes |
|---|---|---|---|---|
| Median time to clearance | derived | ~1.5y at base rates | — | Emergent from per-duration probabilities. |
| Annual clearance prob (years 0–2) | `p_clearance_short` | 0.60 | ✅ | |
| Annual clearance prob (years 2+, infected) | `p_clearance_medium` | 0.30 | ✅ | Applies before persistence transition fires. |
| Annual clearance prob (persistent state) | `p_clearance_persistent` | 0.05 | 🆕 | Rare reversion from persistent → healthy. |
| Smoking RR on clearance | `smoking_clearance_RR` | 0.7 (< 1) | 🆕 | Smoking reduces clearance. |
| Age effect on clearance | — | — | ❌ | Could be added by making clearance probs age-dependent. |

## Sheet 4 — Persistence Threshold

| Excel parameter | v3 code variable | Current value | Status | Notes |
|---|---|---|---|---|
| Threshold months of continuous infection defining persistent | `persistence_threshold_years` | 2 years | 🆕 | Standard literature definition. Excel uses months — keep in years unless sub-annual time steps adopted. |
| Stochastic persistence at threshold | `p_persistence_given_long_inf` | 1.0 | 🆕 | If still infected at threshold, transition deterministically; set < 1 for stochastic variant. |

## Sheet 5 — Latency to OPC

| Excel parameter | v3 code variable | Current value | Status | Notes |
|---|---|---|---|---|
| Mean / median time from persistent infection to OPC diagnosis | derived from Weibull(shape, scale) | mean ≈ 17.9y | 🆕 | |
| Minimum time in Persistent before OPC is possible | implicit in Weibull tail | — | 🆕 | No hard cutoff; Weibull naturally suppresses early progression. |
| Distribution shape | Weibull | shape = 3 | 🆕 | Right-skewed, peaks around 15–20y as Nature Comms paper suggests. |
| Weibull shape parameter (k) | `weibull_shape` | 3.0 (placeholder) | 🆕 | Needs Nature Comms anchor. |
| Weibull scale parameter (λ) | `weibull_scale` | 20.0 (placeholder) | 🆕 | Needs Nature Comms anchor. |
| Smoking RR on progression | `smoking_progression_RR` | 2.0 | ✅ | Applied as scale divisor. |
| Alcohol RR on progression | `alcohol_progression_RR` | 1.5 | 🆕 | |
| Smoking × alcohol interaction | `smoking_alcohol_synergy` | 1.3 | 🆕 | Multiplicative on top of individual RRs. |
| Sex effect on progression | `female_progression_RR` | 0.5 | 🆕 | Women progress slower; reflects sex disparity in OPC. |

## Sheet 6 — OPC Outcomes

| Excel parameter | v3 code variable | Current value | Status | Notes |
|---|---|---|---|---|
| Distribution of stage at OPC diagnosis | — | — | ❌ | Tier B refinement. |
| 5-year HPV+ OPC survival (overall) | implied from `opc_mortality_annual` | ~79% | 🆕 | Calibrated to Ang 2010 NEJM. |
| 5-year HPV+ OPC survival by stage | — | — | ❌ | Requires stage. |
| Annual mortality during active cancer | `opc_mortality_annual` | 0.045 | 🆕 | |
| Mortality of cancer survivors (post-5y) | `opc_survivor_excess_mortality` | 0.01 | 🆕 | Excess vs. background. |
| Treatment effect | — | — | ❌ | |

## Sheet 7 — Vaccine Efficacy

| Excel parameter | v3 code variable | Current value | Status | Notes |
|---|---|---|---|---|
| Vaccine efficacy against incident HPV16/18 acquisition | `VE_acquisition` | 0.90 (placeholder) | 🆕 | Named parameter; `p_infection_vax` derived as `p_acquisition × (1 − VE_acquisition)`. |
| Vaccine efficacy against persistent infection | `VE_persistence` | 0.85 (placeholder) | 🆕 | Acts at acute→persistent transition per grant. |
| Vaccine efficacy if pre-existing infection at vaccination | implicitly zero | — | ⚠️ | Code lets infected agents get vaccinated but vaccination only affects future acquisition/persistence transitions. Made explicit in design. |
| Doses required for full efficacy | — | — | ❌ | Tier C. |
| Single-dose efficacy | — | — | ❌ | Costa Rica trial data available; deferrable. |
| Time to protection after vaccination | — | instantaneous | ❌ | |
| Annual waning of vaccine protection | — | — | ❌ | Tier C. |
| Age-specific efficacy modifier | — | — | ❌ | Tier C. |

## Sheet 8 — Background Mortality

| Excel parameter | v3 code variable | Current value | Status | Notes |
|---|---|---|---|---|
| All-cause mortality by age | `get_mortality_rate_vec()` | piecewise placeholder | ⚠️ | Function accepts sex argument but currently returns sex-independent values. Replace with VA or SSA life table. |
| Smoking adjustment | `smoking_mortality_RR` | 2.0 | 🆕 | |
| Race/ethnicity adjustment | — | — | ❌ | Race not yet an agent attribute. |

## Sheet 9 (new) — Vaccination Uptake

| Parameter | v3 code variable | Current value | Notes |
|---|---|---|---|
| Annual probability of vaccination if eligible | `p_vaccinate` | 0.15 (placeholder) | Behavioral counterpart to Sheet 7 efficacy. Should come from Aim 1 empirical estimates. |

## Sheet 10 (new) — Costs & Economics

| Parameter | v3 code variable | Current value | Notes |
|---|---|---|---|
| Full vaccine series cost | `vaccine_cost` | $600 | |
| OPC diagnostic workup (one-time at dx) | `COST_OPC_DIAGNOSIS` | $25,000 | Separated from annual treatment to fix v2 double-counting. |
| Annual active cancer treatment (yrs 1–5) | `COST_ANNUAL_CANCER_TX` | $30,000 | |
| Annual survivor follow-up (yrs 5+) | `COST_ANNUAL_SURVIVOR` | $2,000 | |
| Discount rate | `discount_rate` | 0.03 | Applied to both costs and QALYs in v3. |
| QALY: healthy | `QALY_HEALTHY` | 1.00 | |
| QALY: infected | `QALY_INFECTED` | 0.98 | Largely asymptomatic. |
| QALY: persistent | `QALY_PERSISTENT` | 0.98 | Asymptomatic. |
| QALY: cancer active | `QALY_CANCER_ACTIVE` | 0.65 | Acute morbidity + treatment. |
| QALY: cancer survivor | `QALY_CANCER_SURVIVOR` | 0.85 | Late effects (swallowing, xerostomia). |
| WTP thresholds for CEA | — | — | Convention: $50K / $100K / $150K per QALY. |

## Sheet 11 (new) — Simulation Settings

| Parameter | v3 code variable | Current value | Notes |
|---|---|---|---|
| Cohort size | `num_agents` | 100,000 | Reviewers wanted ≥500K; runtime will dictate. |
| Simulation horizon | `sim_years` | 75 | |
| Starting age range | `age_min`, `age_max` | 26, 45 | Now aligned with Aim 2 narrative. |
| Maximum age | `max_age` | 99 | |
| Policy lever | `vaccination_age_caps` | {26, 30, 35, 40, 45} | |
| Proportion male | `prop_male` | 0.88 (placeholder) | From VA demographic data. |
| Proportion smoker | `prop_smoker` | 0.27 (placeholder) | Veteran smoking prevalence. |
| Proportion heavy alcohol | `prop_heavy_alcohol` | 0.15 (placeholder) | |

## Parameters now in code that still need Excel rows added

The following v3 additions should get rows in the appropriate Excel sheets so the spreadsheet remains the single source of truth:

- Sheet 1: separate prevalence by sex; right-skewed initial duration parameter
- Sheet 3: clearance from persistent state; smoking RR on clearance
- Sheet 4: stochastic persistence parameter
- Sheet 5: Weibull shape and scale; sex effect on progression
- Sheet 6: survivor excess mortality; survivor threshold definition
- Sheet 7: VE against persistence (distinct from acquisition)
- Sheet 8: smoking mortality RR
- Sheets 9–11: new sheets for uptake, costs/QALYs, simulation settings

---

# Priority Resolution Roadmap

Bundled so that fixes don't require rework. **Tier A is largely resolved in v3**; Tiers B and C remain.

## Tier A — fix before any results are trusted (✓ resolved in v3)
- ✓ A1. Distinct `persistent` state; cancer progression routed through it
- ✓ A2. Weibull time-to-event sampling at persistence onset (replaces constant-hazard)
- ✓ A3. `opc_mortality` recalibrated to ~80% 5-year OS (Ang 2010)
- ✓ A4. `sex` and `alcohol_heavy` added as agent attributes; alcohol RR on progression
- ✓ A5. `baseline_prev_prob` reduced to NHANES-anchored values

## Tier B — important for grant fidelity (open)
- ✓ B1. Vaccination acts on acute→persistent transition (resolved in v3)
- ✓ B2. MSM removed
- B3. Document that "HPV" in the model means oral HPV16-dominant oncogenic types; source all parameters from oral-HPV literature
- ✓ B4. Survivor state cleaned up (resolved in v3)
- B5. Add age-stratified prevalence and acquisition (currently sex-stratified only)

## Tier C — refinement (deferrable to Merit)
- C1. Sub-annual time step (reviewer concern) — document annual-step approximation explicitly if deferred
- C2. VISN attribute and stratified outputs (if needed for grant deliverables)
- C3. Stage at diagnosis and stage-specific survival
- C4. Vaccine waning, single-dose efficacy, time-to-protection, age-specific efficacy
- C5. Race/ethnicity as agent attribute with associated mortality adjustments
- C6. Replace placeholder `get_mortality_rate_vec()` with real VA or SSA life-table lookup

## Outstanding scope decisions
- Cohort interpretation: closed cohort (current) vs. steady-state with replenishment of new young Veterans
- Whether VISN-stratified outputs are required for the pilot or can wait for Merit
- Whether to include alcohol despite no direct measurement in some VA cohorts (proxy via ICD codes or AUDIT-C scores)