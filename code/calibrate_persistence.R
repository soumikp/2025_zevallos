# calibrate_persistence.R
# Grid search on p_persistence_given_long_inf to match VA HPV+ OPC incidence.
#
# Rationale for Option B (vs adjusting weibull_scale):
#   - Keep weibull_scale=20 (mean latency ~18y), consistent with reviewer
#     comment that latency is "likely 10-30 years" and published literature.
#   - Campbell 2015 (n=23 HIM Study) gave 0.40; that cohort was high-risk
#     and small. A lower value for the broader VA male population is
#     biologically defensible and is the calibration lever here.
#
# Calibration target (Saxena et al. J Med Econ 2022, HPV+ fraction ~70%):
#   Overall VA OPC:  86-126 per million/yr (all-OPC) -> 60-88/million HPV+
#                    = 6-9 per 100,000 PY
#   Peak (age 55-64): 146-241/million (all-OPC) -> ~102-169/million HPV+
#
# Grid: 0.02, 0.03, 0.05, 0.08, 0.10, 0.15, 0.20
# Expected crossing near 0.02-0.05 (linear scaling from current 0.40 -> ~130/100k)

suppressPackageStartupMessages(
  pacman::p_load(data.table, dplyr, ggplot2, ggsci, scales, ggrepel, tidyr)
)
source(file.path(here::here(), "code", "helper_v3.R"))

# --- Fixed parameters (all from simulator_v3.R, weibull_scale stays 20) ---
num_agents <- 500000
sim_years  <- 75
age_min    <- 26; age_max <- 45; max_age <- 99
discount_rate <- 0.03

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

persistence_threshold_years <- 2L
weibull_shape <- 3.0
weibull_scale <- 20.0           # FIXED — consistent with 10-30y latency lit

smoking_progression_RR  <- 1.5
alcohol_progression_RR  <- 1.3
smoking_alcohol_synergy <- 1.2

opc_mortality_annual          <- 0.045
opc_survivor_excess_mortality <- 0.01

VE_acquisition <- 0.90; VE_persistence <- 0.85
p_vaccinate    <- 0.15
smoking_mortality_RR <- 2.0
vaccine_cost   <- 550

# --- Calibration target --------------------------------------------------
target_low  <- 6
target_high <- 9

# --- Grid ----------------------------------------------------------------
persist_vals <- c(0.02, 0.03, 0.05, 0.08, 0.10, 0.15, 0.20)

results_cal <- data.frame(
  p_persistence      = numeric(),
  total_opc_cases    = numeric(),
  total_person_years = numeric(),
  incidence_per_100k = numeric(),
  incidence_yr20_40  = numeric(),
  stringsAsFactors   = FALSE
)

cat(sprintf("%-16s  %-10s  %-14s  %-20s  %-20s\n",
            "p_persistence", "OPC_cases", "person_yrs",
            "incid/100k(overall)", "incid/100k(yr20-40)"))
cat(strrep("-", 85), "\n")

for (pv in persist_vals) {
  p_persistence_given_long_inf <- pv
  set.seed(2026)

  t0  <- proc.time()
  res <- run_simulation(age_cap = 26)
  elapsed <- round((proc.time() - t0)[["elapsed"]], 1)

  ys <- res$yearly_stats
  ys$n_alive_eoy <- ys$n_healthy + ys$n_infected + ys$n_persistent + ys$n_cancer

  total_py  <- sum(ys$n_alive_eoy)
  total_opc <- sum(ys$n_new_cancer)
  inc_overall <- total_opc / total_py * 100000

  window     <- ys[ys$year >= 20 & ys$year <= 40, ]
  inc_window <- sum(window$n_new_cancer) / sum(window$n_alive_eoy) * 100000

  results_cal <- rbind(results_cal, data.frame(
    p_persistence      = pv,
    total_opc_cases    = total_opc,
    total_person_years = round(total_py),
    incidence_per_100k = round(inc_overall, 2),
    incidence_yr20_40  = round(inc_window, 2)
  ))

  cat(sprintf("p=%-12.3f  cases=%-8d  PY=%-12.0f  overall=%-10.2f  yr20-40=%-10.2f  [%.1fs]\n",
              pv, total_opc, total_py, inc_overall, inc_window, elapsed))
}

cat(strrep("-", 85), "\n")
cat(sprintf("\nCalibration target: %.0f-%.0f per 100,000 PY (VA HPV+ OPC overall)\n",
            target_low, target_high))
cat(sprintf("  Peak age 55-64 HPV+ OPC target: ~10-17 per 100,000 PY\n\n"))

# Bracket
above <- results_cal[results_cal$incidence_per_100k > target_high, ]
below <- results_cal[results_cal$incidence_per_100k < target_low, ]

if (nrow(above) > 0 && nrow(below) > 0) {
  best_above <- above[which.min(above$incidence_per_100k), ]
  best_below <- below[which.max(below$incidence_per_100k), ]
  cat(sprintf("Overall target bracketed between:\n"))
  cat(sprintf("  p=%.3f -> %.2f/100k (above target)\n",
              best_above$p_persistence, best_above$incidence_per_100k))
  cat(sprintf("  p=%.3f -> %.2f/100k (below target)\n",
              best_below$p_persistence, best_below$incidence_per_100k))
} else {
  closest <- results_cal[which.min(abs(results_cal$incidence_per_100k -
                                         mean(c(target_low, target_high)))), ]
  cat(sprintf("Closest to target: p=%.3f (%.2f/100k)\n",
              closest$p_persistence, closest$incidence_per_100k))
}
