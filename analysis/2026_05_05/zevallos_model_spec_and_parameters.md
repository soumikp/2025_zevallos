# Zevallos VA Pilot — Microsimulation Model Spec & Parameter Inventory

**Purpose:** Granular description of what the Aim 2 microsimulation has to specify, organized as a checklist. Each parameter has a name, type, stratification dimensions, likely source, and notes flagging reviewer concerns or pathology issues.

**Scope note:** This document is built from the Research Plan and standard HPV/OPC microsimulation practice (CISNET-family models, HPVsim, Kim 2021 *PLoS Med*, Laprise 2020 *Ann Intern Med*, Matthijsse 2015). I have not read the actual simulator code yet. Use this as the canonical "what the model needs to specify"; once we map it against the code, you'll see exactly what's already implemented, what's a stub, and what's missing.

**Out of scope (parked for Merit):** QALY weights, cost parameters, ICER calculations.

---

## 1. Conceptual model

### What an agent is

A simulated Veteran. Attributes that travel with the agent for life:

| Attribute | Type | Source | Notes |
|---|---|---|---|
| `id` | integer | — | unique |
| `sex` | M/F | Aim 1 | OPC risk sharply higher in M |
| `race_ethnicity` | categorical | Aim 1 | OPC incidence varies by race; matters for VA |
| `birth_year` / `age_at_entry` | integer | Aim 1 | drives everything time-related |
| `visn` | categorical (1–22) | Aim 1 | preserved end-to-end for VISN-level outputs |
| `rurality` | RUCA category | Aim 1 | urban / large rural / small rural / isolated |
| `spar` | continuous | Aim 1 | spatial access ratio at census tract |
| `smoking_status` | never/former/current | Aim 1 | effect modifier on persistence and progression |
| `pack_years` (optional) | continuous | Aim 1 | dose-response on OPC risk |
| `alcohol_use` | none/moderate/heavy | Aim 1 | effect modifier, mostly synergistic with smoking |
| `comorbidity_index` | Charlson or Elixhauser | Aim 1 | proxy for immune competence |
| `service_connection_pct` | 0–100 | Aim 1 | proxy for healthcare engagement |
| `burn_pit_exposure` | yes/no/unknown | Aim 1 (PACT/Z77.*) | reviewer-flagged; sensitivity range needed |
| `vax_status_at_entry` | unvax / partial / complete | Aim 1 | dose count + age at first dose |
| `prior_oral_hpv` | none / cleared / current / persistent | external | **reviewer-flagged**; major omission today |

### State space

Five disease states (per Research Plan):

1. **Healthy** — no current oral oncogenic HPV
2. **Infection** — incident oral oncogenic HPV
3. **Persistent Infection** — infection that fails to clear within the persistence threshold
4. **OPC** — HPV-associated oropharyngeal cancer
5. **Death** — absorbing

A `Cured/Post-treatment` state for OPC survivors is worth considering; many published models include it. Currently the Research Plan has Death as the only exit from OPC, which is a simplification.

### Allowed transitions

```
Healthy ⇌ Infection → Persistent → OPC → Death
   ↓        ↓           ↓          ↓
  Death   Death       Death      (Death)
```

Notes:
- `Healthy → Infection` and `Infection → Healthy` (clearance) are reversible.
- `Persistent → Infection` (regression to clearable) is biologically possible but usually omitted.
- `OPC → Healthy/Cured` is a modeling choice; if added, needs OPC-specific survival inputs.
- Background mortality applies from every non-absorbing state.

### Time mechanics

| Element | Current (per Research Plan) | Reviewer-flagged target |
|---|---|---|
| Time step | Annual | **Quarterly** (or finer) for Healthy↔Infection↔Persistent; annual OK for OPC/Death |
| Horizon | 30 years | 30 years; consider 50 for sensitivity given long latency |
| Calendar start | 2025–2026 | document explicitly |
| Burn-in | not specified | recommend 5+ years to equilibrate prevalent infections |
| MC iterations | 1,000 | OK; Monte Carlo error should be reported |
| Cohort size | 10,000 | **500K–1M** or explicit MC error justification at 10K |

---

## 2. Parameter inventory

Legend for `Source`:
- **A1** = derivable from Aim 1 CDW data
- **EXT** = external literature; needs citation
- **ASSUME** = modeling assumption; needs sensitivity range
- **MIX** = combination (e.g., Aim 1 distribution + literature for missing strata)

Legend for `Status` once you map against code (fill in during the audit):
- ✅ = present and parameterized
- 🟡 = present but value is a placeholder/guess
- ❌ = not in current model

### 2.1 Cohort initialization

These specify the synthetic population. All come from Aim 1 marginal and joint distributions, with literature backstop where Aim 1 cells are sparse.

| # | Parameter | Type | Stratification | Source | Notes |
|---|---|---|---|---|---|
| C1 | Age distribution at sim start | empirical CDF | by sex, VISN | A1 | 26–45 within Veterans aged 26–45 cohort |
| C2 | Sex distribution | proportion | by VISN | A1 | Veterans ~90% male overall |
| C3 | Race/ethnicity distribution | proportion | by sex, VISN | A1 | |
| C4 | VISN distribution | proportion | — | A1 | preserved as stratifier |
| C5 | Rurality (RUCA) distribution | proportion | by VISN | A1 | |
| C6 | SPAR distribution | continuous | by tract | A1 | |
| C7 | Smoking status | proportion | by age, sex, VISN | A1 | current/former/never |
| C8 | Pack-years (if used) | continuous | by smoking status | A1 | recommend including |
| C9 | Alcohol use | proportion | by age, sex | A1 | |
| C10 | Comorbidity burden | distribution | by age, sex | A1 | |
| C11 | Service connection % | distribution | — | A1 | |
| C12 | Burn pit / military exposure | proportion | by VISN, era of service | A1 | sparse data; assumption-heavy |
| C13 | Baseline vaccination status | proportion ever-vaxed | by age, sex, VISN, rurality | A1 | core Aim 1 output |
| C14 | Vaccination dose count distribution | proportion 1/2/3 doses | by age, sex | A1 | only available for inception cohort |
| C15 | Age at first dose | continuous | by sex | A1 | |
| C16 | **Pre-existing oral HPV prevalence** | proportion | by age, sex, smoking | EXT (NHANES, D'Souza) | **reviewer-flagged**; ~7% men, ~1% women overall, higher in current smokers |
| C17 | Pre-existing persistent infection | proportion | by age, sex | EXT | small; ~1–2% of infected at any time |
| C18 | Prevalent OPC at sim start | proportion | by age, sex | EXT | ~0 in 26–45 starting cohort |

**Joint distribution sampling:** Initialization should use stratified sampling so that key cross-tabulations (age × VISN, smoking × vaccination, sex × race) reproduce Aim 1 marginals, not just univariate distributions.

### 2.2 Transition parameters

These are the engine. All currently per-annual-step; should become per-quarterly-step (or per-monthly with rate-based formulation) after the time-step revision. **Conversion gotcha:** if `p_annual` is the annual probability, the equivalent quarterly probability is `p_quarterly = 1 - (1 - p_annual)^(1/4)`, NOT `p_annual / 4`. Apply this consistently.

#### Acquisition: Healthy → Infection

| # | Parameter | Type | Stratification | Source | Notes |
|---|---|---|---|---|---|
| T1 | Baseline acquisition hazard | rate per time step | by age, sex | EXT | NHANES incident oral HPV; very limited data |
| T2 | Smoking RR on acquisition | multiplier | current vs never | EXT | small, ~1.3 |
| T3 | Sexual behavior multiplier | multiplier | by age/sex (proxy) | EXT/ASSUME | direct sexual history not in CDW |
| T4 | Type-specific weighting (HPV16 vs other oncogenic) | proportion | — | EXT | HPV16 dominates OPC etiology |

#### Clearance: Infection → Healthy

| # | Parameter | Type | Stratification | Source | Notes |
|---|---|---|---|---|---|
| T5 | Baseline clearance rate | rate or 1−p per step | by age, sex | EXT | most clear within 12–24 months; **this is the mechanism that needs sub-annual time steps** |
| T6 | Smoking RR on clearance | multiplier | current vs never | EXT | reduced clearance, ~0.6–0.8 |
| T7 | Age effect on clearance | multiplier or function | continuous age | EXT | clearance declines with age |

#### Progression: Infection → Persistent

If clearance is modeled explicitly, persistence is the complement (no clearance over a defined window). Some models specify it as an explicit transition; others as `1 − P(clearance over τ months)`. Pick one and document.

| # | Parameter | Type | Stratification | Source | Notes |
|---|---|---|---|---|---|
| T8 | Persistence threshold | duration (months) | — | ASSUME | typically ≥12 or ≥24 months |
| T9 | Smoking RR on persistence | multiplier | current vs never | EXT | substantial, ~2.0 |
| T10 | Comorbidity/immune effect | multiplier | by index | EXT/ASSUME | |

#### Progression: Persistent → OPC ★ (the latency problem)

**This is the most underspecified part of the current model and the highest-leverage fix.**

| # | Parameter | Type | Stratification | Source | Notes |
|---|---|---|---|---|---|
| T11 | **Sojourn time in Persistent** | distribution (Weibull recommended; lognormal alt.) | by age, sex, smoking | EXT/ASSUME | mean 10–30 yr; need shape + scale; **reviewer-flagged** |
| T12 | Minimum sojourn | duration (years) | — | ASSUME | suggest ≥5 yr; tested 0/2/5 in sensitivity |
| T13 | Smoking RR on progression | multiplier | current vs never | EXT | substantial, ~2–3× |
| T14 | Alcohol RR on progression | multiplier | heavy vs none | EXT | smaller; synergistic with smoking |
| T15 | Burn pit RR on progression | multiplier | exposed vs not | ASSUME | thin direct evidence; sensitivity range broad |
| T16 | Sex-specific progression multiplier | multiplier | M vs F | EXT | M much higher; partially captured via baseline |
| T17 | Type-specific progression (HPV16 vs other) | multiplier | by type | EXT | HPV16 progresses; non-16 oncogenic types contribute less to OPC |

**Implementation note:** A Weibull dwell-time approach means each agent entering Persistent draws a time-to-OPC `T ~ Weibull(shape=k, scale=λ)` modified by their covariates. This replaces a per-step transition probability entirely. The decision between (a) per-step hazard with risk modifiers vs (b) draw-and-schedule dwell time is structural — both are defensible; the dwell-time approach is more transparent and easier to calibrate to observed latency distributions.

#### Background mortality: any state → Death

| # | Parameter | Type | Stratification | Source | Notes |
|---|---|---|---|---|---|
| T18 | All-cause mortality | rate per time step | by age, sex, race | EXT | VA-specific tables preferred |
| T19 | Mortality multiplier from comorbidity | multiplier | by index | EXT | optional |
| T20 | Mortality multiplier from smoking | multiplier | current vs never | EXT | |

#### OPC-specific mortality: OPC → Death

| # | Parameter | Type | Stratification | Source | Notes |
|---|---|---|---|---|---|
| T21 | OPC stage at diagnosis distribution | proportion | by age, smoking | EXT (Zevallos 2021) | most OPC diagnosed at advanced stage |
| T22 | OPC-specific mortality | rate per time step | by stage, age | EXT (SEER, VA) | 5-yr survival ~60–70% HPV+; lower HPV− |
| T23 | Treatment effect on mortality | multiplier | by treatment type | ASSUME | optional, depends on whether you model treatment |

### 2.3 Vaccination parameters

| # | Parameter | Type | Stratification | Source | Notes |
|---|---|---|---|---|---|
| V1 | Vaccine efficacy vs acquisition | proportion | by HPV type, by dose count | EXT | ~90% for fully vaccinated against HPV16/18 |
| V2 | Vaccine efficacy vs persistence | proportion | by type | EXT | high in trial populations |
| V3 | Efficacy reduction if pre-existing infection at vax | function | type-specific | EXT | **reviewer-flagged**; near zero on the existing strain, full on naive types |
| V4 | Time-to-protection after dose | duration | — | ASSUME | usually weeks; small in 30-yr horizon |
| V5 | Waning of protection | function | per year | EXT/ASSUME | minimal evidence of waning to date |
| V6 | Number of doses required for full effect | integer | by age at first dose | EXT | 2-dose if start <15; 3-dose otherwise |
| V7 | Single-dose efficacy | proportion | by age, sex | EXT | recent evidence supports partial protection from 1 dose |
| V8 | Adherence (series completion) | proportion | by age, sex, VISN | A1 | **reviewer-flagged**; declines with age |
| V9 | Coverage achievable in expansion scenario | function over time | by age cohort, VISN | ASSUME | scenario lever; document explicitly |
| V10 | Catch-up uptake ramp | function (year → coverage) | by scenario | ASSUME | optimistic / realistic / pessimistic |

### 2.4 Effect modifiers (consolidated)

This is a cross-cutting view of where covariates enter transitions. Currently many of these are absent from the model.

| Covariate | Acquisition | Clearance | Persistence | Progression to OPC | Mortality |
|---|---|---|---|---|---|
| Sex | × | × | × | × | × |
| Age | × | × | — | × | × |
| Smoking | T2 | T6 | T9 | T13 | T20 |
| Alcohol | — | — | — | T14 | — |
| Burn pit | — | — | — | T15 | — |
| Comorbidity | — | — | T10 | — | T19 |
| Vaccination | V1 | — | V2 | — | — |
| Pre-existing infection | (gates V1) | — | (gates V2) | — | — |
| HPV type | T4 | T6? | — | T17 | — |

### 2.5 Simulation control

| # | Parameter | Type | Default | Notes |
|---|---|---|---|---|
| S1 | `n_agents` | integer | 10,000 | scale to 500K–1M |
| S2 | `time_step` | duration | 1 yr | move to 0.25 yr |
| S3 | `horizon` | years | 30 | |
| S4 | `burn_in` | years | not specified | recommend ≥5 |
| S5 | `mc_iterations` | integer | 1,000 | OK |
| S6 | `seed_base` | integer | — | one master seed; per-iteration seeds derived |
| S7 | `start_calendar_year` | integer | — | document |
| S8 | scenarios | list | {26, 30, 35, 40, 45} | consider hybrid scenarios per Reviewer 2 |

### 2.6 Calibration targets

These are the external benchmarks you compare model outputs to. Aim 1 does **not** observe HPV infection or OPC, so calibration anchors must come from outside the model's primary data.

| # | Target | Source | What it calibrates |
|---|---|---|---|
| K1 | Oral HPV prevalence by age × sex × smoking | NHANES | acquisition + clearance balance (T1, T5, T6) |
| K2 | Oral HPV incidence | NHANES, military cohorts (Masel 2015) | T1 |
| K3 | OPC incidence in VA, by age × sex × era | Zevallos 2021 *Head Neck* | overall progression cascade |
| K4 | OPC incidence general US population | SEER | sanity-check Veteran multipliers |
| K5 | OPC mortality | SEER, VA | T21, T22 |
| K6 | HPV vaccination prevalence by age × VISN × rurality | Aim 1 | C13 |
| K7 | Vaccination series completion | Aim 1 | V8 |
| K8 | Smoking prevalence by age × sex × VISN | Aim 1 | C7 |

### 2.7 Outputs

Per scenario, per Monte Carlo iteration:

| # | Output | Granularity |
|---|---|---|
| O1 | Cumulative incident HPV infections | by year, age cohort, VISN |
| O2 | Cumulative persistent infections | by year, age cohort, VISN |
| O3 | Cumulative OPC cases | by year, age cohort, VISN |
| O4 | OPC deaths | by year, age cohort, VISN |
| O5 | Number of vaccinations administered | by year, age cohort, VISN |
| O6 | Number-needed-to-vaccinate to prevent one OPC | scenario-level |
| O7 | Life-years gained vs status quo | by VISN |
| O8 | Time series for all of the above | for plotting |

For each output, summarize across MC iterations as median + 95% simulation interval.

---

## 3. What needs to happen next

To make this concrete and connect it to your code:

1. **Paste the simulator script(s)** — at minimum the main simulator file, the helper/utility functions, and any parameter/config file. I'll mark each row in the inventory above with ✅ / 🟡 / ❌ based on what's actually implemented.
2. **From that, we'll generate a `parameter_sources.md`** that's the live, code-linked version of section 2 — every row tied to a specific function or config line, with current value and current source.
3. **Then we sequence the structural fixes** (time step, latency dwell-time, pre-existing infection logic) against this inventory, so each PR has a clear scope.

Paste the code whenever ready and I'll do the audit pass.
