# Parameter list for PI meeting — Zevallos VA Pilot

**Purpose:** Walk into the PI meeting with a structured list of every parameter the simulation needs values for, what each means clinically, whether we need a single value or a range, and the likely source. Initial estimates from literature are included so the PI has something concrete to react to rather than a blank table.

**Goal of this meeting:** Lock down the parameters that block Option B (explicit Persistent state + Weibull dwell time on the Persistent → OPC transition). Everything else is secondary but flagged so the PI knows what's coming.

**Conventions:**
- **Point** = single defensible value
- **Range** = central estimate + bounds for sensitivity analysis (most parameters need this)
- **Distribution** = parametric distribution with parameters
- **Tier 1** = blocks Option B implementation
- **Tier 2** = needed for the model to produce plausible outputs end-to-end
- **Tier 3** = needed for calibration and sensitivity analyses
- **Aim 1** = comes from CDW analyses; flagged here so the PI knows the dependency, but not asking the PI to provide

---

## Cluster 1 — Pre-existing infection at simulation start

These set the initial conditions. The current code seeds 40% of all agents as already-infected, which is too high for any oncogenic-type definition.

| Parameter | Meaning | Type | Initial estimate | Source | Tier |
|---|---|---|---|---|---|
| Prevalence of any oral oncogenic HPV at sim start | Fraction of agents starting in `Infected` state | Range, by age × sex | Men 26–45: ~5–7%; women: ~1–2% | NHANES (Sonawane 2017, Chaturvedi 2012) | 2 |
| Prevalence of oral HPV16 specifically | Subset of the above; HPV16 drives most OPC | Range, by age × sex | Men: ~1–1.5%; women: <0.5% | NHANES | 2 |
| Of currently infected at sim start, fraction already persistent | Determines who's already on the cancer-progression clock | Range | 10–25% of infections | Literature on persistence rates | 2 |
| Duration distribution of pre-existing infections | How long ongoing infections have been ongoing | Distribution | Currently uniform 1–7 yrs in code; should match clearance dynamics | Modeling choice | 2 |

**For PI:** does VA-specific oral HPV prevalence data exist beyond the published Veteran/military estimates? If not, NHANES + a sensitivity multiplier for the higher-smoking Veteran population is the path.

---

## Cluster 2 — Acquisition (Healthy → Infection)

| Parameter | Meaning | Type | Initial estimate | Source | Tier |
|---|---|---|---|---|---|
| Annual incidence of incident oral oncogenic HPV | Probability per year a healthy agent acquires oral HPV | Range, by age × sex | ~1–4% per year in sexually active adults; lower with age | NHANES, military cohort (Masel 2015) | 2 |
| Smoking RR on acquisition | Multiplier on baseline acquisition for current smokers | Range | 1.3 (range 1.0–2.0) | D'Souza HPV studies | 2 |
| Fraction of incident infections that are HPV16 | Type-specific weighting of incident infections | Point | ~25–30% of oncogenic types | Gillison HPV epi | 3 |
| Per-step probability conversion (annual → quarterly) | Mechanical conversion if quarterly time steps | Formula | `p_q = 1 − (1 − p_a)^(1/4)` | — | 1 (when we move to quarterly) |

**For PI:** any preference between using NHANES marginal incidence vs. modeling acquisition as a function of partnership-related variables? The former is simpler and what we have data for; the latter is more biologically grounded but unsupported by CDW.

---

## Cluster 3 — Clearance (Infection → Healthy)

| Parameter | Meaning | Type | Initial estimate | Source | Tier |
|---|---|---|---|---|---|
| Median time to clearance of incident oral HPV | How long until a typical infection clears | Point + range | Median 7–12 months; range 6–18 | D'Souza et al. follow-up studies | 2 |
| Annual clearance probability (years 0–2) | Per-step probability for short-duration infections | Range | 50–70% per year | Derived from median above | 2 |
| Annual clearance probability (years 2–5) | Reduced clearance for medium-duration | Range | 20–40% | Literature; current code uses 40% | 2 |
| Annual clearance probability (>5 years) | Effectively the persistent regime | Range | 0–10% | Literature; current code uses 5% | 2 |
| Smoking RR on clearance | Multiplier for current smokers (RR < 1) | Range | 0.6–0.8 | D'Souza | 2 |
| Age effect on clearance | Direction and magnitude of age effect | Range or function | Modest decline with age; limited evidence | Literature | 3 |

**For PI:** is there a strong clinical preference for representing clearance as a function of duration (current approach) vs. a function of age, or both? The duration-based approach is cleaner mechanically; the age-based approach is more biologically grounded.

---

## Cluster 4 — Persistence threshold

This is a modeling choice that needs to be defensible.

| Parameter | Meaning | Type | Initial estimate | Source | Tier |
|---|---|---|---|---|---|
| Threshold months of continuous infection defining "persistent" | When does an infection move from `Infected` to `Persistent`? | Point | 12 or 24 months | Literature convention | 1 |

**For PI:** which threshold does the PI prefer? 12 months is the more common research convention; 24 months is more conservative (excludes more transient infections from the persistence pathway). This single decision affects everything downstream in Option B.

---

## Cluster 5 — Latency: Persistent → OPC ★★★

This is the heart of Option B and the PI's domain expertise. **Highest leverage parameters in the entire model.**

| Parameter | Meaning | Type | Initial estimate | Source | Tier |
|---|---|---|---|---|---|
| Mean (or median) time from persistent infection to OPC diagnosis | Central tendency of the dwell time | Range | Mean 15–25 years; median ~20 | Gillison/Chaturvedi natural-history reviews | 1 |
| Minimum sojourn in Persistent before OPC is possible | Earliest plausible time to cancer | Point + sensitivity | 5 years (sensitivity at 0, 2, 5, 10) | Modeling choice; weak literature | 1 |
| Distribution shape | Family of the dwell-time distribution | Choice | Weibull (alt: lognormal, gamma) | Modeling convention | 1 |
| Weibull shape parameter (k) | Whether progression is "early" or "late" within window | Range | k ≈ 2–3 (right-skewed, late peak) | Calibration to age-incidence curves | 1 |
| Weibull scale parameter (λ) | Sets the time scale; pairs with shape to give mean | Range | Calibrated so mean matches above | Calibrated | 1 |
| Smoking RR on progression to OPC | Multiplier on hazard for current smokers | Range | 2.0–3.0 | INHANCE pooled, Hashibe et al. | 1 |
| Alcohol RR on progression | Multiplier for heavy alcohol use | Range | 1.5–2.0; substantial smoking interaction | INHANCE | 2 |
| Smoking × alcohol interaction | Synergy multiplier when both present | Range | Up to 5× combined | INHANCE | 3 |
| Burn pit / military exposure RR on progression | Multiplier for exposed Veterans | Range, broad | 1.0–1.5 (weak direct evidence) | Assumption with sensitivity | 3 |
| HPV16 vs other oncogenic types RR for progression | Differential cancer risk by HPV type | Point | HPV16 ~5–10× other oncogenic types for OPC | Gillison | 2 |
| Sex-specific multiplier on progression | M vs F differential beyond what acquisition explains | Range | 3–5× M vs F (partly via baseline) | SEER, Chaturvedi 2011 | 2 (deferred per current scope) |

**For PI:** this is where the meeting should spend most of its time. Specifically:
1. What's the most defensible mean and shape for the Weibull dwell time? Is 15–25 years the right range?
2. Is a 5-year minimum sojourn defensible, or should it be longer? This is the single parameter that most affects whether vaccinating 40-year-olds shows any benefit by year 30 of the simulation.
3. Are the smoking and alcohol RRs above consistent with the PI's clinical experience and his own published work?
4. How aggressive should the burn pit assumption be? The literature is genuinely thin; the PI's team has the credibility to take a position here.

---

## Cluster 6 — OPC outcomes (mortality, survival)

The PI's published work (Zevallos 2021 *Head Neck*) is the anchor for VA-specific values.

| Parameter | Meaning | Type | Initial estimate | Source | Tier |
|---|---|---|---|---|---|
| Distribution of stage at OPC diagnosis | Stage I / II / III / IV proportions | Distribution | Most diagnosed at stage III/IV; ~60–70% advanced | Zevallos 2021, SEER | 2 |
| 5-year HPV+ OPC survival (overall) | Overall survival proportion | Point + range | 70–80% in HPV+ OPC | SEER, AHNS | 2 |
| 5-year HPV+ OPC survival by stage | Stage-specific survival | Point per stage | I: 90%, II: 80%, III: 70%, IV: 50% (approx) | SEER | 2 |
| Annual mortality during active cancer phase | Per-year death probability while in `cancer_active` | Range | Currently 30%/yr in code; this is too high | Derive from 5-yr survival | 1 (the current value is a real bug) |
| Mortality of cancer survivors (post-5-year) | Excess vs. background mortality | Range | Slightly elevated; often modeled as background | Literature | 3 |
| Treatment effect (if modeled) | Treatment vs no-treatment differential | Point | Most VA OPC patients treated; subsume into baseline survival | Assumption | 3 |

**For PI:** the current code's 30%/year OPC mortality during active cancer implies ~17% 5-year survival, which is far below modern HPV+ OPC outcomes. We need to recalibrate to roughly 70–80% 5-year survival. Is the PI comfortable with the stage-specific values above, or does he have VA-specific numbers from his prior work?

---

## Cluster 7 — Vaccine efficacy

The "with vs without vaccine" comparison is the entire point of the model. These need to be solid.

| Parameter | Meaning | Type | Initial estimate | Source | Tier |
|---|---|---|---|---|---|
| Vaccine efficacy against incident HPV16/18 acquisition | Reduction in per-step acquisition for vaccinated naive agents | Range | 90% (range 70–95%) | Mid-Adult HPV trials, Castellsagué | 1 |
| Vaccine efficacy against persistent infection | Reduction in progression to persistent for vaccinated agents | Range | 85–95% (similar to acquisition) | Trial data | 1 |
| Vaccine efficacy if pre-existing infection at vaccination time | Effect on existing infection (vs. naive types) | Point | 0% on currently-infected strain; full on naive types | Trial data | 1 |
| Doses required for "full" efficacy | 2 vs 3 dose schedule | Point | 2 doses if start <15, 3 doses if start ≥15 (current ACIP); 1-dose evidence emerging | ACIP recommendations | 2 |
| Single-dose efficacy | Efficacy with only 1 dose | Range | 60–80% (recent evidence) | Kreimer et al. | 3 |
| Time to protection after vaccination | Lag from dose to immunity | Point | 0–1 month; ignorable over 30-yr horizon | Trial data | 3 |
| Annual waning of vaccine protection | Per-year decline in efficacy | Range | 0–1% per year | Long-term follow-up data; minimal evidence of waning | 3 |
| Age-specific efficacy modifier | Different efficacy by age at vaccination | Range | Slightly lower in mid-adults; subsume into above ranges | Trial data | 3 |

**For PI:** is there a preference for the 9-valent vaccine assumptions vs. the older quadrivalent? Most current US use is 9-valent. The efficacy parameters above are roughly the same; the range of HPV types covered differs. For OPC modeling specifically, HPV16 is the dominant target so this distinction matters less.

---

## Cluster 8 — Background mortality

| Parameter | Meaning | Type | Initial estimate | Source | Tier |
|---|---|---|---|---|---|
| All-cause mortality by age × sex | Background death rate, non-OPC causes | Function | VA actuarial tables; SSA life tables as fallback | VA Office of Mortality, CDC | 2 |
| Smoking adjustment to background mortality | Multiplier for current smokers | Point | ~1.5–2.0 RR | Literature on smoking mortality | 3 |
| Race/ethnicity adjustment | Differential mortality by race | Function | VA-specific if available | VA data | 3 (deferred per current scope) |

**For PI:** is there a preferred VA-specific mortality table, or is using SSA/CDC tables with a Veteran-specific adjustment factor acceptable?

---

## Parameters NOT being asked from PI in this meeting

Flagged here so the PI knows the dependency, but they come from elsewhere.

| Parameter | Source | Notes |
|---|---|---|
| Vaccination prevalence by age × sex × VISN at sim start | Aim 1 | Cohort initialization needs this; placeholder until Aim 1 produces |
| Smoking prevalence by age × sex × VISN | Aim 1 | |
| Alcohol use prevalence | Aim 1 | |
| VISN distribution of cohort | Aim 1 | |
| Rurality (RUCA) distribution | Aim 1 | |
| Burn pit exposure prevalence | Aim 1 (PACT registry, ICD-10 Z77.*) | |
| Comorbidity distribution | Aim 1 | |
| Coverage targets / ramp-up curves for expansion scenarios | Modeling assumption (Option C) | Parked; will need separate discussion |
| Number of MC iterations, time step length, horizon | Computational | |
| Random seeds | Computational | |

---

## What to leave the meeting with

A minimum decision set:

1. **Persistence threshold:** 12 or 24 months. (Cluster 4)
2. **Dwell-time central tendency:** mean and rough shape. (Cluster 5, parameters 1–5)
3. **Smoking RR on progression:** the central value plus how wide a sensitivity range. (Cluster 5)
4. **Burn pit posture:** how aggressive an assumption to take, and what range to test. (Cluster 5)
5. **OPC survival recalibration:** confirm the 70–80% 5-year survival target replacing the current 17%. (Cluster 6)
6. **Vaccine efficacy point estimate:** 90% on acquisition, with what range for sensitivity. (Cluster 7)
7. **Pre-existing infection prevalence:** confirm NHANES values are acceptable as defaults, with smoking-stratified adjustment. (Cluster 1)

If the meeting only nails down 1, 2, 3, and 5, that's enough to start Option B. The rest can be plugged in with reasonable defaults and refined later.
