# helper_v3.R
# Grant-aligned 5-state HPV microsimulation
# States: healthy -> infected -> persistent -> cancer -> dead

pacman::p_load(data.table, dplyr, ggplot2, ggsci, scales, ggrepel, tidyr)

# --- Internal cost/QALY constants (Section 10 of param table) ----
# COSTS: All in 2024 USD. CPI-adjusted from source years using BLS
# Medical Care CPI (CPIMEDSL) compounded YoY changes (2018->2024 = 1.169,
# 2009->2024 = 1.503). See param table Section 10 for full sourcing.
COST_OPC_DIAGNOSIS    <- 0       # Set to 0: Saxena 2022's $82,763 annual
                                 # figure already includes diagnostic workup
                                 # in the first year. Adding a separate
                                 # diagnosis line would double-count.
COST_ANNUAL_CANCER_TX <- 85000   # Saxena 2022 (VA HPV cancer cost study)
                                 # incremental cost vs matched controls,
                                 # CPI-adjusted from $72,746 (2018) to 2024.
                                 # Covers diagnostic workup + active treatment.
COST_ANNUAL_SURVIVOR  <- 2500    # Post-5y surveillance + late-effect care

# QALY WEIGHTS:
QALY_HEALTHY          <- 1.00
QALY_INFECTED         <- 0.98    # Largely asymptomatic
QALY_PERSISTENT       <- 0.98    # Still asymptomatic
QALY_CANCER_ACTIVE    <- 0.65    # Treatment + acute morbidity. v3 value
                                 # retained per user decision. De-ESCALaTE
                                 # (Jones 2020) suggests 0.75 for HPV+
                                 # specifically; 0.65 is more conservative
                                 # and aligned with general HNC literature.
QALY_CANCER_SURVIVOR  <- 0.87    # De-ESCALaTE 24-mo PT EQ-5D-5L

CANCER_SURVIVOR_THRESHOLD <- 5L  # Years post-dx defining survivorship

# --- Background mortality: SSA 2021 male period life table -------
# Source: Social Security Administration, Period Life Table 2021, as used
# in the 2024 Trustees Report. https://www.ssa.gov/oact/STATS/table4c6_2021_TR2024.html
# Note: This is the US general male population. Veterans have somewhat
# higher all-cause mortality (older cohort, more smoking, more chronic
# disease); a multiplier of 1.0-1.2 is defensible but not implemented
# here. Smoking-specific RR is applied separately in the sim loop.
# Replace with VA-specific life table if/when available from CDW.
ssa_male_qx_2021 <- c(
  0.001373, 0.001488, 0.001605, 0.001714, 0.001835,   # ages 20-24
  0.001963, 0.002082, 0.002202, 0.002330, 0.002457,   # ages 25-29
  0.002574, 0.002683, 0.002787, 0.002881, 0.002974,   # ages 30-34
  0.003074, 0.003175, 0.003295, 0.003444, 0.003608,   # ages 35-39
  0.003780, 0.003958, 0.004144, 0.004337, 0.004540,   # ages 40-44
  0.004774, 0.005064, 0.005399, 0.005796, 0.006214,   # ages 45-49
  0.006671, 0.007167, 0.007736, 0.008351, 0.009035,   # ages 50-54
  0.009770, 0.010567, 0.011398, 0.012291, 0.013224,   # ages 55-59
  0.014267, 0.015353, 0.016484, 0.017617, 0.018759,   # ages 60-64
  0.019914, 0.021104, 0.022423, 0.023847, 0.025357,   # ages 65-69
  0.027050, 0.028970, 0.031188, 0.033754, 0.036747,   # ages 70-74
  0.040563, 0.044308, 0.048498, 0.053229, 0.058778,   # ages 75-79
  0.064617, 0.070947, 0.077834, 0.085686, 0.094809,   # ages 80-84
  0.105090, 0.116592, 0.129306, 0.142732, 0.157638,   # ages 85-89
  0.174458, 0.193027, 0.212930, 0.232657, 0.251826,   # ages 90-94
  0.270943, 0.289756, 0.307998, 0.325393, 0.341662    # ages 95-99
)
# Names give the age directly; index = age - 19
names(ssa_male_qx_2021) <- as.character(20:99)

get_mortality_rate_vec <- function(ages) {
  # Clamp ages to [20, 99] for the lookup; agents <20 use age 20 (shouldn't
  # occur given age_min=26); agents >=99 use age 99 qx (they're forced
  # dead at max_age=99 anyway).
  clamped <- pmin(pmax(as.integer(ages), 20L), 99L)
  unname(ssa_male_qx_2021[as.character(clamped)])
}

# --- Population generator ----------------------------------------
generate_population <- function(n) {
  
  agents <- data.table(
    id = 1:n,
    
    # Grant-mandated demographics (male-only; no sex column)
    age = sample(age_min:age_max, n, replace = TRUE),
    
    # Grant-mandated behavioral risk factors
    smoker        = runif(n) < prop_smoker,
    alcohol_heavy = runif(n) < prop_heavy_alcohol,
    
    # Vaccination
    vaccinated       = FALSE,
    vaccination_year = NA_integer_,
    vaccination_age  = NA_integer_,
    
    # Grant 5-state machine
    health_state = "healthy",  # healthy | infected | persistent | cancer | dead
    
    # Timers
    infection_duration  = 0L,   # Years in 'infected'
    persistent_duration = 0L,   # Years in 'persistent'
    cancer_duration     = 0L,   # Years in 'cancer'
    time_to_cancer      = NA_real_,  # Sampled at persistence onset (Weibull)
    
    # Bug 4 flag: TRUE once the one-shot persistence roll has been made
    # for the current infection episode (prevents annual re-rolling).
    # Reset to FALSE on clearance back to healthy.
    persistence_evaluated = FALSE,
    
    # Tracking
    alive            = TRUE,
    infection_year   = NA_integer_,
    persistence_year = NA_integer_,
    cancer_year      = NA_integer_,
    death_year       = NA_integer_,
    cause_of_death   = NA_character_
  )
  
  # --- Seed prevalent infections at simulation start ---
  # Single male-cohort prevalence from Giuliano 2023 PROGRESS US.
  agents[, is_initially_infected := runif(.N) < baseline_prev]
  
  # Assign right-skewed initial duration (most short, few long)
  # rgeom gives 0,1,2,... with mean = (1-p)/p; we shift to >= 1
  agents[is_initially_infected == TRUE, `:=`(
    health_state = "infected",
    infection_duration = rgeom(.N, prob = init_duration_geom_p) + 1L
  )]
  
  # Of those infected with duration already past the persistence threshold,
  # roll the one-shot persistence probability (Bug 1 semantics applied
  # consistently to seeded agents). Those who pass become 'persistent';
  # those who fail stay 'infected' with persistence_evaluated = TRUE.
  long_inf_at_start <- agents[is_initially_infected == TRUE &
                              infection_duration >= persistence_threshold_years]
  
  if(nrow(long_inf_at_start) > 0) {
    is_pers <- runif(nrow(long_inf_at_start)) < p_persistence_given_long_inf
    pers_ids_seed <- long_inf_at_start$id[is_pers]
    
    # Mark all evaluated (passed OR failed) so they don't re-roll later
    agents[id %in% long_inf_at_start$id, persistence_evaluated := TRUE]
    
    if(length(pers_ids_seed) > 0) {
      pers_seed <- agents[id %in% pers_ids_seed]
      n_p <- nrow(pers_seed)
      
      # Risk-adjusted Weibull scale (smaller scale = faster cancer)
      scales <- rep(weibull_scale, n_p)
      scales[pers_seed$smoker]        <- scales[pers_seed$smoker]        / smoking_progression_RR
      scales[pers_seed$alcohol_heavy] <- scales[pers_seed$alcohol_heavy] / alcohol_progression_RR
      both <- pers_seed$smoker & pers_seed$alcohol_heavy
      scales[both] <- scales[both] / smoking_alcohol_synergy
      
      # Bug 2 fix: TRUNCATED WEIBULL.
      # Agents seeded as persistent have already accrued time in the
      # persistent state (infection_duration - persistence_threshold_years).
      # Sample remaining time-to-cancer from the Weibull conditional on
      # T > accrued, via inverse-CDF: T = qweibull(U, shape, scale) where
      # U ~ Uniform(F(accrued), 1). Then remaining = T - accrued > 0.
      accrued <- pers_seed$infection_duration - persistence_threshold_years
      
      u_lower <- pweibull(accrued, shape = weibull_shape, scale = scales)
      u <- runif(n_p, min = u_lower, max = 1)
      ttc_total <- qweibull(u, shape = weibull_shape, scale = scales)
      remaining_ttc <- ttc_total - accrued
      
      # time_to_cancer is stored as REMAINING years from persistence onset;
      # persistent_duration starts at 0 so the countdown matches the in-sim
      # logic (cancer fires when persistent_duration >= time_to_cancer).
      agents[id %in% pers_ids_seed, `:=`(
        health_state        = "persistent",
        persistent_duration = 0L,
        time_to_cancer      = remaining_ttc
      )]
    }
  }
  
  agents[, is_initially_infected := NULL]
  return(agents)
}

# --- Main simulation ---------------------------------------------
run_simulation <- function(age_cap, base_pop = NULL, mort_draws = NULL) {

  population <- if (is.null(base_pop)) generate_population(num_agents) else copy(base_pop)
  
  stats_mat <- matrix(0, nrow = sim_years, ncol = 15)
  colnames(stats_mat) <- c("year", "n_vaccinated", "n_new_infected", "n_cleared",
                           "n_new_persistent", "n_new_cancer", "n_dead", "n_dead_opc",
                           "vaccine_costs", "cancer_costs", "qalys",
                           "n_healthy", "n_infected", "n_persistent", "n_cancer")
  
  total_vaccine_cost <- 0
  total_cancer_cost  <- 0
  total_qalys        <- 0
  
  for(year in 1:sim_years) {
    
    discount_factor <- 1 / ((1 + discount_rate) ^ (year - 1))
    
    living_idx <- which(population$alive)
    if(length(living_idx) == 0) break
    
    # ===== A. AGING ==============================================
    population[living_idx, age := age + 1L]
    
    over_max <- population[living_idx, which(age > max_age)]
    if(length(over_max) > 0) {
      real_idx <- living_idx[over_max]
      population[real_idx, `:=`(
        alive = FALSE, health_state = "dead",
        cause_of_death = "old_age", death_year = year
      )]
      living_idx <- setdiff(living_idx, real_idx)
    }
    
    # ===== B. VACCINATION ========================================
    # Eligibility: alive, not yet vaccinated, age <= cap
    # Vaccinating already-infected agents is allowed; effect is zero on existing infection
    eligible <- population[living_idx][vaccinated == FALSE & age <= age_cap]
    
    if(nrow(eligible) > 0) {
      vax_success <- runif(nrow(eligible)) < p_vaccinate
      vax_ids <- eligible$id[vax_success]
      
      if(length(vax_ids) > 0) {
        population[id %in% vax_ids, `:=`(
          vaccinated = TRUE,
          vaccination_year = year,
          vaccination_age = age
        )]
        cost_now <- length(vax_ids) * vaccine_cost * discount_factor
        total_vaccine_cost <- total_vaccine_cost + cost_now
        stats_mat[year, "n_vaccinated"] <- length(vax_ids)
        stats_mat[year, "vaccine_costs"] <- cost_now
      }
    }
    
    # ===== C1. ACQUISITION: healthy -> infected ===================
    # Vaccination acts here (reduces acquisition by VE_acquisition).
    # Male-only model: single p_acquisition (no sex branch).
    susceptible <- population[living_idx][health_state == "healthy"]
    if(nrow(susceptible) > 0) {
      inf_probs <- rep(p_acquisition, nrow(susceptible))
      inf_probs[susceptible$vaccinated]    <- inf_probs[susceptible$vaccinated]    * (1 - VE_acquisition)
      inf_probs[susceptible$smoker]        <- inf_probs[susceptible$smoker]        * smoking_acquisition_RR
      inf_probs[susceptible$alcohol_heavy] <- inf_probs[susceptible$alcohol_heavy] * alcohol_acquisition_RR
      
      new_inf <- runif(nrow(susceptible)) < inf_probs
      inf_ids <- susceptible$id[new_inf]
      if(length(inf_ids) > 0) {
        population[id %in% inf_ids, `:=`(
          health_state = "infected",
          infection_duration = 0L,
          infection_year = year
        )]
        stats_mat[year, "n_new_infected"] <- length(inf_ids)
      }
    }
    
    # ===== C2. INFECTED: clear OR persist ========================
    # Two transitions can happen this year for an infected agent:
    #  - clearance (back to healthy)
    #  - persistence (forward to persistent), but ONE-SHOT: rolled
    #    only the first time an agent crosses persistence_threshold_years.
    #    After the roll (pass OR fail) `persistence_evaluated = TRUE`
    #    and the agent is never re-rolled. On clearance the flag resets.
    # Vaccine acts on the persistence transition (VE_persistence).
    infected <- population[living_idx][health_state == "infected"]
    if(nrow(infected) > 0) {
      population[id %in% infected$id, infection_duration := infection_duration + 1L]
      infected <- population[id %in% infected$id]
      
      # --- Clearance roll ---
      # Per param table: year 1 of infection clears at p_clearance_short
      # (~0.60), year 2+ at p_clearance_medium (~0.40). Note: current
      # code uses `> 2` so duration==2 still gets the SHORT rate; the
      # param-table convention of "year 2 = medium" would imply `>= 2`.
      # Leaving the threshold as-is for now (pre-existing behavior).
      clear_probs <- rep(p_clearance_short, nrow(infected))
      clear_probs[infected$infection_duration > 2] <- p_clearance_medium
      clear_probs[infected$smoker] <- clear_probs[infected$smoker] * smoking_clearance_RR
      
      is_cleared <- runif(nrow(infected)) < clear_probs
      clear_ids <- infected$id[is_cleared]
      
      # --- Persistence roll (ONE-SHOT) ---
      # Eligible: not cleared this year, at-or-past threshold, never
      # evaluated before. `>= threshold` AND `!persistence_evaluated`
      # means an agent is rolled the first year their duration reaches 2.
      not_cleared <- infected[!is_cleared]
      pers_candidates <- not_cleared[infection_duration >= persistence_threshold_years &
                                       persistence_evaluated == FALSE]
      
      if(nrow(pers_candidates) > 0) {
        pers_probs <- rep(p_persistence_given_long_inf, nrow(pers_candidates))
        pers_probs[pers_candidates$vaccinated] <- pers_probs[pers_candidates$vaccinated] * (1 - VE_persistence)
        
        is_persistent <- runif(nrow(pers_candidates)) < pers_probs
        new_pers_ids  <- pers_candidates$id[is_persistent]
        
        # Mark ALL candidates (pass + fail) as evaluated. Failed agents
        # stay 'infected' and will continue to roll clearance annually,
        # but will never re-roll for persistence in this infection
        # episode. (Flag resets on clearance back to healthy.)
        population[id %in% pers_candidates$id, persistence_evaluated := TRUE]
        
        if(length(new_pers_ids) > 0) {
          n_p <- length(new_pers_ids)
          pers_data <- population[id %in% new_pers_ids]
          
          # Risk-adjusted Weibull scale (smaller = faster cancer)
          scales <- rep(weibull_scale, n_p)
          scales[pers_data$smoker]        <- scales[pers_data$smoker]        / smoking_progression_RR
          scales[pers_data$alcohol_heavy] <- scales[pers_data$alcohol_heavy] / alcohol_progression_RR
          both <- pers_data$smoker & pers_data$alcohol_heavy
          scales[both] <- scales[both] / smoking_alcohol_synergy
          
          ttc <- rweibull(n_p, shape = weibull_shape, scale = scales)
          
          population[id %in% new_pers_ids, `:=`(
            health_state        = "persistent",
            persistent_duration = 0L,
            time_to_cancer      = ttc,
            persistence_year    = year
          )]
          stats_mat[year, "n_new_persistent"] <- length(new_pers_ids)
        }
      }
      
      # Apply clearance (after persistence check so we don't lose IDs).
      # Reset persistence_evaluated so a future re-infection gets a
      # fresh one-shot roll when its duration crosses the threshold.
      if(length(clear_ids) > 0) {
        population[id %in% clear_ids, `:=`(
          health_state          = "healthy",
          infection_duration    = 0L,
          persistence_evaluated = FALSE
        )]
        stats_mat[year, "n_cleared"] <- length(clear_ids)
      }
    }
    
    # ===== C3. PERSISTENT: count down to cancer ==================
    persistent <- population[living_idx][health_state == "persistent"]
    if(nrow(persistent) > 0) {
      population[id %in% persistent$id, persistent_duration := persistent_duration + 1L]
      persistent <- population[id %in% persistent$id]
      
      # Cancer trigger when persistent_duration >= sampled time_to_cancer
      to_cancer <- persistent[persistent_duration >= time_to_cancer]
      if(nrow(to_cancer) > 0) {
        population[id %in% to_cancer$id, `:=`(
          health_state    = "cancer",
          cancer_year     = year,
          cancer_duration = 0L
        )]
        n_new <- nrow(to_cancer)
        diag_cost <- n_new * COST_OPC_DIAGNOSIS * discount_factor
        total_cancer_cost <- total_cancer_cost + diag_cost
        stats_mat[year, "n_new_cancer"] <- n_new
        stats_mat[year, "cancer_costs"] <- stats_mat[year, "cancer_costs"] + diag_cost
      }
      
      # Rare clearance from persistent state. Also resets evaluated
      # flag so any future re-infection rolls fresh.
      still_persistent <- population[id %in% persistent$id][health_state == "persistent"]
      if(nrow(still_persistent) > 0) {
        clear_pers <- runif(nrow(still_persistent)) < p_clearance_persistent
        clear_pers_ids <- still_persistent$id[clear_pers]
        if(length(clear_pers_ids) > 0) {
          population[id %in% clear_pers_ids, `:=`(
            health_state          = "healthy",
            infection_duration    = 0L,
            persistent_duration   = 0L,
            time_to_cancer        = NA_real_,
            persistence_evaluated = FALSE
          )]
        }
      }
    }
    
    # ===== C4. CANCER: annual costs ==============================
    cancer_pts <- population[living_idx][health_state == "cancer"]
    if(nrow(cancer_pts) > 0) {
      population[id %in% cancer_pts$id, cancer_duration := cancer_duration + 1L]
      ca_refresh <- population[id %in% cancer_pts$id]
      
      active    <- ca_refresh[cancer_duration <= CANCER_SURVIVOR_THRESHOLD]
      survivors <- ca_refresh[cancer_duration >  CANCER_SURVIVOR_THRESHOLD]
      
      if(nrow(active) > 0) {
        ac_cost <- nrow(active) * COST_ANNUAL_CANCER_TX * discount_factor
        total_cancer_cost <- total_cancer_cost + ac_cost
        stats_mat[year, "cancer_costs"] <- stats_mat[year, "cancer_costs"] + ac_cost
      }
      if(nrow(survivors) > 0) {
        sv_cost <- nrow(survivors) * COST_ANNUAL_SURVIVOR * discount_factor
        total_cancer_cost <- total_cancer_cost + sv_cost
        stats_mat[year, "cancer_costs"] <- stats_mat[year, "cancer_costs"] + sv_cost
      }
    }
    
    # ===== D. MORTALITY ==========================================
    curr_living <- population[alive == TRUE]
    if(nrow(curr_living) > 0) {
      mort_rates <- get_mortality_rate_vec(curr_living$age)
      mort_rates[curr_living$smoker] <- mort_rates[curr_living$smoker] * smoking_mortality_RR
      
      is_active_ca <- curr_living$health_state == "cancer" &
        curr_living$cancer_duration <= CANCER_SURVIVOR_THRESHOLD
      mort_rates[is_active_ca] <- mort_rates[is_active_ca] + opc_mortality_annual
      
      is_surv_ca <- curr_living$health_state == "cancer" &
        curr_living$cancer_duration > CANCER_SURVIVOR_THRESHOLD
      mort_rates[is_surv_ca] <- mort_rates[is_surv_ca] + opc_survivor_excess_mortality
      
      u_mort  <- if (!is.null(mort_draws)) mort_draws[curr_living$id, year] else runif(nrow(curr_living))
      is_dead <- u_mort < mort_rates
      dead_ids <- curr_living$id[is_dead]
      if(length(dead_ids) > 0) {
        causes <- rep("other", length(dead_ids))

        # Competing risks attribution for cancer patients.
        # Each dying cancer patient is attributed to OPC with probability =
        # excess_rate / total_rate (attributable fraction). Background deaths
        # in long-term survivors are not counted as OPC deaths.
        dead_pop   <- curr_living[is_dead]
        ca_mask    <- dead_pop$health_state == "cancer"
        if(any(ca_mask)) {
          ca_dead      <- dead_pop[ca_mask]
          bg_rates_ca  <- get_mortality_rate_vec(ca_dead$age)
          bg_rates_ca[ca_dead$smoker] <- bg_rates_ca[ca_dead$smoker] * smoking_mortality_RR
          is_active    <- ca_dead$cancer_duration <= CANCER_SURVIVOR_THRESHOLD
          excess_rates <- ifelse(is_active, opc_mortality_annual, opc_survivor_excess_mortality)
          p_opc        <- excess_rates / (bg_rates_ca + excess_rates)
          causes[ca_mask] <- ifelse(runif(sum(ca_mask)) < p_opc, "opc", "other")
        }

        population[id %in% dead_ids, `:=`(
          alive = FALSE,
          death_year = year,
          cause_of_death = causes,
          health_state = "dead"
        )]
        stats_mat[year, "n_dead"] <- length(dead_ids)
        stats_mat[year, "n_dead_opc"] <- sum(causes == "opc")
      }
    }
    
    # ===== E. QALY ACCUMULATION ==================================
    # Discounted QALYs by state for all agents alive at end of year
    living_end <- population[alive == TRUE]
    if(nrow(living_end) > 0) {
      w <- rep(QALY_HEALTHY, nrow(living_end))
      w[living_end$health_state == "infected"]   <- QALY_INFECTED
      w[living_end$health_state == "persistent"] <- QALY_PERSISTENT
      w[living_end$health_state == "cancer" &
          living_end$cancer_duration <= CANCER_SURVIVOR_THRESHOLD] <- QALY_CANCER_ACTIVE
      w[living_end$health_state == "cancer" &
          living_end$cancer_duration >  CANCER_SURVIVOR_THRESHOLD] <- QALY_CANCER_SURVIVOR
      year_qalys <- sum(w) * discount_factor
      total_qalys <- total_qalys + year_qalys
      stats_mat[year, "qalys"] <- year_qalys
    }
    
    # ===== F. State snapshot for validation ======================
    stats_mat[year, "n_healthy"]    <- sum(population$health_state == "healthy"   & population$alive)
    stats_mat[year, "n_infected"]   <- sum(population$health_state == "infected"  & population$alive)
    stats_mat[year, "n_persistent"] <- sum(population$health_state == "persistent" & population$alive)
    stats_mat[year, "n_cancer"]     <- sum(population$health_state == "cancer"    & population$alive)
    stats_mat[year, "year"]         <- year
  }
  
  yearly_stats <- as.data.frame(stats_mat)
  yearly_stats$age_cap <- age_cap
  
  list(
    population         = population,
    yearly_stats       = yearly_stats,
    age_cap            = age_cap,
    total_vaccine_cost = total_vaccine_cost,
    total_cancer_cost  = total_cancer_cost,
    total_qalys        = total_qalys,
    total_opc_cases    = sum(yearly_stats$n_new_cancer),
    total_opc_deaths   = sum(yearly_stats$n_dead_opc),
    total_persistent   = sum(yearly_stats$n_new_persistent)
  )
}

# --- Plotting ----------------------------------------------------
generate_plots <- function(results_list) {
  
  combined <- bind_rows(lapply(results_list, function(x) x$yearly_stats))
  combined$age_cap <- as.factor(combined$age_cap)
  
  base_theme <- theme_bw() +
    theme(legend.position = "bottom", plot.title = element_text(face = "bold"))
  
  cum_plot <- function(var, ylab, title) {
    combined %>%
      filter(year > 0) %>%
      arrange(age_cap, year) %>%
      group_by(age_cap) %>%
      mutate(cum = cumsum(.data[[var]])) %>%
      ggplot(aes(year, cum, color = age_cap)) +
      geom_line(size = 1) +
      labs(title = title, x = "Simulation Year", y = ylab, color = "Age Cap") +
      base_theme + scale_color_jco()
  }
  
  list(
    opc_cases_plot   = cum_plot("n_new_cancer", "Cumulative OPC Cases", "Cumulative OPC Cases by Age Cap"),
    persistent_plot  = cum_plot("n_new_persistent", "Cumulative Persistent Infections", "Cumulative Persistent HPV by Age Cap"),
    opc_deaths_plot  = cum_plot("n_dead_opc", "Cumulative OPC Deaths", "Cumulative OPC Deaths by Age Cap"),
    costs_plot       = combined %>%
      filter(year > 0) %>%
      arrange(age_cap, year) %>%
      group_by(age_cap) %>%
      mutate(cum_cost = cumsum(vaccine_costs + cancer_costs)) %>%
      ggplot(aes(year, cum_cost, color = age_cap)) +
      geom_line(size = 1) +
      labs(title = "Cumulative Total Cost", x = "Simulation Year",
           y = "Discounted Cost (USD)", color = "Age Cap") +
      base_theme + scale_y_continuous(labels = dollar_format(scale = 1e-6, suffix = "M")) +
      scale_color_jco(),
    state_plot       = combined %>%
      filter(year > 0, age_cap == "26") %>%   # status quo to show natural history
      pivot_longer(c(n_healthy, n_infected, n_persistent, n_cancer),
                   names_to = "state", values_to = "n") %>%
      ggplot(aes(year, n, fill = state)) +
      geom_area(alpha = 0.8) +
      labs(title = "State Distribution Over Time (Age Cap 26)",
           x = "Simulation Year", y = "Number of Agents", fill = "State") +
      base_theme + scale_fill_jco()
  )
}

# --- ICER with QALYs ---------------------------------------------
# Bug 3 fix: implement proper extended-dominance removal before
# computing the efficient frontier. Returns the full CEA table (with
# Status: 'frontier' | 'dominated' | 'ext_dominated') and plots both.

# Helper: given a data.frame with Strategy/Total_Cost/Total_QALYs,
# return the efficient frontier marked up with ICERs vs the prior
# frontier point. Status column flags simple-dominated and
# extended-dominated strategies.
compute_efficient_frontier <- function(d) {
  
  d <- d[order(d$Total_QALYs, d$Total_Cost), , drop = FALSE]
  d$Status <- "frontier"
  
  # --- 1. Simple (strict) dominance ---
  # A strategy is simply dominated if there exists ANOTHER strategy
  # with greater-or-equal QALYs AND strictly less cost (or strictly
  # greater QALYs AND less-or-equal cost). Sweep from highest-QALY
  # downward, tracking the min cost seen at >= each QALY level.
  n <- nrow(d)
  if(n >= 2) {
    for(i in 1:n) {
      # Anyone with QALYs >= d$Total_QALYs[i] AND Cost < d$Total_Cost[i]
      # dominates strategy i. (Equality on one side, strict on the other.)
      dominators <- (d$Total_QALYs >= d$Total_QALYs[i] & d$Total_Cost <  d$Total_Cost[i]) |
                    (d$Total_QALYs >  d$Total_QALYs[i] & d$Total_Cost <= d$Total_Cost[i])
      dominators[i] <- FALSE
      if(any(dominators)) d$Status[i] <- "dominated"
    }
  }
  
  # --- 2. Extended dominance ---
  # Among the remaining (non-simply-dominated) strategies sorted by QALYs,
  # a strategy j is extended-dominated if its ICER vs. the previous
  # frontier strategy exceeds the ICER from the previous frontier
  # strategy to some later strategy k (i.e., a linear combination of
  # earlier and later strategies achieves the same QALYs at lower cost).
  # Iterative: remove the worst offender, recompute, repeat until stable.
  repeat {
    f_idx <- which(d$Status == "frontier")
    if(length(f_idx) < 3) break  # Need at least 3 to have ext. dominance
    
    f <- d[f_idx, , drop = FALSE]
    inc_cost  <- diff(f$Total_Cost)
    inc_qalys <- diff(f$Total_QALYs)
    icer      <- ifelse(inc_qalys > 0, inc_cost / inc_qalys, Inf)
    
    # Extended dominance: an interior frontier strategy j (position p in
    # frontier) is ext-dominated if icer[p-1] (vs prior) > icer[p] (vs
    # next). That means jumping past j to the next strategy gives a
    # better incremental ICER, so j is non-monotone.
    if(length(icer) < 2) break
    is_ext_dom <- c(FALSE, icer[-length(icer)] > icer[-1], FALSE)
    
    if(!any(is_ext_dom)) break
    # Remove only the largest violator to avoid removing too many at once
    worst <- which(is_ext_dom)[which.max(icer[which(is_ext_dom) - 1] -
                                          icer[which(is_ext_dom)])]
    d$Status[f_idx[worst]] <- "ext_dominated"
  }
  
  # --- 3. Compute ICERs on the final frontier ---
  d$Inc_Cost  <- NA_real_
  d$Inc_QALYs <- NA_real_
  d$ICER      <- NA_real_
  
  f_idx <- which(d$Status == "frontier")
  if(length(f_idx) >= 2) {
    f <- d[f_idx, ]
    d$Inc_Cost[f_idx[-1]]  <- diff(f$Total_Cost)
    d$Inc_QALYs[f_idx[-1]] <- diff(f$Total_QALYs)
    d$ICER[f_idx[-1]]      <- ifelse(diff(f$Total_QALYs) > 0,
                                     diff(f$Total_Cost) / diff(f$Total_QALYs),
                                     NA_real_)
  }
  
  d
}

generate_icer_plot <- function(results_list) {
  
  cea_data <- data.frame(
    Strategy     = names(results_list),
    Total_Cost   = sapply(results_list, function(x) x$total_vaccine_cost + x$total_cancer_cost),
    Total_QALYs  = sapply(results_list, function(x) x$total_qalys),
    Total_Cases  = sapply(results_list, function(x) x$total_opc_cases),
    Total_Deaths = sapply(results_list, function(x) x$total_opc_deaths),
    stringsAsFactors = FALSE
  )
  
  cea_data <- compute_efficient_frontier(cea_data)
  cea_data$Label <- paste0("Age ", cea_data$Strategy)
  
  print("CEA Table ($/QALY):")
  print(cea_data[, c("Strategy", "Total_Cost", "Total_QALYs",
                     "Inc_Cost", "Inc_QALYs", "ICER", "Status")])
  
  frontier <- cea_data[cea_data$Status == "frontier", ]
  
  ggplot(cea_data, aes(Total_QALYs, Total_Cost, label = Label)) +
    geom_line(data = frontier, color = "grey40", linetype = "solid", linewidth = 0.6) +
    geom_point(aes(color = Status, shape = Status), size = 4) +
    geom_text_repel(box.padding = 0.6) +
    scale_color_manual(values = c(frontier = "#2E9FDF",
                                  dominated = "#E64B35",
                                  ext_dominated = "#F0A500")) +
    scale_shape_manual(values = c(frontier = 16, dominated = 4, ext_dominated = 17)) +
    scale_y_continuous(labels = dollar_format(scale = 1e-6, suffix = "M")) +
    scale_x_continuous(labels = comma_format()) +
    labs(title = "Cost-Effectiveness Plane",
         subtitle = "Efficient frontier (blue), simply dominated (red), extended-dominated (orange)",
         x = "Total QALYs",
         y = "Total Cost (M USD)") +
    theme_minimal() + theme(legend.position = "bottom")
}