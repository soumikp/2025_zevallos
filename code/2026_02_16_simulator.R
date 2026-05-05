rm(list = ls())
pacman::p_load(dplyr, ggplot2, tidyr, here, ggsci, ggpubfigs, patchwork, ggrepel)
source(file.path(here(), "code", "2026_02_16_helper.R"))

# Set random seed for reproducibility
set.seed(2026)

#### Simulation parameters ####
num_agents <- 100000         # Number of agents to simulate
sim_years <- 100             # Number of years to simulate
age_min <- 18               # Minimum age of agents
age_max <- 65               # Maximum age of agents
max_age <- 99               # Maximum possible age (will die if older)
vaccination_age_caps <- c(26, 30, 35, 40, 45)  # Different age caps to compare
opc_cost <- 135000          # Average cost of OPC treatment
vaccine_cost <- 600         # Cost of HPV vaccine (3 doses)
discount_rate <- 0.03       # Annual discount rate for costs and benefits

# Transition probabilities (these would be calibrated based on real data)
p_vaccinate <- 0.15          # Baseline probability of vaccination if eligible
p_infection_unvax <- 0.05  # Annual probability of HPV infection (unvaccinated)
p_infection_vax <- 0.002    # Annual probability of HPV infection (vaccinated)
vaccine_efficacy <- 0.9     # Vaccine efficacy against HPV infection

p_clearance_base <- 0.5     # Base probability of HPV infection clearance
p_persistence_to_opc <- 0.05 # Probability of persistent infection -> OPC
opc_mortality <- 0.3        # Annual probability of death from OPC

# Risk factor modifiers
smoking_infection_multiplier <- 1.5
smoking_persistence_multiplier <- 2.0
msm_infection_multiplier <- 2.0
prev_infection_multiplier <- 1.2


#### Run simulations for different age caps ####

results <- list()
for(age_cap in vaccination_age_caps) {
  cat(paste("Running simulation for age cap", age_cap, "\n"))
  results[[as.character(age_cap)]] <- run_simulation(age_cap)
}

plots <- generate_plots(results)
plots

icer_plot <- generate_icer_plot(results)
print(icer_plot)
