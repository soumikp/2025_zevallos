# HPV Microsimulation — Parameter Table
*Last updated: May 2026 | All costs in 2024 USD | Discount rate applied to costs and QALYs*

---

## Section 1 — Baseline HPV Prevalence (Seed Infections)

| Parameter | Symbol in R | Value | Unit | PSA Distribution | Source | Notes |
|---|---|---|---|---|---|---|
| Oral oncogenic HPV prevalence, men | `baseline_prev_male` | 0.033 | Proportion | Beta(106, 3097) | Giuliano et al., JAMA Otolaryngol 2023 (PROGRESS US); n=1,423 men, 21 US states, ages 18–60 | US-specific HR genotypes. Current v3 uses 0.06 — update needed. Age-stratified values below used for calibration. |
| Age-stratified prevalence, men 18–30 | *(calibration target)* | 0.017 | Proportion | — | Giuliano et al., JAMA Otolaryngol 2023, Table 2 | HR HPV only; for baseline initialization check |
| Age-stratified prevalence, men 31–40 | *(calibration target)* | 0.030 | Proportion | — | Giuliano et al., JAMA Otolaryngol 2023, Table 2 | |
| Age-stratified prevalence, men 41–50 | *(calibration target)* | 0.023 | Proportion | — | Giuliano et al., JAMA Otolaryngol 2023, Table 2 | |
| Age-stratified prevalence, men 51–60 | *(calibration target)* | 0.075 | Proportion | — | Giuliano et al., JAMA Otolaryngol 2023, Table 2 | Rise with age is a key calibration anchor |
| Initial infection duration (geom p) | `init_duration_geom_p` | 0.4 | — | Beta(4, 6) | Placeholder | Geometric mean ~1.5y prior duration. Refine when clearance literature added. |

---

## Section 2 — HPV Acquisition

| Parameter | Symbol in R | Value | Unit | PSA Distribution | Source | Notes |
|---|---|---|---|---|---|---|
| Annual HPV acquisition probability, men | `p_acquisition_male` | 0.041 | Annual probability | Beta(138, 3219) | Dube Mandishora et al., Nat Microbiol 2024 (HIM Study US subcohort, n=834); 3.46 per 1,000 person-months → 1−exp(−0.00346×12) = 0.041/yr | **Acquisition rate does NOT vary by age** (log-rank p=0.36). Justifies constant rate across 26–45 cohort. Current v3 uses 0.04 — update to 0.041. |
| Smoking RR on acquisition | `smoking_acquisition_RR` | 1.15 | Ratio | LogNormal(ln(1.15), 0.14) | Dube Mandishora et al., Nat Microbiol 2024, Table 4: current smoker aHR 1.15 (95% CI 0.87–1.51) | Not statistically significant. Smoking effect is primarily on clearance/persistence, not acquisition. Current v3 uses 1.5 — reduce to 1.15. |
| Alcohol RR on acquisition (heavy) | `alcohol_acquisition_RR` | 1.43 | Ratio | LogNormal(ln(1.43), 0.17) | Dube Mandishora et al., Nat Microbiol 2024, Table 4: >60 drinks/month aHR 1.43 (95% CI 1.02–2.01) | Statistically significant. Maps to `alcohol_heavy` flag in v3. |

---

## Section 3 — Clearance

| Parameter | Symbol in R | Value | Unit | PSA Distribution | Source | Notes |
|---|---|---|---|---|---|---|
| Annual clearance probability, infection duration 0–1 year | `p_clearance_short` | 0.60 | Annual probability | Beta(60, 40) | Kreimer et al., Lancet 2013 (HIM cohort); ~60% of incident oral oncogenic HPV infections clear within 12 months | **Cited in Dube Mandishora 2024 and Damgacioglu 2022 — full paper not uploaded. Recommend pulling Kreimer 2013 to verify.** Current v3 value 0.60 confirmed. |
| Annual clearance probability, infection duration 1–2 years | `p_clearance_medium` | 0.40 | Annual probability | Beta(40, 60) | Derived: if 60% clear by year 1 (40% remain) and ~80% total clear by year 2, then ~50% of remaining agents clear in year 2 → 0.20/0.40 = 0.50; using conservative 0.40 | **Derived, not directly sourced.** Consistent with HIM Study showing rapid early clearance slowing over time. Current v3 value 0.30 — recommend increasing to 0.40. |
| Persistence threshold (years of continuous infection) | `persistence_threshold_years` | 2 | Years | — | Standard clinical/epidemiologic definition; used by Damgacioglu et al., Lancet Reg Health Americas 2022; consistent with Pierce Campbell et al., Cancer Prev Res 2015 | Annual time steps mean this is operationalized as infection_duration ≥ 2L in v3 code. |
| Probability of transitioning to persistent state given infection duration ≥ 2 years | `p_persistence_given_long_inf` | 0.75 | Proportion | Beta(15, 5) | Derived: ~20% of HPV-16 infections persist >24 months (Pierce Campbell et al., Cancer Prev Res 2015, cited in Dube Mandishora 2024); ~20% of infections survive to 2 years after clearance in years 1–2; 15/20 = 0.75 | **This is the critical Bug 1 fix.** Current v3 value is 1.0 (deterministic — biologically wrong). Updating to 0.75. Recommend sensitivity analysis over range 0.50–0.90. **Verify Pierce Campbell 2015 directly.** |
| Annual clearance probability from persistent state | `p_clearance_persistent` | 0.05 | Annual probability | Beta(5, 95) | Placeholder; consistent with Damgacioglu 2022 modeling framework which treats persistence as near-irreversible | Rare spontaneous reversion. Current v3 value 0.05 retained. |
| Smoking RR on clearance (reduces it) | `smoking_clearance_RR` | 0.70 | Ratio | LogNormal(ln(0.70), 0.15) | Bettampadi et al., Clin Infect Dis 2021 (factors associated with persistence/clearance in HIM Study); cited in Dube Mandishora 2024 | RR < 1 means smokers are less likely to clear. **Full paper not uploaded — recommend pulling Bettampadi 2021 to verify exact estimate.** Current v3 value 0.70 retained. |

---

## Section 4 — Persistence to OPC (Weibull Latency)

| Parameter | Symbol in R | Value | Unit | PSA Distribution | Source | Notes |
|---|---|---|---|---|---|---|
| Weibull shape parameter | `weibull_shape` | 3.0 | — | Gamma(9, 3) | Consistent with Damgacioglu et al., Lancet Reg Health Americas 2022 (calibrated OPC natural history model); grant states 15–20 year mean latency | Shape=3 gives unimodal distribution — biologically appropriate (cancer risk rises then falls with increasing persistent infection duration). Current v3 value 3.0 retained. |
| Weibull scale parameter | `weibull_scale` | 20.0 | Years | Gamma(16, 1.25) | Derived to match mean latency ~17.9 years [mean = scale × Γ(1+1/shape) = 20 × Γ(1.33) ≈ 17.9y]; consistent with grant text and Chaturvedi et al., J Clin Oncol 2011 | OPC peak diagnosis age ~60–70 in men (Damgacioglu 2022); HPV acquired throughout life (HIM Study); implies 15–30y latency from persistent infection. Current v3 value 20.0 retained. Calibration target: modeled OPC incidence should match VA and SEER age-specific rates. |
| Smoking RR on progression (reduces Weibull scale → faster cancer) | `smoking_progression_RR` | 1.5 | Ratio | LogNormal(ln(1.5), 0.20) | **Revised downward from v3 value of 2.0.** For HPV+ OPC specifically, smoking is a weaker driver than for HPV− OPC. Applebaum et al., J Natl Cancer Inst 2007 (cited in Damgacioglu 2022): lack of association of alcohol and tobacco with HPV16-associated HNC. Use conservative 1.5 as upper bound. | **Important nuance:** smoking and alcohol are strong risk factors for HPV− OPC but evidence is weak for HPV+ OPC. This model simulates HPV+ OPC only. Flag for sensitivity analysis. |
| Alcohol RR on progression | `alcohol_progression_RR` | 1.3 | Ratio | LogNormal(ln(1.3), 0.20) | **Revised downward from v3 value of 1.5.** Same rationale as smoking — weaker effect in HPV+ OPC. Applebaum et al., J Natl Cancer Inst 2007. | Placeholder; recommend pulling Applebaum 2007 to verify. |
| Smoking × alcohol synergy multiplier | `smoking_alcohol_synergy` | 1.2 | Ratio | LogNormal(ln(1.2), 0.15) | Placeholder; v3 current value 1.3 slightly reduced to reflect weak individual effects | Given weak individual RRs above, synergy term should also be modest. Consider removing entirely in a simplified model version. |
| Bug 2 fix — minimum remaining time-to-cancer for seeded persistent agents | *(code logic)* | max(ttc − accrued, 1L) | Years | — | Logical constraint | **Bug 2 fix:** prevents negative time-to-cancer values at simulation start. Agents seeded as persistent at baseline have already accrued time; remaining TTC = max(sampled TTC − accrued duration, 1 year). |

---

## Section 5 — OPC Outcomes & Mortality

| Parameter | Symbol in R | Value | Unit | PSA Distribution | Source | Notes |
|---|---|---|---|---|---|---|
| HPV+ OPC 5-year survival | *(calibration target)* | 0.79 | Proportion | — | Ang et al., N Engl J Med 2010; n=323 patients with OPC, 58% HPV+ with 5-year OS ~79% vs 46% for HPV− | **Primary calibration target for cancer state.** VA-specific survival data not yet available — update from Aim 1 CDW analysis when complete. |
| Annual OPC mortality, active treatment (years 1–5) | `opc_mortality_annual` | 0.045 | Annual probability | Beta(45, 955) | Back-calculated: (1−0.045)^5 ≈ 0.794, consistent with Ang et al. 5-year OS of 79% for HPV+ OPC | Clean back-calculation from Ang 2010. Current v3 value 0.045 confirmed. |
| Annual excess mortality, OPC survivor (years 5+) | `opc_survivor_excess_mortality` | 0.010 | Annual probability | Beta(10, 990) | Placeholder; reflects late recurrence and second primary risk in long-term HNC survivors | No strong VA-specific source. Update from CDW when available. General HNC survivorship literature suggests 1–2% annual excess risk beyond 5 years. |
| OPC diagnosis cost (one-time) | `COST_OPC_DIAGNOSIS` | 25000 | 2024 USD | Gamma(25, 1000) | Saxena et al., J Med Econ 2022 (VA HPV cancer cost burden, cited in grant) | **Recommend pulling Saxena 2022 to verify exact figure and update to 2024 USD using CPI adjustment.** |
| Annual OPC treatment cost, active phase (years 1–5) | `COST_ANNUAL_CANCER_TX` | 30000 | 2024 USD | Gamma(30, 1000) | Saxena et al., J Med Econ 2022; Jacobson et al., Head Neck Oncol 2012 (both cited in grant) | VA treatment costs may differ from commercial insurance estimates in Jacobson. Update from Aim 1 when available. |
| Annual OPC survivor follow-up cost (years 5+) | `COST_ANNUAL_SURVIVOR` | 2000 | 2024 USD | Gamma(2, 1000) | Placeholder; consistent with routine surveillance costs in HNC survivors | Low priority for sensitivity — small absolute contribution to total cost. |
| OPC incidence rate, US men (calibration target) | *(calibration target)* | 8.0 | Per 100,000 men/year | — | Damgacioglu et al., Lancet Reg Health Americas 2022; peak projected ~9.8/100,000 in early 2030s; current rate ~8/100,000 | Use as external calibration check on simulated OPC incidence. VA-specific rate (Zevallos et al., Head Neck 2021) available but holding for Aim 1 integration. |

---

## Section 6 — Vaccine Efficacy

| Parameter | Symbol in R | Value | Unit | PSA Distribution | Source | Notes |
|---|---|---|---|---|---|---|
| VE against oral HPV acquisition (vaccinated vs unvaccinated) | `VE_acquisition` | 0.90 | Proportion reduction | Beta(90, 10) | Damgacioglu et al., Lancet Reg Health Americas 2022 (base case assumption); Chaturvedi et al., J Clin Oncol 2018 (post-hoc RCT analysis showing ~90% reduction in vaccine-type oral HPV among vaccinated young adult men); Herrero et al., PLoS One 2013 (Costa Rica bivalent vaccine RCT, oral HPV) | 90% reduction applied to `p_acquisition_male` for vaccinated agents. Current v3 value 0.90 confirmed. **Important:** this estimate is primarily from younger vaccinated cohorts. Evidence in 27–45 age group is immunogenicity-based (non-inferior antibody titers), not direct clinical efficacy. Flag as key sensitivity parameter. |
| VE against transition from infected to persistent (vaccinated breakthrough infections) | `VE_persistence` | 0.85 | Proportion reduction | Beta(85, 15) | Biologically plausible extrapolation from vaccine mechanism (prevents E6/E7 oncoprotein expression in breakthrough infections); consistent with cervical HPV persistence data from FUTURE II trial | **No direct oral HPV persistence trial data for this parameter.** This is the weakest-sourced parameter in the model. Sensitivity range 0.60–0.95 strongly recommended. Current v3 value 0.85 retained with caution. |
| Vaccine efficacy, adults 27–45 vs younger cohorts | *(modifier — see notes)* | Non-inferior | — | — | FDA approval of Gardasil 9 for ages 27–45 (October 2018) based on V503 trial extension; Huh et al., Lancet 2017 (V503 mid-adult women 27–45: immunogenicity non-inferior to 16–26 group) | **No efficacy discount applied for age 27–45 in base case** — consistent with non-inferiority immunogenicity data and FDA approval rationale. However, real-world effectiveness may be lower due to prior HPV exposure. Model sensitivity analysis should test a 20–30% VE reduction for the 40–45 sub-cohort. |
| Vaccine cost (full 3-dose series) | `vaccine_cost` | 600 | 2024 USD | Gamma(6, 100) | CDC VFC/commercial pricing; consistent with grant text and prior modeling studies (Kim et al., PLoS Med 2021; Laprise et al., Ann Intern Med 2020) | VA may negotiate lower pricing. Update from VA formulary when available. Current v3 value $600 retained. |

---

## Section 8 — Background Mortality

| Parameter | Symbol in R | Value | Unit | PSA Distribution | Source | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |

---

## Section 7 — Vaccination Uptake

| Parameter | Symbol in R | Value | Unit | PSA Distribution | Source | Notes |
|---|---|---|---|---|---|---|
| Annual vaccination probability, men aged 26–30 | `p_vaccinate_2630` | 0.08 | Annual probability | Beta(8, 92) | Derived: Chidambaram et al., JAMA Oncol 2023 (18.7% of male Veterans 18–26 ever vaccinated over ~3y observation → ~6%/yr); slightly higher for 26–30 given shared decision-making eligibility post-2019 | **Aim 1 will replace this.** Current v3 uses single flat p_vaccinate=0.15 regardless of age — this overestimates uptake in older bands and needs to be age-stratified. |
| Annual vaccination probability, men aged 31–35 | `p_vaccinate_3135` | 0.05 | Annual probability | Beta(5, 95) | Extrapolated: uptake expected to decline with age beyond 30; consistent with general population pattern (Boersma & Black, NCHS Data Brief 2020) | **Placeholder — Aim 1 primary deliverable.** |
| Annual vaccination probability, men aged 36–40 | `p_vaccinate_3640` | 0.03 | Annual probability | Beta(3, 97) | Extrapolated: further decline; shared decision-making guidelines less consistently applied at older ages | **Placeholder — Aim 1 primary deliverable.** |
| Annual vaccination probability, men aged 41–45 | `p_vaccinate_4145` | 0.02 | Annual probability | Beta(2, 98) | Extrapolated: lowest uptake band; consistent with grant's description of "strikingly low" rates in mid-adult Veterans | **Placeholder — Aim 1 primary deliverable.** |
| Status quo vaccination age cap | *(scenario parameter)* | 26 | Years | — | CDC ACIP recommendation; Meites et al., MMWR 2019 | Baseline scenario. Agents eligible for vaccination only if age ≤ cap in each scenario. |
| Expanded vaccination age caps (scenarios) | *(scenario parameters)* | 30, 35, 40, 45 | Years | — | Grant Aim 2 design | Four alternative policy scenarios modeled. |
| Veteran HPV vaccination prevalence, males 18–26 (external calibration) | *(calibration anchor)* | 0.187 | Proportion ever vaccinated | — | Chidambaram et al., JAMA Oncol 2023 | Team's own published estimate. Only available published VA-specific figure. Use to anchor the 26–30 band uptake rate above. |

---

## Section 10 — Costs

| Parameter | Symbol in R | Value | Unit | PSA Distribution | Source | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |

---

## Section 11 — Cohort Composition & Risk Factors

| Parameter | Symbol in R | Value | Unit | PSA Distribution | Source | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |

---

*PSA = Probabilistic Sensitivity Analysis. Distributions assigned for Monte Carlo uncertainty analysis.*
