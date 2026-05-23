# Project Instruction: HPV Vaccination Microsimulation for VA Pilot Grant

## Project Overview
This project builds the Aim 2 microsimulation model for a funded VA pilot grant titled **"Optimizing HPV Vaccination Strategies for Head and Neck Cancer Prevention in Veterans"** (Application 1I21RD002895-01, PI: Zevallos). The model projects the public health benefit of expanding HPV vaccination eligibility in the VHA from age 26 to ages 30, 35, 40, or 45, with a focus on oropharyngeal cancer (OPC) prevention.

The grant has been awarded with an impact score of 172. Reviewer critiques must be addressed in the final model.

---

## Model Architecture: 5-State Individual-Based Microsimulation

**Health States (in order of progression):**
`healthy → infected → persistent → cancer → dead`

**Key Biological Facts to Preserve:**
- Oral oncogenic HPV infection is the necessary precursor to HPV+ OPC
- Clearance is most likely in the first 1–2 years; after 2+ years probability drops sharply
- Persistence is defined as continuous infection >24 months
- Latency from persistent infection to OPC is 10–30 years (mean ~17–18 years); modeled with a Weibull distribution (shape=3, scale=20 as starting point — subject to calibration)
- Vaccination acts at two points: (1) reduces acquisition probability and (2) reduces transition from infected to persistent
- OPC 5-year survival for HPV+ disease is ~79%; modeled via annual excess mortality

**Population:**
- Veterans aged 26–45 at simulation entry
- **Male only** (`prop_male = 1.0`) — OPC burden is overwhelmingly male in the VHA; simplifies the model and removes poorly-sourced female natural history parameters
- ~27% current smokers
- ~15% heavy alcohol use
- Prevalent infections seeded at baseline using US male oral HPV prevalence (PROGRESS US, Giuliano 2023)

**Scenarios to Compare:**
- Status quo: vaccination eligibility through age 26
- Expanded: eligibility through ages 30, 35, 40, 45

---

## Code Files in This Project

| File | Role |
|---|---|
| `helper_v3.R` | All functions: population generator, simulation loop, plotting, ICER |
| `simulator_v3.R` | Parameter declarations and scenario runner |
| `2026_02_16_helper.R` | Original v1 helper — reference only, do not run |
| `2026_02_16_simulator.R` | Original v1 simulator — reference only, do not run |
| `parameters.xlsx` | Parameter table (being built out — single source of truth) |

**Active files are helper_v3.R and simulator_v3.R.** All development happens in these files.

---

## Known Bugs to Fix (Priority Order)

### Bug 1 — Deterministic persistence (biological error)
**Location:** `simulator_v3.R` line: `p_persistence_given_long_inf <- 1.0`
**Problem:** Every agent infected past the threshold deterministically becomes persistent. This overestimates persistent infection prevalence and is biologically wrong.
**Fix:** Set to a calibrated value (literature suggests 10–20% of infections persist). Make stochastic.

### Bug 2 — Negative time-to-cancer at baseline (logical error)
**Location:** `helper_v3.R`, `generate_population()`, the `pers_at_start` block
**Problem:** `accrued <- infection_duration - persistence_threshold_years` can exceed the Weibull-sampled `time_to_cancer`, producing negative remaining time. Agents would immediately get cancer at simulation start.
**Fix:** Clamp `time_to_cancer` so remaining time = max(ttc - accrued, 1L). Alternatively, resample until ttc > accrued.

### Bug 3 — ICER frontier includes dominated strategies (analytical error)
**Location:** `helper_v3.R`, `generate_icer_plot()`
**Problem:** Dominated strategies are not removed before calculating incremental costs and effects. This produces misleading ICER values.
**Fix:** Implement proper extended dominance removal before computing the efficient frontier.

---

## Features to Add (in build order)

1. **Age-specific vaccination uptake** — `p_vaccinate` should vary by age group (26–30, 31–35, 36–40, 41–45), not be a single flat probability. Sourced from Aim 1 data or literature placeholders until Aim 1 completes.

2. **VISN-level heterogeneity** — At minimum, VISN-specific baseline vaccination prevalence and smoking prevalence as input parameters. Required for VISN-level output tables described in Aim 2.

4. **Calibration scaffold** — Define observable targets the model must reproduce:
   - VA OPC incidence rate (from Zevallos et al. 2021, Head & Neck)
   - Oral HPV prevalence from NHANES (Gillison et al.)
   - OPC 5-year survival ~79% (HPV+ disease)
   - Vaccination prevalence from Aim 1 / Figure 2 in grant

5. **Formal sensitivity analysis** — One-way (tornado) and probabilistic (PSA with parameter ranges). PSA should use 1,000 Monte Carlo draws over parameter uncertainty ranges.

6. **Trace/validation output** — Year-by-year state proportions to confirm model behaves sensibly (e.g., infection prevalence plausible in year 5 vs year 30).

---

## Parameters: Source Hierarchy

When sourcing any parameter, use this priority order:
1. VA-specific published data (e.g., Zevallos et al., Chidambaram et al. JAMA Oncology 2023)
2. US population studies (NHANES, HIM Study, SEER)
3. Clinical trial data (vaccine efficacy from RCTs in 24–45 age group)
4. General literature / meta-analyses

**Always document the source, year, and population for every parameter in the parameters.xlsx file.**

---

## Reviewer Critiques to Address (from Summary Statement)

| Critique | Reviewer | Status |
|---|---|---|
| Missing QALY and cost-effectiveness analysis | R1, R2 | Partially done in v3; ICER bug must be fixed |
| 10,000 agents too few for rare outcome | R1 | Fixed in v3 (100,000) |
| Latency between persistent infection and cancer not specified | R1 | Addressed with Weibull in v3 |
| Pre-existing infection not modeled | R1 | Addressed in v3 generate_population() |
| Age-specific vaccine adherence missing | R1, R2 | Not yet implemented |
| Burn pit exposure not incorporated | R2 | Not yet implemented |
| VISN-level outputs needed | R2 | Not yet implemented |
| Calibration targets not specified | R3 | Not yet implemented |
| Annual time steps too coarse for clearance dynamics | R1 | Not yet changed — consider quarterly steps |
| Rationale for incremental age thresholds needed | R2 | Model design issue; document in output |
| Other adult vaccination history not adjusted for | R2 | Not yet implemented |

---

## Coding Standards

- Language: R
- Key packages: `data.table`, `dplyr`, `ggplot2`, `ggsci`, `ggrepel`, `scales`, `tidyr`, `patchwork`
- All simulations use `set.seed(2026)` for reproducibility
- Parameters live in `simulator_v3.R` only; helper functions live in `helper_v3.R`
- `parameters.xlsx` is the authoritative parameter table; every parameter in the R files should have a corresponding row in that table with source citation
- Costs are discounted at 3% annually; QALYs are also discounted at 3%
- Simulation horizon: 75 years
- All monetary values in 2024 USD

---

## What NOT to Do
- Do not revert to the v1 4-state model structure
- Do not use `p_persistence_given_long_inf = 1.0` (deterministic persistence)
- Do not run simulations with fewer than 100,000 agents for final results
- Do not add features without a cited parameter source — use a clearly labeled placeholder with a note to update from Aim 1 data
- Do not add sex-stratified parameters or female natural history — the model is male-only
- Do not add burn pit exposure or change time step granularity — both are out of scope for this phase
