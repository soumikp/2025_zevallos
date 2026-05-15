# 2025_04_21_helper.R
# Vectorized HPV Microsimulation Helper Functions
# Optimized for speed using data.table

pacman::p_load(data.table, dplyr, ggplot2, ggsci)

# --- GLOBAL CONSTANTS (Internal to helper if not in simulator) ---
# We define these here to ensure the vectorized logic works even if simulator.R misses them
MIN_LATENCY_FOR_CANCER <- 10  # Years of infection required before cancer risk begins
CANCER_SURVIVAL_THRESHOLD <- 5 # Years until considered a "survivor"
COST_ANNUAL_CANCER <- 30000    # Active treatment cost
COST_ANNUAL_SURVIVOR <- 2000   # Follow-up cost for survivors

# --- MORTALITY FUNCTION (Vectorized) ---
get_mortality_rate_vec <- function(ages) {
  # Base rate 0.001, increasing after 40
  rates <- rep(0.001, length(ages))
  
  # Age 40-59
  mask_mid <- ages >= 40 & ages < 60
  rates[mask_mid] <- 0.001 * (1 + 0.05 * (ages[mask_mid] - 40))
  
  # Age 60+
  mask_old <- ages >= 60
  rates[mask_old] <- 0.001 * (1 + 0.2 * (ages[mask_old] - 40))
  
  return(rates)
}

# --- POPULATION GENERATOR (Vectorized) ---
generate_population <- function(n) {
  
  # Initialize data.table
  agents <- data.table(
    id = 1:n,
    age = sample(18:65, n, replace = TRUE),
    vaccinated = FALSE,
    hpv_status = FALSE,
    health_state = "healthy", # healthy, infected, cancer_active, cancer_survivor, dead
    infection_duration = 0,
    cancer_duration = 0,
    num_prev_infections = 0,
    
    # Demographics / Risk Factors
    smoker = sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.3, 0.7)),
    msm = sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.1, 0.9)),
    vaccine_hesitant = sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.4, 0.6)),
    alive = TRUE,
    
    # Tracking
    vaccination_year = NA_integer_,
    cancer_year = NA_integer_,
    death_year = NA_integer_,
    cause_of_death = NA_character_
  )
  
  # --- FIX: SEED BASELINE INFECTIONS ---
  # Realistically, ~20-40% of this age group might have prevalent HPV.
  # We seed infections so the model doesn't need 15 years to "warm up".
  
  # Base prevalence assumption (simplified function of age)
  # Peaks around age 25, declines after.
  baseline_prev_prob <- 0.40 # High baseline for VHA/High-risk population
  
  # Randomly assign baseline infections
  agents[, is_initially_infected := runif(.N) < baseline_prev_prob]
  
  # For those infected, assign a random duration (1 to 7 years)
  # This creates immediate heterogeneity in risk
  agents[is_initially_infected == TRUE, `:=`(
    hpv_status = TRUE,
    health_state = "infected",
    infection_duration = sample(1:7, .N, replace = TRUE)
  )]
  
  agents[, is_initially_infected := NULL] # cleanup temp col
  
  return(agents)
}

# --- MAIN SIMULATION LOOP (Vectorized) ---
run_simulation <- function(age_cap) {
  
  # 1. Setup
  population <- generate_population(num_agents)
  
  # Pre-allocate results matrix for speed (Yearly Stats)
  stats_mat <- matrix(0, nrow = sim_years, ncol = 11)
  colnames(stats_mat) <- c("year", "num_vaccinated", "num_infected", "num_cleared", 
                           "num_cancer", "num_dead", "num_dead_opc", "num_dead_old_age",
                           "vaccine_costs", "cancer_costs", "survivor_cases")
  
  # We will just track costs cumulatively to save memory, 
  # or use a simplified transition list.
  total_vaccine_cost <- 0
  total_cancer_cost <- 0
  
  # 2. Time Loop
  for(year in 1:sim_years) {
    
    discount_factor <- 1 / ((1 + discount_rate) ^ (year - 1))
    
    # Filter Living Agents Only (working on subset is faster)
    # We use 'which' to get indices of living agents
    living_idx <- which(population$alive == TRUE)
    n_living <- length(living_idx)
    
    if(n_living == 0) break
    
    # --- A. AGING ---
    population[living_idx, age := age + 1]
    
    # Check Max Age (Death by Old Age)
    death_old_idx <- population[living_idx, which(age > max_age)]
    if(length(death_old_idx) > 0) {
      # Map back to original indices
      real_idx <- living_idx[death_old_idx]
      population[real_idx, `:=`(
        alive = FALSE,
        health_state = "dead",
        cause_of_death = "old_age",
        death_year = year
      )]
      # Update living list
      living_idx <- setdiff(living_idx, real_idx)
    }
    
    # --- B. VACCINATION ---
    # Logic: Eligible Age + Not Vaccinated. 
    # Note: Independent of health status (infected people get vaxed too).
    eligible_vax <- population[living_idx][vaccinated == FALSE & age <= age_cap]
    
    if(nrow(eligible_vax) > 0) {
      # Vectorized Probability Calculation
      probs <- rep(p_vaccinate, nrow(eligible_vax))
      probs[eligible_vax$vaccine_hesitant] <- probs[eligible_vax$vaccine_hesitant] * 0.3
      
      # Roll Dice
      vax_success <- runif(nrow(eligible_vax)) < probs
      
      # Update Main Population
      vax_ids <- eligible_vax$id[vax_success]
      if(length(vax_ids) > 0) {
        population[id %in% vax_ids, `:=`(
          vaccinated = TRUE,
          vaccination_year = year
        )]
        
        # Costs
        cost_now <- length(vax_ids) * vaccine_cost * discount_factor
        total_vaccine_cost <- total_vaccine_cost + cost_now
        stats_mat[year, "num_vaccinated"] <- length(vax_ids)
        stats_mat[year, "vaccine_costs"] <- cost_now
      }
    }
    
    # --- C. DISEASE TRANSITIONS ---
    
    # 1. NEW INFECTIONS (State: Healthy -> Infected)
    # ---------------------------------------------
    susceptible <- population[living_idx][health_state == "healthy"]
    if(nrow(susceptible) > 0) {
      # Base Prob
      inf_probs <- ifelse(susceptible$vaccinated, p_infection_vax, p_infection_unvax)
      
      # Modifiers
      inf_probs[susceptible$smoker] <- inf_probs[susceptible$smoker] * smoking_infection_multiplier
      inf_probs[susceptible$msm] <- inf_probs[susceptible$msm] * msm_infection_multiplier
      
      # Roll
      new_inf <- runif(nrow(susceptible)) < inf_probs
      inf_ids <- susceptible$id[new_inf]
      
      if(length(inf_ids) > 0) {
        population[id %in% inf_ids, `:=`(
          health_state = "infected",
          hpv_status = TRUE,
          infection_duration = 0, # Reset counter
          infection_year = year
        )]
        stats_mat[year, "num_infected"] <- length(inf_ids)
      }
    }
    
    # 2. PROGRESSION / CLEARANCE (State: Infected)
    # --------------------------------------------
    infected <- population[living_idx][health_state == "infected"]
    if(nrow(infected) > 0) {
      # Increment Duration
      population[id %in% infected$id, infection_duration := infection_duration + 1]
      
      # Refetch updated infected group for logic checks
      infected <- population[id %in% infected$id] 
      
      # A. Clearance Logic
      clear_probs <- rep(p_clearance_base, nrow(infected))
      
      # STAGE 1: Medium Duration (2-5 years) - Slightly harder to clear
      mask_med <- infected$infection_duration > 2 & infected$infection_duration <= 5
      clear_probs[mask_med] <- clear_probs[mask_med] * 0.8
      
      # STAGE 2: "Sticky" Persistence (> 5 years) - VERY hard to clear
      # If you've had it 5 years, your body is failing to clear it.
      mask_long <- infected$infection_duration > 5
      clear_probs[mask_long] <- 0.05  # Only 5% chance to clear (95% persistence)
      
      is_cleared <- runif(nrow(infected)) < clear_probs
      clear_ids <- infected$id[is_cleared]
      
      # B. Cancer Progression Logic (Only for those NOT cleared)
      # CRITICAL FIX: Latency Check
      remaining_ids <- infected$id[!is_cleared]
      if(length(remaining_ids) > 0) {
        at_risk <- population[id %in% remaining_ids]
        
        # Only calculate prob if duration > MIN_LATENCY
        # (This prevents instant cancer)
        cancer_candidates <- at_risk[infection_duration > MIN_LATENCY_FOR_CANCER]
        
        if(nrow(cancer_candidates) > 0) {
          c_probs <- rep(p_persistence_to_opc, nrow(cancer_candidates))
          
          # Risk Modifiers
          c_probs[cancer_candidates$smoker] <- c_probs[cancer_candidates$smoker] * smoking_persistence_multiplier
          c_probs[cancer_candidates$num_prev_infections > 0] <- c_probs[cancer_candidates$num_prev_infections > 0] * prev_infection_multiplier
          
          is_cancer <- runif(nrow(cancer_candidates)) < c_probs
          cancer_ids <- cancer_candidates$id[is_cancer]
          
          # Update Cancer State
          if(length(cancer_ids) > 0) {
            population[id %in% cancer_ids, `:=`(
              health_state = "cancer_active",
              cancer_year = year,
              cancer_duration = 0
            )]
            
            # Diagnostic Cost (One time)
            # Assuming opc_cost global is diagnosis + 1st year
            cost_now <- length(cancer_ids) * opc_cost * discount_factor
            total_cancer_cost <- total_cancer_cost + cost_now
            stats_mat[year, "num_cancer"] <- length(cancer_ids)
            stats_mat[year, "cancer_costs"] <- stats_mat[year, "cancer_costs"] + cost_now
          }
        }
      }
      
      # Update Cleared State (done after cancer check to avoid conflicts)
      if(length(clear_ids) > 0) {
        population[id %in% clear_ids, `:=`(
          health_state = "healthy",
          hpv_status = FALSE,
          infection_duration = 0,
          num_prev_infections = num_prev_infections + 1
        )]
        stats_mat[year, "num_cleared"] <- length(clear_ids)
      }
    }
    
    # 3. CANCER EVOLUTION (Active -> Survivor OR Death)
    # -------------------------------------------------
    active_cancer <- population[living_idx][health_state == "cancer_active"]
    if(nrow(active_cancer) > 0) {
      # Increment Duration
      population[id %in% active_cancer$id, cancer_duration := cancer_duration + 1]
      
      # Annual Treatment Cost
      cost_now <- nrow(active_cancer) * COST_ANNUAL_CANCER * discount_factor
      stats_mat[year, "cancer_costs"] <- stats_mat[year, "cancer_costs"] + cost_now
      total_cancer_cost <- total_cancer_cost + cost_now
      
      # Check for Survivorship (Cured)
      # If duration > 5 years, move to survivor
      survivors <- active_cancer[cancer_duration > CANCER_SURVIVAL_THRESHOLD]
      if(nrow(survivors) > 0) {
        population[id %in% survivors$id, health_state := "cancer_survivor"]
      }
    }
    
    # 4. SURVIVOR STATE
    # -----------------
    survivors <- population[living_idx][health_state == "cancer_survivor"]
    if(nrow(survivors) > 0) {
      # Lower annual monitoring cost
      cost_now <- nrow(survivors) * COST_ANNUAL_SURVIVOR * discount_factor
      stats_mat[year, "cancer_costs"] <- stats_mat[year, "cancer_costs"] + cost_now
      total_cancer_cost <- total_cancer_cost + cost_now
      stats_mat[year, "survivor_cases"] <- nrow(survivors)
    }
    
    # --- D. MORTALITY (ALL CAUSES) ---
    # Refetch living after all updates
    curr_living <- population[alive == TRUE]
    if(nrow(curr_living) > 0) {
      
      # 1. Background Mortality
      mort_rates <- get_mortality_rate_vec(curr_living$age)
      
      # 2. Add Excess Mortality for Active Cancer
      # (Survivors get normal mortality or slightly elevated - kept normal here for simplicity)
      is_active_ca <- curr_living$health_state == "cancer_active"
      mort_rates[is_active_ca] <- mort_rates[is_active_ca] + opc_mortality
      
      # Roll for Death
      is_dead <- runif(nrow(curr_living)) < mort_rates
      dead_ids <- curr_living$id[is_dead]
      
      if(length(dead_ids) > 0) {
        # Determine Cause
        causes <- rep("other", length(dead_ids))
        
        # If they had active cancer, call it OPC death
        # (Simplified: assumes if you die with active OPC, it was the OPC)
        cancer_death_mask <- population[id %in% dead_ids, health_state == "cancer_active"]
        causes[cancer_death_mask] <- "opc"
        
        population[id %in% dead_ids, `:=`(
          alive = FALSE,
          death_year = year,
          cause_of_death = causes,
          health_state = "dead"
        )]
        
        stats_mat[year, "num_dead"] <- length(dead_ids)
        stats_mat[year, "num_dead_opc"] <- sum(causes == "opc")
      }
    }
    
    stats_mat[year, "year"] <- year
  } # End Year Loop
  
  # Format Output
  yearly_stats <- as.data.frame(stats_mat)
  yearly_stats$age_cap <- age_cap
  
  summary <- list(
    population = population,
    yearly_stats = yearly_stats,
    age_cap = age_cap,
    total_vaccine_cost = total_vaccine_cost,
    total_cancer_cost = total_cancer_cost,
    total_opc_cases = sum(yearly_stats$num_cancer),
    total_opc_deaths = sum(yearly_stats$num_dead_opc),
    total_old_age_deaths = sum(yearly_stats$num_dead_old_age)
  )
  
  return(summary)
}

# --- PLOTTING FUNCTION ---
generate_plots <- function(results_list) {
  
  # Bind all dataframes from the list
  combined_stats <- bind_rows(lapply(results_list, function(x) x$yearly_stats))
  
  # Convert age_cap to factor for plotting
  combined_stats$age_cap <- as.factor(combined_stats$age_cap)
  
  # 1. Cumulative OPC Cases
  opc_cases_plot <- combined_stats %>%
    # --- FIX START ---
    filter(year > 0) %>%          # Remove any potential initialization artifacts
    arrange(age_cap, year) %>%    # STRICTLY SORT by group and year
    group_by(age_cap) %>%
    mutate(cum_cancer = cumsum(num_cancer)) %>%
    # --- FIX END ---
    ggplot(aes(x = year, y = cum_cancer, color = age_cap)) +
    geom_line(size = 1) +         # geom_line automatically sorts X-axis, but cumsum needed the sort above
    labs(
      title = "Cumulative OPC Cases",
      x = "Simulation Year",
      y = "Cases",
      color = "Age Cap"
    ) +
    theme_bw() +
    theme(legend.position = "bottom") + 
    scale_color_jco() + 
    scale_x_continuous(limits = c(1, 82), expand = c(0, 0))
  
  # 2. Cumulative OPC Deaths
  opc_deaths_plot <- combined_stats %>%
    # --- FIX START ---
    filter(year > 0) %>%
    arrange(age_cap, year) %>%
    group_by(age_cap) %>%
    mutate(cum_deaths_opc = cumsum(num_dead_opc)) %>%
    # --- FIX END ---
    ggplot(aes(x = year, y = cum_deaths_opc, color = age_cap)) +
    geom_line(size = 1) +
    labs(
      title = "Cumulative OPC Deaths",
      x = "Simulation Year",
      y = "Deaths",
      color = "Age Cap"
    ) +
    theme_bw() +
    theme(legend.position = "bottom") + 
    scale_color_jco() + 
    scale_x_continuous(limits = c(1, 82), expand = c(0, 0))
  
  # 3. Cumulative Costs
  costs_plot <- combined_stats %>%
    # --- FIX START ---
    filter(year > 0) %>%
    arrange(age_cap, year) %>%
    group_by(age_cap) %>%
    mutate(
      cum_vaccine_costs = cumsum(vaccine_costs),
      cum_cancer_costs = cumsum(cancer_costs),
      cum_total_costs = cum_vaccine_costs + cum_cancer_costs
    ) %>%
    # --- FIX END ---
    ggplot(aes(x = year, y = cum_total_costs, color = age_cap)) +
    geom_line(size = 1) +
    labs(
      title = "Cumulative Total Costs (USD)",
      x = "Simulation Year",
      y = "Costs",
      color = "Age Cap"
    ) +
    theme_bw() +
    theme(legend.position = "bottom") + 
    scale_y_continuous(labels = scales::dollar_format(scale = 1e-6, suffix = "M")) +
    scale_color_jco() + 
    scale_x_continuous(limits = c(1, 82), expand = c(0, 0))
  
  return(list(
    opc_cases_plot = opc_cases_plot,
    opc_deaths_plot = opc_deaths_plot,
    costs_plot = costs_plot
  ))
}

# --- ICER FUNCTION ---
generate_icer_plot <- function(results_list) {
  
  # 1. Extract Summary Data
  # -----------------------
  # Create a clean dataframe from the results list
  cea_data <- data.frame(
    Strategy = names(results_list),
    Total_Cost = sapply(results_list, function(x) x$total_vaccine_cost + x$total_cancer_cost),
    Total_Cases = sapply(results_list, function(x) x$total_opc_cases),
    Total_Deaths = sapply(results_list, function(x) x$total_opc_deaths)
  )
  
  # 2. Calculate Effectiveness (Cases Averted)
  # ------------------------------------------
  # We assume Age Cap 26 is the "Baseline" (least intervention)
  # Effectiveness = How many cases did we avoid compared to the worst outcome?
  # (Alternatively, you can plot raw cases on a reversed X-axis)
  
  # Sort by effectiveness (lowest cases = highest effectiveness)
  cea_data <- cea_data %>% 
    arrange(desc(Total_Cases)) %>% 
    mutate(
      Cases_Averted = max(Total_Cases) - Total_Cases,
      Deaths_Averted = max(Total_Deaths) - Total_Deaths
    )
  
  # 3. Calculate ICER (Incremental Cost-Effectiveness Ratio)
  # --------------------------------------------------------
  # ICER = (Cost_B - Cost_A) / (Effect_B - Effect_A)
  
  # We strictly order by 'Effectiveness' (Cases Averted) to calculate the frontier
  cea_data <- cea_data %>% arrange(Cases_Averted)
  
  # Calculate increments
  cea_data <- cea_data %>%
    mutate(
      Inc_Cost = Total_Cost - lag(Total_Cost, default = first(Total_Cost)),
      Inc_Effect = Cases_Averted - lag(Cases_Averted, default = first(Cases_Averted)),
      ICER = ifelse(Inc_Effect > 0, Inc_Cost / Inc_Effect, NA)
    )
  
  # Identify Dominated Strategies (Simple domination logic)
  # A strategy is dominated if it costs more and is less effective than another.
  # (Strictly, the frontier requires convex hull logic, but for 5 points this works)
  cea_data <- cea_data %>%
    mutate(
      Label = paste0("Age ", Strategy),
      Is_Dominated = ifelse(ICER < 0 & !is.na(ICER), "Dominated", "Efficient") 
      # Note: This is a simplified check. Real CEA removes dominated rows and recalculates.
    )
  
  # 4. Generate the Plot
  # --------------------
  icer_plot <- ggplot(cea_data, aes(x = Cases_Averted, y = Total_Cost, label = Label)) +
    # Draw the lines connecting strategies (The Frontier)
    geom_line(color = "grey50", linetype = "dashed") +
    
    # Add points
    geom_point(aes(color = Is_Dominated), size = 4) +
    
    # Add labels (using ggrepel so they don't overlap)
    geom_text_repel(box.padding = 0.5) +
    
    # Formatting
    scale_y_continuous(labels = scales::dollar_format(scale = 1e-6, suffix = "M")) +
    scale_color_manual(values = c("Efficient" = "#2E9FDF", "Dominated" = "#E7B800")) +
    
    labs(
      title = "Cost-Effectiveness Efficiency Frontier",
      subtitle = "Incremental Cost per OPC Case Averted",
      x = "Total OPC Cases Averted (vs Baseline)",
      y = "Total Cohort Cost (Millions USD)",
      caption = "Strategies connected by line represent the efficient frontier.\nPoints above the line are dominated (less efficient)."
    ) +
    theme_minimal() +
    theme(legend.position = "bottom")
  
  # 5. Print Table for verification
  print("ICER Calculation Table:")
  print(cea_data %>% select(Strategy, Total_Cost, Cases_Averted, ICER))
  
  return(icer_plot)
}

