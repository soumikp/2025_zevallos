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
prop_male          <- 0.88      # VA Veterans 26-45 ~88% male (placeholder)
prop_smoker        <- 0.27      # Veteran smoking prevalence (placeholder)
prop_heavy_alcohol <- 0.15      # Heavy alcohol use (placeholder)

# --- PRE-EXISTING INFECTION (Sheet 1) -- TO BE SOURCED -----------
baseline_prev_male   <- 0.06    # NHANES oral oncogenic HPV in men (Gillison)
baseline_prev_female <- 0.011   # NHANES, women
init_duration_geom_p <- 0.4     # Geom(p) -> mean ~ 1.5y prior duration

# --- ACQUISITION (Sheet 2) -- TO BE SOURCED ----------------------
p_acquisition_male    <- 0.04   # Annual incidence men (HIM Study Kreimer)
p_acquisition_female  <- 0.01
smoking_acquisition_RR <- 1.5

# --- CLEARANCE (Sheet 3) -- TO BE SOURCED ------------------------
p_clearance_short      <- 0.60  # Annual clearance years 0-2
p_clearance_medium     <- 0.30  # Annual clearance years 2+ (still 'infected')
p_clearance_persistent <- 0.05  # Once in 'persistent', rare reversion
smoking_clearance_RR   <- 0.7   # Smoking REDUCES clearance (RR < 1)

# --- PERSISTENCE (Sheet 4) -- TO BE SOURCED ----------------------
persistence_threshold_years   <- 2L   # Standard: >24mo continuous infection
p_persistence_given_long_inf  <- 1.0  # If still infected at threshold,
# define as persistent (or set <1 for stochastic)

# --- LATENCY TO OPC (Sheet 5) -- TO BE SOURCED -------------------
# Weibull(shape=3, scale=20) -> mean ~ 17.9y, median ~ 17.7y
weibull_shape <- 3.0
weibull_scale <- 20.0
smoking_progression_RR  <- 2.0  # Reduces scale -> faster progression
alcohol_progression_RR  <- 1.5
smoking_alcohol_synergy <- 1.3  # Multiplicative on top of individual RRs
female_progression_RR   <- 0.5  # Women progress slower (lower OPC risk)

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

# --- COSTS (Sheet 10 NEW) -- TO BE SOURCED -----------------------
vaccine_cost <- 600            # Full series (3-dose) cost
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