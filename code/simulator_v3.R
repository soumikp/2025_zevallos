# simulator_v3.R
# Parameter declarations + simulation run
# Pairs with helper_v3.R

rm(list = ls())
pacman::p_load(dplyr, ggplot2, tidyr, here, ggsci, ggrepel)
source(file.path(here(), "code", "helper_v3.R"))

set.seed(2026)

# --- SIMULATION SETTINGS (Sheet 11) ------------------------------
num_agents <- 100000
sim_years  <- 75
age_min    <- 26                # Grant: Veterans 26-45
age_max    <- 45
max_age    <- 99
vaccination_age_caps <- c(26, 30, 35, 40, 45)
discount_rate <- 0.03           # Applied to costs AND QALYs

# --- COHORT COMPOSITION ------------------------------------------
# Model is male-only (see project instruction): VHA OPC burden is
# overwhelmingly male; avoids poorly-sourced female natural history.
prop_smoker        <- 0.27      # Veteran smoking prevalence (placeholder)
prop_heavy_alcohol <- 0.15      # Heavy alcohol use (placeholder)

# --- PRE-EXISTING INFECTION (Sheet 1) -----------------------------
# Oral oncogenic HPV prevalence in US men (Giuliano et al. JAMA
# Otolaryngol 2023, PROGRESS US, n=1,423). Age-stratified anchors:
# 18-30 -> 0.017, 31-40 -> 0.030, 41-50 -> 0.023, 51-60 -> 0.075.
# 0.033 is the cohort-wide proportion; v3 used 0.06 (over-stated).
baseline_prev        <- 0.033
init_duration_geom_p <- 0.4     # Geom(p) -> mean ~ 1.5y prior duration

# --- ACQUISITION (Sheet 2) ---------------------------------------
# Dube Mandishora et al., Nat Microbiol 2024 (HIM US subcohort, n=834):
# 3.46 per 1,000 person-months -> 1-exp(-0.00346*12) = 0.041/yr.
# Acquisition rate does NOT vary by age in HIM (log-rank p=0.36).
p_acquisition          <- 0.041
smoking_acquisition_RR <- 1.15  # Dube Mandishora 2024 aHR 1.15 (not sig.)
alcohol_acquisition_RR <- 1.43  # Dube Mandishora 2024 aHR 1.43 (sig.)

# --- CLEARANCE (Sheet 3) -----------------------------------------
# Kreimer Lancet 2013 (HIM): ~60% incident oral oncogenic HPV clears
# by 12mo. Year-2 conditional clearance derived in param table notes.
p_clearance_short      <- 0.60  # Annual clearance years 0-1
p_clearance_medium     <- 0.40  # Annual clearance year 2+ (still 'infected')
p_clearance_persistent <- 0.05  # Once in 'persistent', rare reversion
smoking_clearance_RR   <- 0.7   # Smoking REDUCES clearance (RR < 1)

# --- PERSISTENCE (Sheet 4) ---------------------------------------
persistence_threshold_years   <- 2L   # Standard: >24mo continuous infection
# Bug 1 fix: ONE-SHOT roll at the moment infection_duration crosses
# the 2-year threshold (NOT a per-year hazard). Value derived from
# Pierce Campbell 2015 (HIM Study) — see param table.
p_persistence_given_long_inf  <- 0.40

# --- LATENCY TO OPC (Sheet 5) ------------------------------------
# Weibull(shape=3, scale=20) -> mean ~ 17.9y, median ~ 17.7y.
# Smoking/alcohol RRs revised down from v3: HPV+ OPC is less driven
# by tobacco/alcohol than HPV- OPC (Applebaum 2007, cited in
# Damgacioglu 2022). 1.5/1.3 are conservative upper bounds.
weibull_shape <- 3.0
weibull_scale <- 20.0
smoking_progression_RR  <- 1.5  # Reduces scale -> faster progression
alcohol_progression_RR  <- 1.3
smoking_alcohol_synergy <- 1.2  # Multiplicative on top of individual RRs

# --- OPC OUTCOMES (Sheet 6) -- TO BE SOURCED ---------------------
# 0.045 annual mortality -> 5y survival ~ (1-0.045)^5 ~ 79%, matching HPV+ OPC
opc_mortality_annual          <- 0.045
opc_survivor_excess_mortality <- 0.01

# --- VACCINE EFFICACY (Sheet 7) -- TO BE SOURCED -----------------
VE_acquisition <- 0.90         # Reduction in acquisition probability
VE_persistence <- 0.85         # Reduction in acute->persistent transition

# --- VACCINATION UPTAKE (Sheet 9 NEW) -- FROM AIM 1 --------------
p_vaccinate <- 0.15            # Annual prob of vax if eligible (placeholder)

# --- BACKGROUND MORTALITY (Sheet 8) -- TO BE SOURCED -------------
smoking_mortality_RR <- 2.0

# --- COSTS (Sheet 10 NEW) -- VACCINE COST FROM CDC 2024 ----------
# Gardasil 9 adult CDC contract price $182.79/dose x 3 doses = $548.38,
# rounded to $550. Source: CDC Vaccine Price List, Dec 1 2024 archive.
# VA pricing tracks federal supply schedule. For private-sector
# sensitivity, use $923 ($307.61 x 3). See param table Section 10.
vaccine_cost <- 550            # Full series (3-dose) cost, 2024 USD
# COST_OPC_DIAGNOSIS, COST_ANNUAL_CANCER_TX, COST_ANNUAL_SURVIVOR in helper.R


# --- Run scenarios -----------------------------------------------
results <- list()
for(cap in vaccination_age_caps) {
  cat(paste("Running age cap", cap, "...\n"))
  results[[as.character(cap)]] <- run_simulation(cap)
}

plots <- generate_plots(results)
plots$opc_cases_plot
plots$persistent_plot
plots$opc_deaths_plot
plots$costs_plot
plots$state_plot

icer_plot <- generate_icer_plot(results)
print(icer_plot)