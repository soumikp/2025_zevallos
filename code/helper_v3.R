# helper_v3.R
# Grant-aligned 5-state HPV microsimulation
# States: healthy -> infected -> persistent -> cancer -> dead

pacman::p_load(data.table, dplyr, ggplot2, ggsci, scales, ggrepel, tidyr)

# --- Internal cost/QALY constants -------------------------------
# (kept here so they don't clutter simulator; promote to Excel Sheet 10)
COST_OPC_DIAGNOSIS    <- 25000   # One-time diagnostic workup at OPC dx
COST_ANNUAL_CANCER_TX <- 30000   # Annual active treatment (yrs 1-5)
COST_ANNUAL_SURVIVOR  <- 2000    # Annual post-5y survivor follow-up

QALY_HEALTHY          <- 1.00
QALY_INFECTED         <- 0.98    # Largely asymptomatic
QALY_PERSISTENT       <- 0.98    # Still asymptomatic
QALY_CANCER_ACTIVE    <- 0.65    # Treatment + acute morbidity
QALY_CANCER_SURVIVOR  <- 0.85    # Long-term swallowing/xerostomia sequelae

CANCER_SURVIVOR_THRESHOLD <- 5L  # Years post-dx defining survivorship

# --- Background mortality (placeholder; replace with VA life table) ---
get_mortality_rate_vec <- function(ages, sex = "M") {
  # Placeholder piecewise function. Replace with SSA or VA life-table
  # lookup keyed on age and sex. Sex argument reserved for that swap.
  rates <- rep(0.001, length(ages))
  rates[ages >= 40 & ages < 60] <- 0.001 * (1 + 0.05 * (ages[ages >= 40 & ages < 60] - 40))
  rates[ages >= 60] <- 0.001 * (1 + 0.20 * (ages[ages >= 60] - 40))
  return(rates)
}

# --- Population generator ----------------------------------------
generate_population <- function(n) {
  
  agents <- data.table(
    id = 1:n,
    
    # Grant-mandated demographics
    age = sample(age_min:age_max, n, replace = TRUE),
    sex = sample(c("M", "F"), n, replace = TRUE,
                 prob = c(prop_male, 1 - prop_male)),
    
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
    
    # Tracking
    alive            = TRUE,
    infection_year   = NA_integer_,
    persistence_year = NA_integer_,
    cancer_year      = NA_integer_,
    death_year       = NA_integer_,
    cause_of_death   = NA_character_
  )
  
  # --- Seed prevalent infections at simulation start ---
  # Sex-stratified prevalence from NHANES (Sheet 1)
  agents[, baseline_inf_prob := ifelse(sex == "M",
                                       baseline_prev_male,
                                       baseline_prev_female)]
  agents[, is_initially_infected := runif(.N) < baseline_inf_prob]
  
  # Assign right-skewed initial duration (most short, few long)
  # rgeom gives 0,1,2,... with mean = (1-p)/p; we shift to >= 1
  agents[is_initially_infected == TRUE, `:=`(
    health_state = "infected",
    infection_duration = rgeom(.N, prob = init_duration_geom_p) + 1L
  )]
  
  # Of those infected with duration already past the persistence threshold,
  # classify as persistent and sample their time-to-cancer
  pers_at_start <- agents[is_initially_infected == TRUE &
                            infection_duration >= persistence_threshold_years]
  if(nrow(pers_at_start) > 0) {
    n_p <- nrow(pers_at_start)
    
    # Risk-adjusted Weibull scale (smaller = faster)
    scales <- rep(weibull_scale, n_p)
    scales[pers_at_start$smoker]        <- scales[pers_at_start$smoker]        / smoking_progression_RR
    scales[pers_at_start$alcohol_heavy] <- scales[pers_at_start$alcohol_heavy] / alcohol_progression_RR
    both <- pers_at_start$smoker & pers_at_start$alcohol_heavy
    scales[both] <- scales[both] / smoking_alcohol_synergy
    scales[pers_at_start$sex == "F"] <- scales[pers_at_start$sex == "F"] / female_progression_RR
    
    ttc <- rweibull(n_p, shape = weibull_shape, scale = scales)
    
    # Already accrued some persistent time; subtract from ttc clock
    accrued <- pers_at_start$infection_duration - persistence_threshold_years
    
    agents[id %in% pers_at_start$id, `:=`(
      health_state = "persistent",
      persistent_duration = accrued,
      time_to_cancer = ttc
    )]
  }
  
  agents[, c("baseline_inf_prob", "is_initially_infected") := NULL]
  return(agents)
}

# --- Main simulation ---------------------------------------------
run_simulation <- function(age_cap) {
  
  population <- generate_population(num_agents)
  
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
    # Vaccination acts here (reduces acquisition by VE_acquisition)
    susceptible <- population[living_idx][health_state == "healthy"]
    if(nrow(susceptible) > 0) {
      inf_probs <- ifelse(susceptible$sex == "M",
                          p_acquisition_male, p_acquisition_female)
      inf_probs[susceptible$vaccinated] <- inf_probs[susceptible$vaccinated] * (1 - VE_acquisition)
      inf_probs[susceptible$smoker]     <- inf_probs[susceptible$smoker]     * smoking_acquisition_RR
      
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
    # Vaccination acts here too (reduces transition to persistent by VE_persistence)
    infected <- population[living_idx][health_state == "infected"]
    if(nrow(infected) > 0) {
      population[id %in% infected$id, infection_duration := infection_duration + 1L]
      infected <- population[id %in% infected$id]
      
      # Clearance probability by duration (Sheet 3)
      clear_probs <- rep(p_clearance_short, nrow(infected))
      clear_probs[infected$infection_duration > 2] <- p_clearance_medium
      clear_probs[infected$smoker] <- clear_probs[infected$smoker] * smoking_clearance_RR
      
      is_cleared <- runif(nrow(infected)) < clear_probs
      clear_ids <- infected$id[is_cleared]
      
      # Persistence check: still infected AND duration past threshold
      not_cleared <- infected[!is_cleared]
      at_threshold <- not_cleared[infection_duration >= persistence_threshold_years]
      
      if(nrow(at_threshold) > 0) {
        # Vaccine effect on persistence transition (grant-mandated)
        pers_probs <- rep(p_persistence_given_long_inf, nrow(at_threshold))
        pers_probs[at_threshold$vaccinated] <- pers_probs[at_threshold$vaccinated] * (1 - VE_persistence)
        
        is_persistent <- runif(nrow(at_threshold)) < pers_probs
        pers_ids <- at_threshold$id[is_persistent]
        
        if(length(pers_ids) > 0) {
          # Sample time-to-cancer Weibull at persistence onset
          n_p <- length(pers_ids)
          pers_data <- population[id %in% pers_ids]
          
          scales <- rep(weibull_scale, n_p)
          scales[pers_data$smoker]        <- scales[pers_data$smoker]        / smoking_progression_RR
          scales[pers_data$alcohol_heavy] <- scales[pers_data$alcohol_heavy] / alcohol_progression_RR
          both <- pers_data$smoker & pers_data$alcohol_heavy
          scales[both] <- scales[both] / smoking_alcohol_synergy
          scales[pers_data$sex == "F"] <- scales[pers_data$sex == "F"] / female_progression_RR
          
          ttc <- rweibull(n_p, shape = weibull_shape, scale = scales)
          
          population[id %in% pers_ids, `:=`(
            health_state        = "persistent",
            persistent_duration = 0L,
            time_to_cancer      = ttc,
            persistence_year    = year
          )]
          stats_mat[year, "n_new_persistent"] <- length(pers_ids)
        }
      }
      
      # Apply clearance (after persistence check so we don't lose IDs)
      if(length(clear_ids) > 0) {
        population[id %in% clear_ids, `:=`(
          health_state = "healthy",
          infection_duration = 0L
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
      
      # Rare clearance from persistent state
      still_persistent <- population[id %in% persistent$id][health_state == "persistent"]
      if(nrow(still_persistent) > 0) {
        clear_pers <- runif(nrow(still_persistent)) < p_clearance_persistent
        clear_pers_ids <- still_persistent$id[clear_pers]
        if(length(clear_pers_ids) > 0) {
          population[id %in% clear_pers_ids, `:=`(
            health_state = "healthy",
            infection_duration = 0L,
            persistent_duration = 0L,
            time_to_cancer = NA_real_
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
      mort_rates <- get_mortality_rate_vec(curr_living$age, curr_living$sex)
      mort_rates[curr_living$smoker] <- mort_rates[curr_living$smoker] * smoking_mortality_RR
      
      is_active_ca <- curr_living$health_state == "cancer" &
        curr_living$cancer_duration <= CANCER_SURVIVOR_THRESHOLD
      mort_rates[is_active_ca] <- mort_rates[is_active_ca] + opc_mortality_annual
      
      is_surv_ca <- curr_living$health_state == "cancer" &
        curr_living$cancer_duration > CANCER_SURVIVOR_THRESHOLD
      mort_rates[is_surv_ca] <- mort_rates[is_surv_ca] + opc_survivor_excess_mortality
      
      is_dead <- runif(nrow(curr_living)) < mort_rates
      dead_ids <- curr_living$id[is_dead]
      if(length(dead_ids) > 0) {
        causes <- rep("other", length(dead_ids))
        ca_mask <- population[id %in% dead_ids, health_state == "cancer"]
        causes[ca_mask] <- "opc"
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
generate_icer_plot <- function(results_list) {
  
  cea_data <- data.frame(
    Strategy    = names(results_list),
    Total_Cost  = sapply(results_list, function(x) x$total_vaccine_cost + x$total_cancer_cost),
    Total_QALYs = sapply(results_list, function(x) x$total_qalys),
    Total_Cases = sapply(results_list, function(x) x$total_opc_cases),
    Total_Deaths = sapply(results_list, function(x) x$total_opc_deaths)
  )
  
  cea_data <- cea_data %>%
    arrange(Total_QALYs) %>%
    mutate(
      Inc_Cost  = Total_Cost - lag(Total_Cost),
      Inc_QALYs = Total_QALYs - lag(Total_QALYs),
      ICER      = ifelse(Inc_QALYs > 0, Inc_Cost / Inc_QALYs, NA),
      Label     = paste0("Age ", Strategy)
    )
  
  print("ICER Table ($/QALY):")
  print(cea_data %>% select(Strategy, Total_Cost, Total_QALYs, ICER))
  
  ggplot(cea_data, aes(Total_QALYs, Total_Cost, label = Label)) +
    geom_line(color = "grey50", linetype = "dashed") +
    geom_point(color = "#2E9FDF", size = 4) +
    geom_text_repel(box.padding = 0.6) +
    scale_y_continuous(labels = dollar_format(scale = 1e-6, suffix = "M")) +
    scale_x_continuous(labels = comma_format()) +
    labs(title = "Cost-Effectiveness Plane",
         subtitle = "Incremental Cost per QALY Gained",
         x = "Total QALYs",
         y = "Total Cost (M USD)") +
    theme_minimal() + theme(legend.position = "bottom")
}