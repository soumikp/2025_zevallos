# HPV Vaccination Simulation Model for VHA
# Agent-based model to assess cost-effectiveness of extending vaccination age cap

# this script contains helper functions only

# Function to generate mortality rates by age (simplified)
get_mortality_rate <- function(age) {
  # This is a simplified model - should be replaced with actual VHA mortality data
  base_rate <- 0.001
  if(age < 40) return(base_rate)
  else if(age < 60) return(base_rate * (1 + 0.05 * (age - 40)))
  else return(base_rate * (1 + 0.2 * (age - 40)))
}

# Function to generate the initial population
generate_population <- function(n) {
  # Create data frame for agents
  age_min = 18
  age_max = 65
  agents <- data.frame(
    id = 1:n,
    age = sample(age_min:age_max, n, replace = TRUE),
    vaccinated = FALSE, # everyone starts off unvaccinated
    hpv_status = FALSE, # everyone starts off without HPV infection
    infection_duration = 0, 
    num_prev_infections = 0,
    smoker = sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.3, 0.7)), # 30% are smokers
    msm = sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.1, 0.9)), # 10% are part of MSM network
    vaccine_hesitant = sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.4, 0.6)), # 40% have vaccine hesitancy
    alive = TRUE,
    health_state = "healthy",  # healthy, infected, cancer, dead
    years_with_cancer = 0,
    cause_of_death = NA,
    vaccination_year = NA,
    infection_year = NA,
    cancer_year = NA,
    death_year = NA
  )
  
  return(agents)
}

# Function to run one simulation with a given age cap
# Function to run one simulation with a given age cap
run_simulation <- function(age_cap) {
  # Generate initial population
  population <- generate_population(num_agents)
  
  # Create data frame to store results for each year
  yearly_stats <- data.frame(
    year = 1:sim_years,
    age_cap = age_cap,
    num_vaccinated = 0,
    num_infected = 0,
    num_cleared = 0,
    num_cancer = 0,
    num_dead = 0,
    num_dead_opc = 0,
    num_dead_old_age = 0,  # Track deaths due to old age
    vaccine_costs = 0,
    cancer_costs = 0
  )
  
  # Track all transitions for cost-effectiveness analysis
  all_transitions <- data.frame(
    id = integer(),
    year = integer(),
    age = integer(),
    event = character(),
    discounted_cost = numeric()
  )
  
  # Simulation loop
  for(year in 1:sim_years) {
    # Calculate discounting factor for this year
    discount_factor <- 1 / ((1 + discount_rate) ^ (year - 1))
    
    # Track changes within this year
    newly_vaccinated <- 0
    newly_infected <- 0
    newly_cleared <- 0
    newly_cancer <- 0
    newly_dead <- 0
    newly_dead_opc <- 0
    newly_dead_old_age <- 0
    
    vaccine_costs_this_year <- 0
    cancer_costs_this_year <- 0
    
    # Update each living agent
    for(i in 1:nrow(population)) {
      if(!population$alive[i]) next  # Skip dead agents
      
      # Update age
      population$age[i] <- population$age[i] + 1
      
      # Get current state
      current_age <- population$age[i]
      current_state <- population$health_state[i]
      is_smoker <- population$smoker[i]
      is_msm <- population$msm[i]
      is_hesitant <- population$vaccine_hesitant[i]
      
      # Check if agent has reached max age
      if(current_age > max_age) {
        # Agent dies of old age
        population$alive[i] <- FALSE
        population$health_state[i] <- "dead"
        population$death_year[i] <- year
        population$cause_of_death[i] <- "old_age"
        newly_dead <- newly_dead + 1
        newly_dead_old_age <- newly_dead_old_age + 1
        
        # Record transition
        all_transitions <- rbind(all_transitions, data.frame(
          id = population$id[i],
          year = year,
          age = current_age,
          event = "death_old_age",
          discounted_cost = 0
        ))
        
        next  # Skip to next agent
      }
      
      # Apply mortality (all-cause)
      mortality_rate <- get_mortality_rate(current_age)
      
      # Process based on current health state
      if(current_state == "healthy") {
        # Unvaccinated person may get vaccinated (if under age cap)
        if(!population$vaccinated[i] && current_age <= age_cap) {
          # Adjust vaccination probability based on hesitancy
          vax_prob <- p_vaccinate
          if(is_hesitant) vax_prob <- vax_prob * 0.3
          
          if(runif(1) < vax_prob) {
            population$vaccinated[i] <- TRUE
            population$vaccination_year[i] <- year
            newly_vaccinated <- newly_vaccinated + 1
            
            # Record vaccination cost
            discounted_vaccine_cost <- vaccine_cost * discount_factor
            vaccine_costs_this_year <- vaccine_costs_this_year + discounted_vaccine_cost
            
            # Record transition
            all_transitions <- rbind(all_transitions, data.frame(
              id = population$id[i],
              year = year,
              age = current_age,
              event = "vaccination",
              discounted_cost = discounted_vaccine_cost
            ))
          }
        }
        
        # May get infected
        infection_prob <- ifelse(population$vaccinated[i], 
                                 p_infection_vax, 
                                 p_infection_unvax)
        
        # Apply risk factor modifiers
        if(is_smoker) infection_prob <- infection_prob * smoking_infection_multiplier
        if(is_msm) infection_prob <- infection_prob * msm_infection_multiplier
        
        if(runif(1) < infection_prob) {
          population$hpv_status[i] <- TRUE
          population$health_state[i] <- "infected"
          population$infection_duration[i] <- 1
          population$infection_year[i] <- year
          newly_infected <- newly_infected + 1
          
          # Record transition
          all_transitions <- rbind(all_transitions, data.frame(
            id = population$id[i],
            year = year,
            age = current_age,
            event = "infection",
            discounted_cost = 0
          ))
        }
        
      } else if(current_state == "infected") {
        # Update infection duration
        population$infection_duration[i] <- population$infection_duration[i] + 1
        
        # May clear infection
        clearance_prob <- p_clearance_base
        
        # Duration affects clearance probability (longer = harder to clear)
        if(population$infection_duration[i] > 2) {
          clearance_prob <- clearance_prob * 0.8
        }
        
        if(runif(1) < clearance_prob) {
          population$hpv_status[i] <- FALSE
          population$health_state[i] <- "healthy"
          population$num_prev_infections[i] <- population$num_prev_infections[i] + 1
          population$infection_duration[i] <- 0
          newly_cleared <- newly_cleared + 1
          
          # Record transition
          all_transitions <- rbind(all_transitions, data.frame(
            id = population$id[i],
            year = year,
            age = current_age,
            event = "clearance",
            discounted_cost = 0
          ))
        } else {
          # May progress to cancer
          cancer_prob <- p_persistence_to_opc
          
          # Risk factors affect progression
          if(is_smoker) cancer_prob <- cancer_prob * smoking_persistence_multiplier
          if(population$infection_duration[i] > 3) cancer_prob <- cancer_prob * 1.5
          if(population$num_prev_infections[i] > 0) cancer_prob <- cancer_prob * prev_infection_multiplier
          
          if(runif(1) < cancer_prob) {
            population$health_state[i] <- "cancer"
            population$cancer_year[i] <- year
            newly_cancer <- newly_cancer + 1
            
            # Record cancer cost (initial diagnosis and treatment)
            discounted_cancer_cost <- opc_cost * discount_factor
            cancer_costs_this_year <- cancer_costs_this_year + discounted_cancer_cost
            
            # Record transition
            all_transitions <- rbind(all_transitions, data.frame(
              id = population$id[i],
              year = year,
              age = current_age,
              event = "cancer",
              discounted_cost = discounted_cancer_cost
            ))
          }
        }
        
      } else if(current_state == "cancer") {
        # Increase years with cancer
        population$years_with_cancer[i] <- population$years_with_cancer[i] + 1
        
        # Cancer treatment costs (annual)
        annual_treatment_cost <- 30000 * discount_factor
        cancer_costs_this_year <- cancer_costs_this_year + annual_treatment_cost
        
        # Record annual treatment
        all_transitions <- rbind(all_transitions, data.frame(
          id = population$id[i],
          year = year,
          age = current_age,
          event = "cancer_treatment",
          discounted_cost = annual_treatment_cost
        ))
        
        # Higher mortality
        mortality_rate <- mortality_rate + opc_mortality
      }
      
      # Apply mortality check
      if(runif(1) < mortality_rate) {
        population$alive[i] <- FALSE
        population$health_state[i] <- "dead"
        population$death_year[i] <- year
        newly_dead <- newly_dead + 1
        
        # Determine cause of death
        if(current_state == "cancer") {
          population$cause_of_death[i] <- "opc"
          newly_dead_opc <- newly_dead_opc + 1
        } else {
          population$cause_of_death[i] <- "other"
        }
        
        # Record transition
        all_transitions <- rbind(all_transitions, data.frame(
          id = population$id[i],
          year = year,
          age = current_age,
          event = ifelse(population$cause_of_death[i] == "opc", "death_opc", "death_other"),
          discounted_cost = 0
        ))
      }
    }
    
    # Update yearly stats
    yearly_stats$num_vaccinated[year] <- newly_vaccinated
    yearly_stats$num_infected[year] <- newly_infected
    yearly_stats$num_cleared[year] <- newly_cleared
    yearly_stats$num_cancer[year] <- newly_cancer
    yearly_stats$num_dead[year] <- newly_dead
    yearly_stats$num_dead_opc[year] <- newly_dead_opc
    yearly_stats$num_dead_old_age[year] <- newly_dead_old_age
    yearly_stats$vaccine_costs[year] <- vaccine_costs_this_year
    yearly_stats$cancer_costs[year] <- cancer_costs_this_year
  }
  
  # Create summary results
  summary <- list(
    population = population,
    yearly_stats = yearly_stats,
    transitions = all_transitions,
    age_cap = age_cap,
    total_vaccine_cost = sum(yearly_stats$vaccine_costs),
    total_cancer_cost = sum(yearly_stats$cancer_costs),
    total_opc_cases = sum(yearly_stats$num_cancer),
    total_opc_deaths = sum(yearly_stats$num_dead_opc),
    total_old_age_deaths = sum(yearly_stats$num_dead_old_age)
  )
  
  return(summary)
}

# # Calculate incremental cost-effectiveness ratios (ICER) (needs more work)
# calculate_icer <- function(results_list) {
#   # Extract relevant metrics for each age cap
#   metrics <- data.frame(
#     age_cap = vaccination_age_caps,
#     vaccine_cost = sapply(results_list, function(x) x$total_vaccine_cost),
#     cancer_cost = sapply(results_list, function(x) x$total_cancer_cost),
#     opc_cases = sapply(results_list, function(x) x$total_opc_cases),
#     opc_deaths = sapply(results_list, function(x) x$total_opc_deaths)
#   )
#   
#   # Calculate total costs and sort by age cap
#   metrics <- metrics %>%
#     mutate(
#       total_cost = vaccine_cost + cancer_cost,
#       cases_averted = max(opc_cases) - opc_cases,
#       deaths_averted = max(opc_deaths) - opc_deaths
#     ) %>%
#     arrange(age_cap)
#   
#   # Calculate incremental metrics
#   metrics <- metrics %>%
#     mutate(
#       inc_cost = total_cost - lag(total_cost, default = first(total_cost)),
#       inc_cases_averted = cases_averted - lag(cases_averted, default = first(cases_averted)),
#       inc_deaths_averted = deaths_averted - lag(deaths_averted, default = first(deaths_averted)),
#       icer_cases = ifelse(inc_cases_averted > 0, inc_cost / inc_cases_averted, NA),
#       icer_deaths = ifelse(inc_deaths_averted > 0, inc_cost / inc_deaths_averted, NA)
#     )
#   
#   return(metrics)
# }

# Generate plots
generate_plots <- function(results_list) {
  # Combine yearly stats
  combined_stats <- 
   rbind(results_list[["30"]]$yearly_stats, 
         results_list[["26"]]$yearly_stats,
         results_list[["35"]]$yearly_stats,
         results_list[["40"]]$yearly_stats,
         results_list[["45"]]$yearly_stats)
  
  combined_stats$age_cap <- rep(c(26, 30, 35, 40, 45), each = 100)
  
  # Plot cumulative OPC cases
  opc_cases_plot <- combined_stats %>%
    group_by(age_cap) %>%
    mutate(cum_cancer = cumsum(num_cancer)) %>%
    ggplot(aes(x = year, y = cum_cancer, color = factor(age_cap))) +
    geom_smooth(se = FALSE) +
    labs(
      title = "Cumulative OPC Cases by Vaccination Age Cap",
      #subtitle = "Simulated cohort size = 10,000",
      x = "Simulation Year\n(Starting from 2025)",
      y = "Cumulative OPC Cases",
      color = "Age Cap"
    ) +
    theme_big_simple()+ 
    theme(legend.position = "bottom") + 
    scale_color_bmj()
  
  # Plot cumulative OPC deaths
  opc_deaths_plot <- combined_stats %>%
    group_by(age_cap) %>%
    mutate(cum_deaths_opc = cumsum(num_dead_opc)) %>%
    ggplot(aes(x = year, y = cum_deaths_opc, color = factor(age_cap))) +
    geom_smooth(se = FALSE) +
    labs(
      title = "Cumulative OPC Deaths by Vaccination Age Cap",
      #subtitle = "Simulated cohort size = 10,000",
      x = "Simulation Year",
      y = "Cumulative OPC Deaths",
      color = "Age Cap"
    ) +
    theme_big_simple()+ 
    theme(legend.position = "bottom") + 
    scale_color_bmj()
  
  # Plot cumulative costs
  costs_plot <- combined_stats %>%
    group_by(age_cap) %>%
    mutate(
      cum_vaccine_costs = cumsum(vaccine_costs),
      cum_cancer_costs = cumsum(cancer_costs),
      cum_total_costs = cum_vaccine_costs + cum_cancer_costs
    ) %>%
    ggplot(aes(x = year, y = cum_total_costs, color = factor(age_cap))) +
    geom_smooth(se = FALSE) +
    labs(
      title = "Cumulative Total Costs by Vaccination Age Cap",
      #subtitle = "Simulated cohort size = 10,000",
      x = "Simulation Year",
      y = "Cumulative Costs (USD)",
      color = "Age Cap"
    )  +
    theme_big_simple()+ 
    theme(legend.position = "bottom") + 
    scale_color_bmj()
  
  return(list(
    opc_cases_plot = opc_cases_plot,
    opc_deaths_plot = opc_deaths_plot,
    costs_plot = costs_plot
  ))
}
