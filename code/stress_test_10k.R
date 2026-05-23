# stress_test_10k.R
# One-shot stress test at num_agents=10000 to verify simulator runs end-to-end.
# Saves plots to PDF; prints key diagnostics to console.
# Do NOT commit this file to production.

suppressPackageStartupMessages({
  pacman::p_load(dplyr, ggplot2, tidyr, here, ggsci, ggrepel, data.table)
})

source(file.path(here(), "code", "helper_v3.R"))

set.seed(2026)

# --- Simulation settings (OVERRIDE num_agents for stress test) ----------
num_agents <- 1500000  # VHA male veterans 26-45 ~ 1.5M (policy-relevant scale)
sim_years  <- 75
age_min    <- 26
age_max    <- 45
max_age    <- 99
vaccination_age_caps <- c(26, 30, 35, 40, 45)
discount_rate <- 0.03

# --- All other parameters from simulator_v3.R (unchanged) ---------------
prop_smoker        <- 0.27
prop_heavy_alcohol <- 0.15

baseline_prev        <- 0.033
init_duration_geom_p <- 0.4

p_acquisition          <- 0.041
smoking_acquisition_RR <- 1.15
alcohol_acquisition_RR <- 1.43

p_clearance_short      <- 0.60
p_clearance_medium     <- 0.40
p_clearance_persistent <- 0.05
smoking_clearance_RR   <- 0.7

persistence_threshold_years  <- 2L
p_persistence_given_long_inf <- 0.020  # calibrated 2026-05-23

weibull_shape <- 3.0
weibull_scale <- 20.0
smoking_progression_RR  <- 1.5
alcohol_progression_RR  <- 1.3
smoking_alcohol_synergy <- 1.2

opc_mortality_annual          <- 0.045
opc_survivor_excess_mortality <- 0.01

VE_acquisition <- 0.90
VE_persistence <- 0.85

p_vaccinate <- 0.15

smoking_mortality_RR <- 2.0

vaccine_cost <- 550

# --- Run all scenarios --------------------------------------------------
cat("=== STRESS TEST: num_agents =", num_agents, "===\n\n")
t_start <- proc.time()

cat("Generating base population + mortality CRN draws...\n")
t0 <- proc.time()
base_pop   <- generate_population(num_agents)
mort_draws <- matrix(as.single(runif(num_agents * sim_years)),
                     nrow = num_agents, ncol = sim_years)
cat(sprintf("  Ready in %.1fs (mort_draws: %.0f MB)\n\n",
            (proc.time() - t0)[["elapsed"]], object.size(mort_draws) / 1e6))

results <- list()
for(cap in vaccination_age_caps) {
  cat(paste0("Running age cap ", cap, "...\n"))
  t0 <- proc.time()
  results[[as.character(cap)]] <- run_simulation(cap, base_pop = base_pop,
                                                 mort_draws = mort_draws)
  elapsed <- (proc.time() - t0)[["elapsed"]]
  cat(paste0("  Done in ", round(elapsed, 1), "s\n"))
}

total_elapsed <- (proc.time() - t_start)[["elapsed"]]
cat(paste0("\nAll scenarios completed in ", round(total_elapsed, 1), "s\n\n"))

# --- Key diagnostics -------------------------------------------------------
cat("=== DIAGNOSTIC: Status-quo scenario (cap=26) ===\n")
r26 <- results[["26"]]
ys  <- r26$yearly_stats

cat("\nFinal year (year 75) state distribution:\n")
final_row <- ys[nrow(ys), c("year", "n_healthy", "n_infected", "n_persistent", "n_cancer")]
print(final_row, row.names = FALSE)

cat("\nFirst 5 years - new infections, persistent, cancer per year:\n")
early <- ys[1:5, c("year", "n_new_infected", "n_new_persistent", "n_new_cancer")]
print(early, row.names = FALSE)

cat("\nTotal OPC cases and deaths over 75 years:\n")
cat("  Total new OPC:       ", sum(ys$n_new_cancer), "\n")
cat("  Total OPC deaths:    ", sum(ys$n_dead_opc), "\n")
cat("  Total all-cause dead:", sum(ys$n_dead), "\n")

cat("\nDiscounted totals (status-quo, cap=26):\n")
cat("  Total QALYs:         ", round(r26$total_qalys, 1), "\n")
total_cost_26 <- r26$total_vaccine_cost + r26$total_cancer_cost
cat("  Total costs (vax+ca):", format(round(total_cost_26), big.mark = ","), "USD\n")
cat("  Vaccine costs:       ", format(round(r26$total_vaccine_cost), big.mark = ","), "USD\n")
cat("  Cancer costs:        ", format(round(r26$total_cancer_cost),  big.mark = ","), "USD\n")

cat("\n--- Sanity checks ---\n")
cat("  Early annual new infections (expect ~300-400 for 10k agents at p_acq=0.041):\n")
cat("  Year 1:", ys$n_new_infected[1],
    " Year 2:", ys$n_new_infected[2],
    " Year 3:", ys$n_new_infected[3], "\n")
cat("  Persistent agents as % of new infections (lagged, expect ~10%):\n")
if(sum(ys$n_new_infected[1:70]) > 0)
  cat("  Ratio (total pers / total infected):",
      round(sum(ys$n_new_persistent) / sum(ys$n_new_infected) * 100, 1), "%\n")

cat("\n=== ICER TABLE (printed inside generate_icer_plot) ===\n")

# --- Save plots to PDF --------------------------------------------------
pdf_path <- file.path(here(), "code", "stress_test_10k_plots.pdf")
pdf(pdf_path, width=10, height=7)

tryCatch({
  plots <- generate_plots(results)
  print(plots$opc_cases_plot)
  print(plots$persistent_plot)
  print(plots$opc_deaths_plot)
  print(plots$costs_plot)
  print(plots$state_plot)
}, error = function(e) {
  cat("WARNING: generate_plots() failed:", conditionMessage(e), "\n")
})

tryCatch({
  icer_plot <- generate_icer_plot(results)
  print(icer_plot)
}, error = function(e) {
  cat("WARNING: generate_icer_plot() failed:", conditionMessage(e), "\n")
})

dev.off()
cat("\nPlots saved to:", pdf_path, "\n")
cat("\n=== STRESS TEST COMPLETE ===\n")
