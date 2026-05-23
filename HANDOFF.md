# Project Handoff: HPV Vaccination Microsimulation for VA Pilot Grant

**Read this entire document before touching code.** It contains everything you need to continue the work, including decisions made and their justifications, known limitations, and what's next.

---

## 0. Quick Orientation

You are working on the **Aim 2 microsimulation model** for a funded VA pilot grant: **"Optimizing HPV Vaccination Strategies for Head and Neck Cancer Prevention in Veterans"** (Application 1I21RD002895-01, PI: Zevallos, impact score 172).

The model projects the public health benefit of expanding HPV vaccination eligibility in the VHA from age 26 to ages 30, 35, 40, or 45, with a focus on HPV+ oropharyngeal cancer (OPC) prevention.

**You are continuing work from a prior Claude session conducted in claude.ai.** The user has now moved this work into Antigravity with Claude Code so you can run the code, iterate, and commit to git. The git repo is: https://github.com/soumikp/2025_zevallos

---

## 1. File Layout

Place files in the existing repo structure:

| File | Repo location | Status |
|---|---|---|
| `helper_v3.R` | `/code/` | **Updated this session** — replace existing |
| `simulator_v3.R` | `/code/` | **Updated this session** — replace existing |
| `2026_05_19_param_table.md` | `/documents/` | **Updated this session** — replace existing |
| `2026_05_19_project_instruction.md` | `/documents/` | Existing — no changes |
| `2026_05_19_next_steps.md` | `/documents/` | Existing — see Section 7 below; partially stale |
| `2026_02_16_helper.R`, `2026_02_16_simulator.R` | `/code/` | **Reference only, do not run** (v1, 4-state) |
| Source PDFs | `/literature/` | Existing |

After uploading the three updated files, **the first thing you should do is run the simulator end-to-end at `num_agents = 10000`** to confirm it works before scaling to 100k. See Section 6.

---

## 2. Model Architecture

**5-state individual-based microsimulation:**
`healthy → infected → persistent → cancer → dead`

**Population:**
- Veterans aged 26–45 at simulation entry
- **Male only** (no sex column; project instruction Section 2 confirms this)
- ~27% current smokers, ~15% heavy alcohol use
- Prevalent infections seeded at baseline from Giuliano 2023 PROGRESS US male oral HPV prevalence

**Scenarios:**
- Status quo: vaccination eligibility through age 26
- Expanded: eligibility through ages 30, 35, 40, 45

**Time step:** Annual.

**Simulation horizon:** 75 years.

**Discount rate:** 3% annual (both costs and QALYs).

**All monetary values:** 2024 USD.

**Seed:** `set.seed(2026)`.

---

## 3. Decisions Made This Session (with rationale)

The previous Claude made a series of consequential decisions. **You should not silently revisit them.** If you disagree, raise it with the user explicitly before changing.

### 3.1 Male-only cohort (no sex branching)
The v3 code had `prop_male = 0.88` with sex-stratified parameters for baseline prevalence, acquisition, and progression. Per project instruction, the model is male-only. All sex logic was stripped: `sex` column removed from agents, `baseline_prev_female` and `p_acquisition_female` removed, `female_progression_RR` removed, `get_mortality_rate_vec` no longer takes a sex argument.

### 3.2 Persistence is ONE-SHOT, not a per-year hazard
**Old (v3, deterministic):** `p_persistence_given_long_inf = 1.0` — every infection past 2 years became persistent. Biologically wrong.

**New:** `p_persistence_given_long_inf = 0.40`, rolled **once** at the moment `infection_duration` crosses 2 years. Tracked by a new `persistence_evaluated` boolean column.
- Pass → agent transitions to `persistent` state
- Fail → agent stays `infected`, flag set to TRUE so they're never re-rolled for persistence in this infection episode
- On clearance back to `healthy`, the flag resets to FALSE so a future re-infection gets a fresh roll

Value derived directly from Pierce Campbell et al., Cancer Prev Res 2015 (HIM Study, n=23): 10/24 incident infections surviving to year 2 → persistent state (~42%, rounded to 0.40).

**Note:** Dube Mandishora 2024's claim that "~20% of HPV-16 infections persist >24 months" is a loose pooled summary of Campbell, not a directly reproducible number. Cite Campbell 2015 directly, not Dube Mandishora.

### 3.3 Truncated Weibull for seeded persistent agents
**Old (v3):** Bug — seeded persistent agents could have `accrued > ttc` producing negative remaining time-to-cancer.

**New:** Inverse-CDF conditioning on T > accrued: `qweibull(runif(n, pweibull(accrued, shape, scale), 1), shape, scale)`. Preserves the conditional shape of the Weibull while guaranteeing remaining time > 0. Storage convention changed: seeded persistent agents now start with `persistent_duration = 0` and `time_to_cancer = remaining` (not full ttc). Cancer fires when `persistent_duration >= time_to_cancer`, matching the in-simulation logic exactly.

### 3.4 Extended dominance in ICER calculation
**Old (v3):** Bug — dominated strategies were not removed before calculating incremental costs/effects.

**New:** `compute_efficient_frontier()` helper in `helper_v3.R` implements:
1. Simple dominance removal (any strategy with higher cost AND lower-or-equal QALYs vs another)
2. Iterative extended dominance removal (any frontier strategy whose ICER vs prior point exceeds the ICER of a later point)
3. Status column: `frontier` / `dominated` / `ext_dominated`

Plot now shows frontier in blue, simply-dominated in red, extended-dominated in orange.

### 3.5 Cost parameters
| Parameter | Value | Source |
|---|---|---|
| `COST_OPC_DIAGNOSIS` | **$0** | Set to 0 to avoid double-counting; Saxena 2022's annual cost already includes diagnostic workup |
| `COST_ANNUAL_CANCER_TX` | **$85,000** | Saxena et al., J Med Econ 2022 (n=4,537 VA OPC cases, FY2014-2018): incremental cost vs matched controls = $72,746 (2018 USD) × 1.169 CPI factor (BLS Medical Care CPI 2018→2024) = $85,061 |
| `COST_ANNUAL_SURVIVOR` | **$2,500** | Refinement of v3 placeholder; no direct source. Low contribution to total. |
| `vaccine_cost` | **$550** | CDC Vaccine Price List, Dec 1 2024: Gardasil 9 adult CDC contract price $182.79/dose × 3 doses |

### 3.6 QALY weights
| Parameter | Value | Source |
|---|---|---|
| `QALY_HEALTHY` | 1.00 | Anchor |
| `QALY_INFECTED` | 0.98 | Asymptomatic; placeholder |
| `QALY_PERSISTENT` | 0.98 | Asymptomatic; placeholder |
| `QALY_CANCER_ACTIVE` | **0.65** | v3 value retained per user decision. De-ESCALaTE HPV trial (Jones 2020, n=166 HPV+ OPSCC) suggests 0.75 for HPV+ specifically; 0.65 is conservative. Test 0.75 in sensitivity analysis. |
| `QALY_CANCER_SURVIVOR` | 0.87 | De-ESCALaTE 24-mo PT EQ-5D-5L score |

### 3.7 Background mortality from SSA Period Life Table 2021 (male)
**Old (v3):** Piecewise placeholder function (0.001/yr baseline; 1% by age 60, 1.3% by age 99). Substantially understated mortality.

**New:** Hardcoded lookup vector `ssa_male_qx_2021` for ages 20-99, from https://www.ssa.gov/oact/STATS/table4c6_2021_TR2024.html. `get_mortality_rate_vec()` clamps age to [20, 99] and returns qx. Used for general male population — **no veteran-specific multiplier applied** (literature suggests RR 1.0-1.2; defensible default is 1.0 with smoking RR capturing the major risk component).

Smoking-specific RR (`smoking_mortality_RR = 2.0`) is still applied multiplicatively in the simulation loop.

### 3.8 Other parameter updates rolled in this session
| Parameter | v3 | New | Source |
|---|---|---|---|
| `baseline_prev` | 0.06 | 0.033 | Giuliano 2023 PROGRESS US (was over-stated in v3) |
| `p_acquisition` | 0.04 | 0.041 | Dube Mandishora 2024 HIM US subcohort |
| `smoking_acquisition_RR` | 1.5 | 1.15 | Dube Mandishora 2024 aHR |
| `alcohol_acquisition_RR` | (none) | 1.43 | Dube Mandishora 2024 aHR (new parameter) |
| `p_clearance_medium` | 0.30 | 0.40 | Param table derivation; consistent with Kreimer 2013 |
| `smoking_progression_RR` | 2.0 | 1.5 | Applebaum 2007 (HPV+ specific; less tobacco-driven than HPV-) |
| `alcohol_progression_RR` | 1.5 | 1.3 | Applebaum 2007 |
| `smoking_alcohol_synergy` | 1.3 | 1.2 | Conservative adjustment |

---

## 4. Known Limitations and Caveats

These are not bugs but are worth knowing:

1. **`baseline_prev` and many parameters carry single-source uncertainty.** PSA ranges are noted in the param table but not yet implemented in the code.

2. **The clearance threshold uses strict `>` not `>=`.** In `helper_v3.R`, the clearance block uses `clear_probs[infected$infection_duration > 2] <- p_clearance_medium`. Per the param table convention, year 2 of infection should arguably get the medium rate (`>= 2`). This is a pre-existing inconsistency from v3 that was left as-is, with a comment flagging it. **Decision pending from user.**

3. **`cause_of_death = "opc"` is assigned to any death while `health_state == "cancer"`**, including long-tail survivors dying primarily of background causes plus the 1% survivor excess. This may inflate `n_dead_opc`. Consider splitting into `opc_active` and `opc_late` causes, or attributing proportionally.

4. **Param table section numbering is shuffled** (1, 2, 3, 4, 5, 6, 8, 7, 10, 11). Section 9 doesn't exist but is referenced in `simulator_v3.R` line 81 as "Sheet 9 NEW" (should be Section 7, Vaccination Uptake). Cosmetic.

5. **The mortality vector returns unnamed values** (defensively `unname()`'d in the function). Downstream code in the sim loop doesn't depend on names, but spot-check if you refactor.

6. **The simulator references `parameters.xlsx` in some comments** but the authoritative source is the markdown param table. Cosmetic.

---

## 5. Confirmed Bugs Fixed This Session

| Bug | Location | Fix |
|---|---|---|
| Bug 1: Deterministic persistence | `simulator_v3.R` | `p_persistence_given_long_inf = 0.40` with one-shot semantics |
| Bug 2: Negative time-to-cancer at baseline | `helper_v3.R`, `generate_population()` | Truncated Weibull via inverse-CDF |
| Bug 3: ICER frontier includes dominated strategies | `helper_v3.R`, `generate_icer_plot()` | New `compute_efficient_frontier()` helper with iterative extended dominance |
| Bug 4: Persistence re-rolled annually | `helper_v3.R` | New `persistence_evaluated` boolean column; tracks one-shot status across the agent's lifetime |

---

## 6. First Things To Do

In this order:

### 6.1 Verify the code runs end-to-end
```r
# In R or RStudio inside Antigravity:
source("code/helper_v3.R")
source("code/simulator_v3.R")
# Edit simulator to set num_agents <- 10000 for first run
# Then source it and verify no errors
```

Most likely failure modes if there is an error:
- `compute_efficient_frontier`: brand-new code, edge cases in iterative removal (e.g., all-equal ICERs). Look there first.
- `data.table` multi-column `:=` with `id %in% ...`: should work but version-quirky.
- Empty subset handling in the persistence block: `if(length(new_pers_ids) > 0)` guards are present but I didn't trace every n=0 path.

### 6.2 Sanity-check output traces
- Year-by-year `stats_mat`: does `n_new_infected` look reasonable? With `p_acquisition = 0.041` and ~100k healthy agents, expect ~3,000-4,000 new infections in early years.
- `n_new_persistent`: should be roughly (annual surviving past year 2) × 0.40. Given clearance rates, ~10% of incident infections eventually persist. So if you see ~3,000 new infections/year, expect ~300 new persistent/year (lagged 2y).
- Final state distribution at year 75: most agents dead (SSA mortality is realistic now), small fraction had OPC.

### 6.3 Compare to calibration targets
The grant mandates the model reproduce:
- VA OPC incidence rate (Zevallos et al. 2021, Head & Neck) — exact value TBD
- Oral HPV prevalence from NHANES (Gillison et al.)
- OPC 5-year survival ~79% (HPV+ disease)
- Vaccination prevalence from Aim 1 / Figure 2 in grant

**If the cumulative incidence is much lower than VA data suggests**, the most likely cause is the combined effect of (a) more realistic mortality killing agents before cancer onset, (b) one-shot persistence, and (c) corrected baseline prevalence. This may be a *correct* result that exposes the v3 model was over-counting; or it may indicate the latency Weibull(3, 20) is too long.

### 6.4 Then scale to `num_agents = 100000` for production results

---

## 7. Roadmap (from `2026_05_19_next_steps.md`)

The next-steps file in the repo lists features to add. Status update from this session:

| Feature | Status |
|---|---|
| Fix deterministic persistence (Bug 1) | **Done** |
| Fix negative time-to-cancer (Bug 2) | **Done** |
| Fix ICER dominated strategies (Bug 3) | **Done** |
| Add `persistence_evaluated` flag (Bug 4) | **Done** |
| Male-only cohort | **Done** |
| SSA life table for background mortality | **Done** |
| Age-specific vaccination uptake (`p_vaccinate` by age band) | **Not started** — placeholders pending Aim 1 data |
| VISN-level heterogeneity (VISN-specific smoking, baseline vaccination prevalence) | **Not started** |
| Calibration scaffold | **Not started** — see Section 6.3 for targets |
| Formal sensitivity analysis (one-way tornado + PSA with 1,000 MC draws) | **Not started** — PSA distributions ARE defined in param table |
| Trace/validation output (year-by-year state proportions) | **Partial** — `stats_mat` exists; needs better summary |
| Quarterly time steps (R1 critique on temporal granularity) | **Deferred** — explicitly out of scope per project instruction |
| Burn pit exposure (R2 critique) | **Deferred** — explicitly out of scope per project instruction; address in Discussion |
| Other adult vaccination history (R2 critique) | **Not started** |

The next-steps file may have stale items reflecting the old mixed-sex design; cross-check against this handoff document.

---

## 8. Source Citations Used This Session

For full sourcing, see the param table. Key sources:

**From project PDFs (in `/literature/`):**
- **Pierce Campbell et al., Cancer Prev Res 2015** — HIM Study, n=23 oral HPV-16+ men, persistence numbers
- **Saxena et al., J Med Econ 2022** — VA OPC cost burden (n=4,537), primary cost source
- **Jacobson et al., Head Neck Oncol 2012** — Combined oral/OP/SG cancer costs, cross-check
- **Laprise et al., Ann Intern Med 2020** — Vaccine cost reference, ICER comparators
- **Giuliano et al., JAMA Otolaryngol 2023** — PROGRESS US, male oral HPV prevalence
- **Dube Mandishora et al., Nat Microbiol 2024** — HIM US subcohort, acquisition incidence + RRs
- **Kreimer et al., Lancet 2013** — HIM Study, clearance rates
- **Applebaum et al., 2007** — HPV+ specific tobacco/alcohol risk (lower than HPV-)

**From web (with URLs documented in param table):**
- **CDC Vaccine Price List, Dec 1 2024** (cdc.gov archive) — Gardasil 9 federal contract pricing
- **BLS Medical Care CPI (CPIMEDSL)** — CPI adjustment from 2018 → 2024 (factor 1.169)
- **Jones et al., Eur J Cancer 2020** (PMC) — De-ESCALaTE HPV trial EQ-5D-5L utility scores
- **SSA Period Life Table 2021** (ssa.gov) — Male qx for ages 20-99
- **Odani et al., MMWR 2018** + **Brown et al., AJPH 2017** — Veteran smoking prevalence
- **Adejumo et al., Am J Med Open 2023** (PMC) — VA AUDIT-C high-risk drinking

---

## 9. Files Delivered with This Handoff

The three files in this delivery are the current working state:
1. **`helper_v3.R`** — all functions: `generate_population`, `run_simulation`, `compute_efficient_frontier`, `generate_icer_plot`, `get_mortality_rate_vec`, etc.
2. **`simulator_v3.R`** — all parameter declarations and scenario runner
3. **`2026_05_19_param_table.md`** — authoritative parameter table with sources

Place them in `/code/` (R files) and `/documents/` (markdown) respectively.

---

## 10. Working Style Notes for Next Claude

The user prefers:
- **Honest flagging of uncertainty.** When a parameter has no direct source, say so. Don't invent attributions.
- **Don't implement things without permission.** Ask before substantive changes; especially do not "fix" things on your own initiative without flagging first.
- **Don't make decisions unilaterally about contested numerical values.** When the literature is ambiguous (e.g., the Campbell vs Dube Mandishora citation issue), present options and let the user pick.
- **Concise check-ins via `ask_user_input_v0`-style options** when there are multiple defensible paths.
- **Read the literature directly when claims are non-obvious.** The previous Claude unzipped and read the Campbell 2015 PDF directly to derive the 0.40 persistence value rather than relying on the secondary citation in the param table.
- **Code first, then numeric changes.** Major bug fixes are separate from parameter recalibration; bundle changes only when the user explicitly OKs it.

---

## 11. Open Questions for the User (carried forward)

These were raised but not resolved in the prior session:

1. **Clearance threshold convention:** Should `infected$infection_duration > 2` become `>= 2` to match the param table convention that "year 2 = medium rate"?
2. **OPC death attribution:** Should `cause_of_death = "opc"` be split into active-phase vs survivor-phase to avoid attributing background deaths to OPC?
3. **Param table section reordering:** Worth cleaning up the 1,2,3,4,5,6,8,7,10,11 sequence?
4. **Veteran mortality multiplier:** Currently 1.0 (general male population). Test 1.1 in sensitivity?
5. **Diagnosis-vs-treatment cost split:** Currently folded into single annual cost ($85k × 5y active). If clinical team wants separate diagnosis-year cost, restructure.

---

*End of handoff document. Good luck.*
