# calibrate_weibull.R
# Grid search on weibull_scale to match VA HPV+ OPC incidence target.
#
# Calibration target (Saxena et al. J Med Econ 2022, HPV+ fraction ~70%):
#   Overall VA OPC incidence: 86-126 per million per year (all-OPC)
#   HPV+ fraction ~70% -> ~60-88 per million = 6-9 per 100,000 PY
#   Peak age group 55-64: 146-241 per million (all-OPC) -> ~102-169 per million HPV+
#
# Approach: run status-quo (cap=26, zero vaccination in this cohort) at
# 500k agents for each candidate scale. Compute:
#   (a) overall person-year incidence across full 75-year sim
#   (b) incidence in years 20-40 (agents aged ~46-75, closest to Saxena 55-64 peak)
#
# Key lever: weibull_scale controls mean latency from persistent -> cancer.
#   scale=20 -> mean ~18y (current, model ~10-15x too high)
#   Expect target near scale=50-80 based on rough calculation.

suppressPackageStartupMessages(
  pacman::p_load(data.table, dplyr, ggplot2, ggsci, scales, ggrepel, tidyr)
)
source(file.path(here::here(), "code", "helper_v3.R"))

# --- Fixed parameters (all from simulator_v3.R) -------------------------
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

persistence_threshold_years  <- 2L
p_persistence_given_long_inf <- 0.40

weibull_shape <- 3.0            # shape fixed; only scale varies
smoking_progression_RR  <- 1.5
alcohol_progression_RR  <- 1.3
smoking_alcohol_synergy <- 1.2

opc_mortality_annual          <- 0.045
opc_survivor_excess_mortality <- 0.01

VE_acquisition <- 0.90; VE_persistence <- 0.85
p_vaccinate    <- 0.15       # irrelevant for cap=26 (nobody eligible)
smoking_mortality_RR <- 2.0
vaccine_cost   <- 550

# --- Calibration target --------------------------------------------------
target_low  <- 6    # per 100,000 PY (HPV+ OPC, VA overall)
target_high <- 9

# --- Grid ----------------------------------------------------------------
scales_to_try <- c(20, 30, 40, 50, 60, 75, 100)

results_cal <- data.frame(
  weibull_scale       = numeric(),
  weibull_mean_yrs    = numeric(),
  total_opc_cases     = numeric(),
  total_person_years  = numeric(),
  incidence_per_100k  = numeric(),       # overall sim
  incidence_yr20_40   = numeric(),       # years 20-40 (agents ~46-75)
  stringsAsFactors    = FALSE
)

cat(sprintf("%-14s  %-10s  %-12s  %-14s  %-18s  %-18s\n",
            "weibull_scale", "mean_yrs", "OPC_cases", "person_yrs",
            "incid/100k(overall)", "incid/100k(yr20-40)"))
cat(strrep("-", 95), "\n")

for (ws in scales_to_try) {
  weibull_scale <- ws
  set.seed(2026)

  t0  <- proc.time()
  res <- run_simulation(age_cap = 26)
  elapsed <- round((proc.time() - t0)[["elapsed"]], 1)

  ys <- res$yearly_stats

  # Person-years: sum of alive agents each year (end-of-year snapshot)
  ys$n_alive_eoy <- ys$n_healthy + ys$n_infected + ys$n_persistent + ys$n_cancer
  total_py <- sum(ys$n_alive_eoy)

  # Overall incidence
  total_opc   <- sum(ys$n_new_cancer)
  inc_overall <- total_opc / total_py * 100000

  # Years 20-40 incidence (agents at approximate ages 46-75, overlaps Saxena peak)
  window      <- ys[ys$year >= 20 & ys$year <= 40, ]
  py_window   <- sum(window$n_alive_eoy)
  inc_window  <- sum(window$n_new_cancer) / py_window * 100000

  weibull_mean <- ws * gamma(1 + 1 / weibull_shape)

  results_cal <- rbind(results_cal, data.frame(
    weibull_scale      = ws,
    weibull_mean_yrs   = round(weibull_mean, 1),
    total_opc_cases    = total_opc,
    total_person_years = round(total_py),
    incidence_per_100k = round(inc_overall, 2),
    incidence_yr20_40  = round(inc_window, 2)
  ))

  cat(sprintf("scale=%-8g  mean=%-6.1fy  cases=%-8d  PY=%-12.0f  "
              ,ws, weibull_mean, total_opc, total_py))
  cat(sprintf("overall=%-8.2f  yr20-40=%-8.2f  [%.1fs]\n",
              inc_overall, inc_window, elapsed))
}

cat(strrep("-", 95), "\n")
cat(sprintf("\nCalibration target (VA HPV+ OPC): %.0f-%.0f per 100,000 PY\n",
            target_low, target_high))
cat(sprintf("  (Saxena 2022 all-OPC: 86-126/million; x0.70 HPV+ fraction = 60-88/million)\n"))
cat(sprintf("  Peak age 55-64 (all-OPC): 146-241/million -> HPV+ ~102-169/million\n\n"))

# Bracket the target
above <- results_cal[results_cal$incidence_per_100k > target_high, ]
below <- results_cal[results_cal$incidence_per_100k < target_low, ]

if (nrow(above) > 0 & nrow(below) > 0) {
  best_above <- above[which.min(above$incidence_per_100k), ]
  best_below <- below[which.max(below$incidence_per_100k), ]
  cat(sprintf("Target bracketed between scale=%.0f (%.2f/100k) and scale=%.0f (%.2f/100k)\n",
              best_above$weibull_scale, best_above$incidence_per_100k,
              best_below$weibull_scale, best_below$incidence_per_100k))
} else {
  closest <- results_cal[which.min(abs(results_cal$incidence_per_100k -
                                         mean(c(target_low, target_high)))), ]
  cat(sprintf("Closest to target: scale=%.0f (%.2f/100k)\n",
              closest$weibull_scale, closest$incidence_per_100k))
}
