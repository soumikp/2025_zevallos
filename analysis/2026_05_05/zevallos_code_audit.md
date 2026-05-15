# Zevallos VA Pilot — Code Audit (2026_02_16 version)

Audit of `2026_02_16_simulator.R` and `2026_02_16_helper.R` against the parameter inventory in `zevallos_model_spec_and_parameters.md`.

Conventions:
- ✅ implemented and reasonable
- 🟡 implemented but a placeholder, hardcoded, or out of step with the Research Plan
- ❌ not present at all
- 🔴 implemented in a way that's mechanically/scientifically incorrect

---

## TL;DR

The current code is a working scaffold but has substantially less structure than the Research Plan describes. The biggest deltas:

1. **There is no separate `Persistent Infection` state.** The Research Plan's 5-state model (Healthy → Infection → Persistent → OPC → Death) is implemented as a 4-state model with a duration counter standing in for persistence (`Healthy → Infected → Cancer_active → Cancer_survivor → Dead`). Persistence is encoded as `infection_duration > 10 years`.
2. **The cohort is undifferentiated.** No sex, no race, no VISN, no rurality, no alcohol, no comorbidity, no burn pit. This is the single most consequential omission for Veteran-specific modeling — OPC incidence in men is ~5× that in women, and the entire Veteran-specific premise is sex+smoking+VISN heterogeneity.
3. **There is one Monte Carlo realization per scenario, not 1,000.** No simulation intervals, no PSA, no uncertainty bands. The grant text says "1,000 Monte Carlo iterations" — that loop is not in the code.
4. **The vaccination policy lever isn't really a policy lever.** `age_cap` controls how many *years* an agent gets to roll a 15%/year vaccination chance, which creates 76% lifetime coverage at cap=26 vs ~99% at cap=45. That's not "expanded policy" — that's "more shots at the dice over more years." See structural issue #4 below.
5. **The latency mechanism is brittle.** The 10-year minimum is enforced by checking continuous duration, but `infection_duration` resets to 0 on clearance. So an agent who clears at year 9 and is reinfected at year 10 has the clock reset. Biologically the 10–30 year latency is from initial persistent oncogenic infection to cancer, not from "the most recent uninterrupted infection episode."

These are tractable. Several are one-evening fixes once we agree on the structural choices. Sections below give a row-by-row map.

---

## Architecture as actually implemented

**States (helper.R:39):** `healthy`, `infected`, `cancer_active`, `cancer_survivor`, `dead`. Note `cancer_survivor` is in the code but not in the Research Plan; `Persistent Infection` is in the Research Plan but not in the code.

**Transitions actually allowed:**
```
healthy → infected   (via p_infection_unvax / p_infection_vax)
infected → healthy   (via clearance, with num_prev_infections incremented)
infected → cancer_active   (via p_persistence_to_opc, only if infection_duration > 10)
cancer_active → cancer_survivor   (deterministic at cancer_duration > 5)
* → dead   (via background mortality + opc_mortality for cancer_active)
```

There is **no** `persistent` state and **no** way to be "in persistence and clear back to infected/healthy."

**Time mechanics (simulator.R:9–14):**
| Element | Code | Research Plan | Reviewer-flagged? |
|---|---|---|---|
| `num_agents` | 100,000 | 10,000 | yes — code has already scaled up; good |
| `sim_years` | 100 | 30 | code is more conservative; fine |
| age range at entry | 18–65 (uniform) | 26–45 cohort | **mismatch** |
| time step | 1 year | 1 year | yes — needs to become quarterly |
| MC iterations | 1 (no loop) | 1,000 | **major gap** |
| seed | single, set in simulator (`2026`) | not specified | OK |
| burn-in | implicit via prevalent infection seeding | not specified | OK-ish |

The age range at entry is a real concern. The grant is about Veterans 26–45; the code samples 18–65 uniformly. Either the cohort generator needs to match the grant's target population, or there needs to be a clear documented reason for the broader age range (e.g., to model lifetime risk including pre-26 vaccination).

---

## Row-by-row audit

### Cohort initialization (Section 2.1 of inventory)

| # | Parameter | Status | Notes |
|---|---|---|---|
| C1 | Age distribution | 🟡 | uniform 18–65 (helper.R:36); should be 26–45 with empirical distribution from Aim 1 |
| C2 | Sex | ❌ | **not in agent table** |
| C3 | Race/ethnicity | ❌ | not in agent table |
| C4 | VISN | ❌ | not in agent table — blocks all VISN-level outputs the grant promises |
| C5 | Rurality (RUCA) | ❌ | |
| C6 | SPAR | ❌ | |
| C7 | Smoking status | 🟡 | binary `smoker` 30% (helper.R:45); should be never/former/current with age and sex variation |
| C8 | Pack-years | ❌ | |
| C9 | Alcohol use | ❌ | |
| C10 | Comorbidity burden | ❌ | |
| C11 | Service connection % | ❌ | |
| C12 | Burn pit / military exposure | ❌ | reviewer-flagged |
| C13 | Baseline vaccination status | 🟡 | implicit — all agents start `vaccinated = FALSE` (helper.R:38). Should be sampled from Aim 1 prevalence. |
| C14 | Vaccination dose count | ❌ | binary, not by dose count |
| C15 | Age at first dose | 🟡 | tracked as `vaccination_year` post hoc; not initialized |
| C16 | **Pre-existing oral HPV prevalence** | 🟡 | seeded at 40% with duration 1–7 yrs (helper.R:62–74). The 40% is too high (NHANES total oral HPV ~7% in men, ~1% in women, oncogenic types ~3.5%/0.6%). Document the rationale or reduce. |
| C17 | Pre-existing persistent infection | ❌ | no separate persistent state |
| C18 | Prevalent OPC at sim start | ❌ | small effect for 26–45 cohort, fine to leave |

**Ad hoc covariates in the code that aren't in the inventory:**
- `msm` (helper.R:46): 10% prevalence, fixed. Reviewer 2 explicitly flagged measurability of MSM in CDW. If you keep this, you need a CDW phenotype. Otherwise drop and let the unstructured residual variance absorb it.
- `vaccine_hesitant` (helper.R:47): 40%, fixed, multiplies vaccination probability by 0.3. Fine as a simple lever; should be calibrated to Aim 1 vaccination prevalence rather than chosen.

### Transitions (Section 2.2)

#### Acquisition: Healthy → Infection

| # | Parameter | Status | Notes |
|---|---|---|---|
| T1 | Baseline acquisition rate | 🟡 | `p_infection_unvax = 0.05/yr` (simulator.R:21), age-flat. Should vary by age (peak in young adults) and sex. |
| T2 | Smoking RR on acquisition | 🟡 | `smoking_infection_multiplier = 1.5` (simulator.R:30). Literature is closer to ~1.3; defensible as starting point. |
| T3 | Sexual behavior multiplier | 🟡 | partially captured by `msm_infection_multiplier = 2.0`; otherwise absent |
| T4 | Type-specific weighting | ❌ | model treats HPV as a single entity |

#### Clearance: Infection → Healthy

The code (helper.R:196–207) implements a **duration-stratified clearance probability**:
- duration ≤ 2 years: 50% annual clearance
- duration 2–5 years: 50% × 0.8 = 40% annual clearance
- duration > 5 years: **5%** annual clearance ("sticky persistence")

| # | Parameter | Status | Notes |
|---|---|---|---|
| T5 | Baseline clearance | 🟡 | `p_clearance_base = 0.5` is reasonable for short-duration infections; the >5-year branch is effectively the persistence mechanism |
| T6 | Smoking RR on clearance | ❌ | not implemented; smoking only affects acquisition and progression |
| T7 | Age effect on clearance | 🔴 | absent; clearance is a function of duration only, not age. Real clearance declines with age. |

#### "Persistence" (implicit)

There is no explicit Persistent state. The combination of (a) duration-stratified clearance making clearance hard after 5 years and (b) the `MIN_LATENCY_FOR_CANCER = 10` gate on cancer transition together approximate persistence. But:

- The same `infected` state covers both acute and persistent infection.
- Stratifications that should differ between acute and persistent (clearance dynamics, mortality, OPC progression) all key off `infection_duration` rather than state.
- An agent who clears at year 9 and reinfects at year 10 has `infection_duration` reset to 0; they then need 10+ more years to be a cancer candidate again. (helper.R:178, 253)

| # | Parameter | Status | Notes |
|---|---|---|---|
| T8 | Persistence threshold | 🟡 | implicit at 5 years (when clearance probability drops to 5%) and 10 years (when cancer becomes possible). Two thresholds are inconsistent — pick one and document. |
| T9 | Smoking RR on persistence | 🔴 | the `smoking_persistence_multiplier = 2.0` (simulator.R:31) is named "persistence" but is actually applied to the persistence→cancer transition (helper.R:224), not to persistence itself |
| T10 | Comorbidity/immune effect | ❌ | |

#### Persistence → OPC ★ (the latency problem)

| # | Parameter | Status | Notes |
|---|---|---|---|
| T11 | **Sojourn time in Persistent** | 🔴 | implemented as `p_persistence_to_opc = 0.05/yr` after a 10-year minimum (simulator.R:26, helper.R:218). This is a memoryless geometric process, not a dwell-time distribution. **This is the single highest-priority structural fix.** |
| T12 | Minimum sojourn | ✅ | `MIN_LATENCY_FOR_CANCER = 10` (helper.R:9). Defensible value; document source. |
| T13 | Smoking RR on progression | ✅ | `smoking_persistence_multiplier = 2.0` (mis-named) |
| T14 | Alcohol RR on progression | ❌ | |
| T15 | Burn pit RR on progression | ❌ | reviewer-flagged |
| T16 | Sex-specific progression | ❌ | because no sex variable |
| T17 | Type-specific progression | ❌ | |

The `prev_infection_multiplier = 1.2` applied to cancer probability (helper.R:225) is an interesting addition — it captures the idea that prior cleared infections add some risk. It's also not in the inventory. Worth keeping if you can find a literature anchor; flag it as an assumption otherwise.

#### Background and OPC mortality

| # | Parameter | Status | Notes |
|---|---|---|---|
| T18 | All-cause mortality | 🟡 | hardcoded function `get_mortality_rate_vec` (helper.R:15–28) with a piecewise age structure. Not by sex or race. Replace with VA actuarial tables. |
| T19 | Comorbidity mortality multiplier | ❌ | |
| T20 | Smoking mortality multiplier | ❌ | |
| T21 | OPC stage at diagnosis | ❌ | model assumes all OPC behaves the same |
| T22 | OPC-specific mortality | 🟡 | `opc_mortality = 0.3/yr` (simulator.R:27) added to background for `cancer_active`. Implies 5-yr survival ~17% which is too low for HPV+ OPC (real ~70–80%). **Fix.** |
| T23 | Treatment effect | ❌ | not modeled; treatment is implicit in the `cancer_active → cancer_survivor` transition at year 5 |

**Cancer dynamics specific issue:** survivors (helper.R:282) get full background mortality only, no excess mortality from prior cancer. That's defensible for HPV+ OPC but worth documenting. Also, the `cancer_active → cancer_survivor` transition is deterministic at year 5 (helper.R:274) — there's no probabilistic treatment effect, no recurrence, no late-effects mortality. This is a simplification the reviewers haven't flagged but a Merit reviewer eventually will.

### Vaccination (Section 2.3)

| # | Parameter | Status | Notes |
|---|---|---|---|
| V1 | VE vs acquisition | 🔴 | encoded indirectly as `p_infection_vax / p_infection_unvax = 0.002 / 0.05 = 96%`. The named `vaccine_efficacy = 0.9` parameter (simulator.R:23) is **declared but never used**. Refactor so VE is a single multiplier on per-step infection hazard. |
| V2 | VE vs persistence | ❌ | no separate effect on persistence dynamics |
| V3 | Pre-existing infection at vax | 🟡 | partial: vaccination is allowed regardless of state (helper.R:131), but `p_infection_vax` only fires when `health_state == "healthy"` (helper.R:164), so an agent vaccinated while infected gets no immediate benefit. After clearance they get `p_infection_vax`. There is no type-specific blocking — vaccinating a currently-infected agent against a strain they don't have isn't modeled. **Reviewer-flagged.** |
| V4 | Time-to-protection | ❌ | instantaneous; small effect over 30+ years |
| V5 | Waning | ❌ | |
| V6 | Doses required | ❌ | binary vaccinated yes/no |
| V7 | Single-dose efficacy | ❌ | |
| V8 | Adherence (series completion) | ❌ | reviewer-flagged |
| V9 | Coverage achievable in expansion | 🔴 | see structural issue #4 below |
| V10 | Catch-up uptake ramp | ❌ | |

### Effect modifiers (Section 2.4)

The matrix that's actually implemented:

| Covariate | Acquisition | Clearance | Persistence | Progression | Mortality |
|---|---|---|---|---|---|
| Sex | ❌ | ❌ | ❌ | ❌ | ❌ |
| Age | ❌ | 🟡 (via duration, not age) | — | ❌ | ✅ |
| Smoking | ✅ T2 | ❌ | ❌ | ✅ T13 | ❌ |
| Alcohol | ❌ | ❌ | ❌ | ❌ | ❌ |
| Burn pit | ❌ | ❌ | ❌ | ❌ | ❌ |
| Comorbidity | ❌ | ❌ | ❌ | ❌ | ❌ |
| Vaccination | ✅ V1 | ❌ | ❌ | ❌ | ❌ |
| Pre-existing infection | gates V1 partially | ❌ | ❌ | 🟡 (via num_prev_infections) | ❌ |
| HPV type | ❌ | ❌ | ❌ | ❌ | ❌ |
| MSM | ✅ | ❌ | ❌ | ❌ | ❌ |

### Simulation control (Section 2.5)

| # | Parameter | Status | Notes |
|---|---|---|---|
| S1 | `n_agents` | ✅ | 100K |
| S2 | `time_step` | 🟡 | annual; reviewer wants quarterly |
| S3 | `horizon` | 🟡 | 100 yr; Research Plan said 30 |
| S4 | `burn_in` | 🟡 | implicit via prevalent infection seeding; not formal |
| S5 | `mc_iterations` | 🔴 | **single run per scenario** |
| S6 | `seed` | ✅ | set once at simulator.R:6 |
| S7 | `start_calendar_year` | ❌ | not represented; everything is in sim-year units |
| S8 | scenarios | ✅ | {26, 30, 35, 40, 45} per simulator.R:14 |

### Calibration targets (Section 2.6)

| # | Target | Status |
|---|---|---|
| K1–K8 | All targets | ❌ — no calibration loop, no benchmarks loaded, no comparison logic in the codebase |

### Outputs (Section 2.7)

| # | Output | Status |
|---|---|---|
| O1 | Cumulative HPV infections | 🟡 incident counts by year only; no cohort/VISN stratification |
| O2 | Cumulative persistent infections | ❌ no persistent state to count |
| O3 | Cumulative OPC | 🟡 by year; no VISN |
| O4 | OPC deaths | 🟡 |
| O5 | Vaccinations administered | ✅ |
| O6 | NNV | ❌ |
| O7 | Life-years gained | ❌ |
| O8 | Time series | ✅ in plots |

---

## Critical structural issues

### 1. No Persistent state

The 5-state model in the grant is implemented as a 4-state model. The `Persistent` state is encoded as a duration condition on the `Infected` state, with two implicit thresholds (5 years for "sticky" clearance, 10 years for cancer eligibility).

Recommended fix: **make Persistent an explicit state.** Transition `Infected → Persistent` at duration 12 or 24 months (defensible per literature). In Persistent, clearance probability is low or zero; the dwell-time distribution governs eventual transition to OPC. This:
- Aligns the code with the grant
- Lets you cleanly attach different parameters (clearance, mortality multipliers) to each state
- Makes the dwell-time fix in #2 below natural

### 2. Latency is memoryless geometric, not a dwell-time distribution

`p_persistence_to_opc = 0.05` per year after a 10-year wait means the time-to-cancer (conditional on reaching the wait) is geometric with mean 20 years and a long tail. There's no biological reason for this shape — it's just the consequence of using a constant per-step probability. Reviewer 1 specifically flagged this.

Recommended fix: replace the per-step probability with a draw at entry to Persistent: `T_progression ~ Weibull(shape=k, scale=λ) | covariates`. Schedule the OPC transition at that time. Calibrate `k`, `λ` to match observed age-incidence curves of HPV+ OPC.

### 3. Duration counter resets on clearance

`infection_duration = 0` on clearance (helper.R:253) means an agent who clears at year 9 and reinfects at year 10 must accumulate 10 more years before becoming cancer-eligible. This is biologically incorrect; the relevant clock is cumulative time at risk under persistent oncogenic infection, not consecutive time in the current episode.

Recommended fix: track `cumulative_persistent_duration` separately, or make Persistent absorbing (no clearance from Persistent), or define "persistence" by total years infected with the same type. The cleanest fix is making Persistent absorbing once entered, which matches biological understanding for the 10–30 year latency cases.

### 4. The vaccination policy lever is years-of-eligibility, not coverage

`age_cap` controls until what age an agent can roll the 15%/year vaccination dice. Starting at age 18:
- `age_cap = 26`: 9 eligibility-years → ~76% lifetime coverage (with `p_vaccinate = 0.15`)
- `age_cap = 45`: 28 eligibility-years → ~99% lifetime coverage

So most of the difference between scenarios is just "more years to roll the dice," not "different policy." A real expanded-eligibility scenario should specify catch-up coverage in newly eligible cohorts — i.e., what fraction of newly eligible Veterans actually get vaccinated, with realistic ramp-up curves. This also matters because the reviewers explicitly questioned whether expanded eligibility produces real-world coverage gains.

Recommended fix: replace `p_vaccinate` per year with a coverage target per scenario, achieved over a defined ramp-up window. This decouples policy reach from "how many years did the agent loiter under the cap."

### 5. No Monte Carlo iteration

One realization per scenario. The Research Plan promises 1,000 MC iterations with 95% simulation intervals; the code doesn't have that loop.

Recommended fix: wrap `run_simulation` in an outer loop over `n_iter`, vary the seed per iteration, store yearly_stats per iteration, summarize as mean + 95% bands at the end. With 100K agents and a 100-year horizon, 1,000 iterations will need either parallelization or a smaller agent count or a shorter horizon (or all three). 100 iterations at 100K agents is a reasonable starting point for development; scale toward 1,000 for final.

### 6. No sex stratification

Already noted but worth restating. OPC incidence in men is several times that in women. The grant's premise is Veteran-specific risk concentrated in older men. A model without sex cannot deliver Veteran-specific projections — it delivers Veteran-blind projections.

Recommended fix: add `sex` to the agent table, sex-stratify acquisition, clearance (modest), persistence, progression, and OPC mortality. Initialize sex from Aim 1's joint distribution.

### 7. Vaccine efficacy is parameterized indirectly and inconsistently

`vaccine_efficacy = 0.9` is declared and never used. The actual VE is implicit in `p_infection_vax / p_infection_unvax = 0.04` (i.e., 96% reduction). Pick one parameterization and refactor. The cleanest is:

```
p_infection(agent) = p_baseline(age, sex) * 
                     (1 - vaccine_efficacy * I[vaccinated & not_pre_existing]) *
                     prod(risk_multipliers)
```

This makes VE a single, citable number with a sensitivity range, and cleanly handles the pre-existing-infection case.

---

## What to keep

A few things in the code are good and shouldn't be lost in a refactor:

- The data.table vectorization pattern. Keep.
- Pre-existing infection seeding at sim start (even if 40% is high). Keep the mechanism, recalibrate the rate.
- The cancer_survivor state. Not in the Research Plan but biologically sensible. Keep, refine survival.
- The duration-stratified clearance shape (high clearance early, sticky later). The shape is right; it should live on a properly-modeled Persistent state.
- The `prev_infection_multiplier`. Interesting idea, captures cumulative HPV exposure. Keep but flag as an assumption needing literature support.
- Vectorized cohort generation. Keep.
- Cost tracking infrastructure. Park, don't delete; will be needed for the Merit.

---

## Recommended fix sequence

In dependency order (each builds on the previous):

1. **Add sex** to the agent table and sex-stratify acquisition, persistence, progression, OPC mortality. Initialize from Aim 1 marginals (placeholder values now; real values when Aim 1 numbers come in). *Why first:* unblocks every downstream parameter, and makes OPC numbers plausible.
2. **Add an explicit Persistent state.** Transition Infected → Persistent at 12 or 24 months. Persistent is absorbing relative to clearance (or has very low clearance). *Why second:* needed before the dwell-time fix.
3. **Replace the geometric latency with a Weibull dwell time** drawn at entry to Persistent, modulated by smoking/age/sex. *Why third:* the latency is the dominant determinant of expansion-scenario differences, especially at the older age caps.
4. **Refactor vaccination policy to coverage-based, not years-based.** Define per-scenario coverage targets and ramp curves. *Why fourth:* otherwise the scenarios don't reflect policy.
5. **Wrap in an MC loop, 100→1,000 iterations.** Add 95% simulation intervals to all outputs. *Why fifth:* now changes are statistically interpretable.
6. **Move to quarterly time steps for Healthy ↔ Infection.** Convert annual probabilities to quarterly hazards properly: `p_q = 1 − (1 − p_a)^(1/4)`. *Why sixth:* mostly mechanical once the structural fixes are in; kept here to avoid having to redo it after each prior fix.
7. **Add VISN, rurality, race** to the agent table and stratified outputs. *Why seventh:* it's mostly bookkeeping but only useful once #1–5 produce reliable per-stratum estimates.
8. **Calibration loop.** Compare model outputs against K1–K8 targets, tune parameters within plausible ranges. This is its own multi-week effort.

Cohort age range (18–65 vs 26–45) is a separate decision — flag it for the team meeting before fixing.

---

## Smaller things worth fixing

- `vaccine_efficacy = 0.9` declared, never used (simulator.R:23). Remove or use.
- `MSM` rate of 10% (helper.R:46) is high vs. literature (~3–5% in general male population, lower in Veterans). And it's not clear MSM can be reliably extracted from CDW — Reviewer 2 flagged this.
- `baseline_prev_prob = 0.40` for pre-existing oral HPV (helper.R:64) is much higher than NHANES (~7% men, ~1% women for any oral HPV; ~3.5%/0.6% for oncogenic types). Recalibrate.
- 100-year sim horizon vs. 30-year Research Plan (simulator.R:10). Reconcile.
- Discount logic baked into the cost lines (simulator.R:17, helper.R:101) — fine to leave for now since costs are out of scope, but the structure is in place.
- Single fixed seed across all scenarios — every scenario uses identical population realizations, which is actually a feature for variance reduction (paired comparisons) but should be documented.
- `num_prev_infections` is a good idea but the multiplier (1.2) needs a source.
- Background mortality function (helper.R:15–28) is hand-shaped, not from any cited table. Replace with VA actuarial.
