# HPV Vaccination Simulation Model for VHA
# Agent-based model to assess cost-effectiveness of extending vaccination age cap

#### housekeeping ####

rm(list = ls())
pacman::p_load(dplyr, ggplot2, tidyr, here, ggsci, ggpubfigs, patchwork)

# Set random seed for reproducibility
set.seed(2025)

#### Simulation parameters ####
num_agents <- 5000         # Number of agents to simulate
sim_years <- 100             # Number of years to simulate
age_min <- 18               # Minimum age of agents
age_max <- 65               # Maximum age of agents
max_age <- 99               # Maximum possible age (will die if older)
vaccination_age_caps <- c(26, 30, 35, 40, 45)  # Different age caps to compare
opc_cost <- 150000          # Average cost of OPC treatment
vaccine_cost <- 450         # Cost of HPV vaccine (3 doses)
discount_rate <- 0.03       # Annual discount rate for costs and benefits

# Transition probabilities (these would be calibrated based on real data)
p_vaccinate <- 0.1          # Baseline probability of vaccination if eligible
p_infection_unvax <- 0.015  # Annual probability of HPV infection (unvaccinated)
p_infection_vax <- 0.002    # Annual probability of HPV infection (vaccinated)
vaccine_efficacy <- 0.9     # Vaccine efficacy against HPV infection

p_clearance_base <- 0.5     # Base probability of HPV infection clearance
p_persistence_to_opc <- 0.01 # Probability of persistent infection -> OPC
opc_mortality <- 0.3        # Annual probability of death from OPC

# Risk factor modifiers
smoking_infection_multiplier <- 1.5
smoking_persistence_multiplier <- 2.0
msm_infection_multiplier <- 2.0
prev_infection_multiplier <- 1.2


#### Run simulations for different age caps ####

source(file.path(here(), "code", "2025_04_21_helper.R"))

results <- list()
for(age_cap in vaccination_age_caps) {
  cat(paste("Running simulation for age cap", age_cap, "\n"))
  results[[as.character(age_cap)]] <- run_simulation(age_cap)
}



# #### Calculate ICER #### this needs more work
# icer_results <- calculate_icer(results)
# print(icer_results)

# Generate and display plots
plots <- generate_plots(results)

layout <- "
AACC
BBCC
"

plot_sim <- (plots$opc_cases_plot + plots$opc_deaths_plot + plots$costs_plot) +
  plot_layout(design = layout)

factor = 1.650
# ggsave(file.path("/Users/soumik/Desktop/2025_11_18_simulation.pdf"), 
#        plot_sim, 
#        height = factor*8.5, 
#        width = factor*11, 
#        units = "in")

ggsave(file.path(file.path(here(), "documents", "2025_11_18_simPlots.pdf")), 
       plot_sim, 
       height = factor*8.5, 
       width = factor*11, 
       units = "in")

# # Save results (skipping for now, still testing)
# save(results, 
#      #icer_results, 
#      plots, file = "hpv_vaccination_simulation_results.RData")

# # Generate summary report
# summary_report <- function(results_list, icer_df) {
#   cat("HPV Vaccination Simulation Model Summary Report\n")
#   cat("================================================\n\n")
#   
#   cat("Simulation Parameters:\n")
#   cat(paste("- Number of agents:", num_agents, "\n"))
#   cat(paste("- Simulation years:", sim_years, "\n"))
#   cat(paste("- Vaccination age caps evaluated:", paste(vaccination_age_caps, collapse=", "), "\n\n"))
#   
#   cat("Cost-Effectiveness Results:\n")
#   print(icer_df %>% select(age_cap, total_cost, opc_cases, opc_deaths, icer_cases, icer_deaths))
#   
#   cat("\nTotal Cases Averted by Increasing Age Cap:\n")
#   for(i in 2:length(vaccination_age_caps)) {
#     prev_cap <- vaccination_age_caps[i-1]
#     curr_cap <- vaccination_age_caps[i]
#     cases_diff <- icer_df$inc_cases_averted[i]
#     deaths_diff <- icer_df$inc_deaths_averted[i]
#     cost_diff <- icer_df$inc_cost[i]
#     
#     cat(paste0("- Increasing from ", prev_cap, " to ", curr_cap, " years: ", 
#                cases_diff, " cases and ", deaths_diff, " deaths averted at additional cost of $", 
#                format(cost_diff, big.mark=","), "\n"))
#   }
#   
#   cat("\nOptimal Age Cap Recommendation:\n")
#   # Find the age cap with the lowest ICER below a threshold (e.g., $100,000 per case averted)
#   threshold <- 100000
#   optimal <- icer_df %>% 
#     filter(!is.na(icer_cases) & icer_cases < threshold) %>%
#     arrange(desc(age_cap)) %>%
#     slice(1)
#   
#   if(nrow(optimal) > 0) {
#     cat(paste0("Based on a willingness-to-pay threshold of $", format(threshold, big.mark=","), 
#                " per case averted, the optimal vaccination age cap is ", optimal$age_cap, " years.\n"))
#   } else {
#     cat("No age cap meets the cost-effectiveness threshold.\n")
#   }
# }
# 
# # Generate summary report
# summary_report(results, icer_results)