# Next Steps — Updated After Parameter Table Completion

## What Has Been Done
- Parameter table fully built (10 sections, all parameters sourced)
- Male-only model decision confirmed
- Three code bugs identified and fixes specified
- Key parameter changes from v3 documented in project instruction

## Papers Still to Download and Upload to Project
1. Kreimer et al., Lancet 2013 — clearance rates
2. Pierce Campbell et al., Cancer Prev Res 2015 — HPV-16 persistence (Bug 1 source)
3. Bettampadi et al., Clin Infect Dis 2021 — smoking and clearance
4. Applebaum et al., J Natl Cancer Inst 2007 — smoking/alcohol in HPV+ OPC
5. Chaturvedi et al., J Clin Oncol 2018 — vaccine efficacy on oral HPV
6. Huh et al., Lancet 2017 — V503 trial adults 27–45
7. Laprise et al., Ann Intern Med 2020 — QALY weights and cost-effectiveness comparator
8. Jacobson et al., Head Neck Oncol 2012 — OPC treatment costs

## Free Resources to Access (No Download Needed)
- SSA Period Life Tables 2021: ssa.gov/oact/STATS/table4c6.html
- BLS CPI calculator: bls.gov/cpi
- CDC VFC vaccine pricing: cdc.gov/vaccines/programs/vfc

## First Message in the New Chat
> "The parameter table is complete. Let's now fix the three bugs in helper_v3.R and implement all parameter updates from the table. Start with Bug 1: change p_persistence_given_long_inf from 1.0 to 0.75. Then Bug 2: fix negative time-to-cancer for seeded persistent agents. Then Bug 3: fix the ICER dominated strategy removal. After all three bugs, implement the male-only simplification and the age-banded vaccination uptake."

## Step 1 — Set Up the Claude Project

1. Create a new Claude Project (not just a chat)
2. Paste the **Project Instruction** document as the project's system prompt
3. This instruction will persist across all chats in the project

---

## Step 2 — Upload These Files to the Project Directory

Upload all of the following. They should live in the project so every chat can see them.

### Code files (you already have these)
- [ ] `helper_v3.R`
- [ ] `simulator_v3.R`
- [ ] `2026_02_16_helper.R` (v1, reference only)
- [ ] `2026_02_16_simulator.R` (v1, reference only)

### Grant documents (you already have these)
- [ ] Specific Aims document
- [ ] Research Strategy / Research Plan
- [ ] Summary Statement (reviewer critiques PDF)

### Parameter table (needs work — see Step 3)
- [ ] `parameters.xlsx` — once you build it out per Step 3 below

---

## Step 3 — Build the Parameter Table Before Starting

The Excel file came in empty. Before coding, fill in what you can. Use one row per parameter.

**Columns to include:**
`Parameter Name | Symbol | Value | Unit | Distribution for PSA | Source | Notes`

**Parameters to fill in first (highest priority):**

| Parameter | Where to Find It |
|---|---|
| Oral oncogenic HPV prevalence in men aged 26–45 | Gillison et al. NHANES studies; aim for age-stratified if possible |
| Oral HPV prevalence in women 26–45 | Same source |
| Annual HPV acquisition rate, men | HIM Study (Kreimer et al.) |
| Annual HPV acquisition rate, women | Same |
| Clearance probability, years 0–2 | Ho et al.; Gravitt et al. |
| Clearance probability, years 2+ | Same |
| Probability of persistence given long infection | Literature; ~10–20% |
| Weibull shape and scale for time-to-cancer | Back-calculate from mean latency ~17–18 years; cite Chaturvedi, Gillison |
| HPV+ OPC 5-year survival | ~79%; cite Ang et al. NEJM 2010 |
| Annual OPC mortality (active treatment) | Back-calculate from 5-year survival |
| Vaccine efficacy — acquisition (VE_acq) | FUTURE II / V503 trial data; adults 24–45 |
| Vaccine efficacy — persistence (VE_pers) | Same trials |
| Veteran smoking prevalence | Odani et al. MMWR 2018; ~27% |
| Veteran heavy alcohol prevalence | VA survey data; ~15% |
| Smoking RR on acquisition | Meta-analysis; ~1.5 |
| Smoking RR on clearance (impairs it) | Literature; RR < 1, ~0.7 |
| Smoking RR on progression to cancer | Literature; ~2.0 |
| OPC treatment cost | Saxena et al. J Med Econ 2022 (already cited in grant) |
| Vaccine cost (3-dose series) | CDC/VA formulary; ~$600 |
| Burn pit exposure prevalence in Veterans | **Out of scope for this phase — skip** |
| Background mortality | SSA life tables, stratified by age and sex |
| Proportion male in VHA 26–45 cohort | ~88%; cite VA utilization data |

---

## Step 4 — Gather These Key Papers

Pull the full text (PDF) if you can; at minimum have the key numbers ready.

1. **Chidambaram et al., JAMA Oncology 2023** — your team's prior vaccination prevalence study (already cited)
2. **Zevallos et al., Head & Neck 2021** — VA OPC incidence trends (calibration target)
3. **Ang et al., NEJM 2010** — HPV+ OPC survival (calibration target)
4. **Gillison et al., J Clin Oncol 2015** — oral HPV epidemiology
5. **Kreimer et al. / HIM Study** — male HPV acquisition rates
6. **Saxena et al., J Med Econ 2022** — VA HPV cancer cost burden (already cited)
7. **Laprise et al., Ann Intern Med 2020** — cost-effectiveness of HPV vaccination through age 45 (general population; compare against your Veteran-specific results)
8. **Kim et al., PLoS Med 2021** — vaccination for adults 30–45, cost-effectiveness (compare)
9. **V503 / Gardasil 9 trial data** — vaccine efficacy in adults 27–45
10. **Odani et al., MMWR 2018** — Veteran smoking prevalence

---

## Step 5 — First Message in the New Chat

Once the project is set up with the instruction and files uploaded, open a new chat and say:

> "Let's start with Step 1: fix the three biological logic bugs in helper_v3.R. Start with Bug 1 (deterministic persistence), then Bug 2 (negative time-to-cancer), then Bug 3 (ICER frontier). Show me the corrected code sections with explanation for each fix."

Work through each bug and confirm the fix before moving to the next feature addition.
