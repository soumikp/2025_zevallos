pacman::p_load(tidyverse, ggsci, patchwork, plotly)

# Define agent class
agent <- function(id, age, vaccinated, hpv_status, disease_state) {
  list(
    id = id, 
    age = age,
    vaccinated = vaccinated,
    hpv_status = hpv_status,
    disease_state = disease_state
  )
}

# Initialize population
initialize_population <- function(n, min_age, max_age) {
  lapply(1:n, function(i) {
    age <- sample(min_age:max_age, 1)
    vaccinated <- sample(c(TRUE, FALSE), 1, prob = c(0.5, 0.5))  # 50% vaccinated
    hpv_status <- "none"
    disease_state <- "healthy"
    agent(id = i, age, vaccinated, hpv_status, disease_state)
  })
}

# Transition rules
update_agent <- function(agent, ageCap = 26) {
  # Age the agent
  agent$age <- agent$age + 1
  
  # Vaccination (up to age 30)
  if (agent$age <= ageCap && !agent$vaccinated) {
    agent$vaccinated <- sample(c(TRUE, FALSE), 1, prob = c(0.30, 0.70))  # 10% chance to get vaccinated
  }
  
  # HPV infection (age-specific risk)
  if (agent$hpv_status == "none") {
    p_infection <- ifelse(agent$age < 26, 0.05, 0.02)  # Higher risk for younger ages
    if (agent$vaccinated) p_infection <- p_infection * 0.1  # 90% efficacy
    if (runif(1) < p_infection) agent$hpv_status <- sample(c("low_risk", "high_risk"), 1, prob = c(0.2, 0.8))
  }
  
  # Disease progression
  if (agent$hpv_status == "high_risk") {
    if (agent$disease_state == "healthy" && runif(1) < 0.2) {
      agent$disease_state <- "precancer"  # Healthy → Precancer
    } else if (agent$disease_state == "precancer" && runif(1) < 0.3) {
      agent$disease_state <- "cancer"  # Precancer → Cancer
    }
  }
  
  # Death
  if (agent$disease_state == "cancer" && runif(1) < 0.2) {
    agent$disease_state <- "dead"  # Cancer → Death
  } else if (runif(1) < 0.01) {
    agent$disease_state <- "dead"  # Background mortality
  }
  
  return(agent)
}

# Run simulation
simulate <- function(population, cycles, ageCap = 26) {
  results <- list()
  for (cycle in 1:cycles) {
    population <- lapply(population, update_agent, ageCap = ageCap)
    results[[cycle]] <- sapply(population, function(x) x$disease_state)
  }
  return(results)
}

# Initialize and run
n = 50000
population <- initialize_population(n = n, min_age = 20, max_age = 85)

t1 <- Sys.time()
results_26 <- simulate(population, cycles = 65, ageCap = 26)  # 60 years (25 to 85)
t2 <- Sys.time()
t2 - t1

t1 <- Sys.time()
results_30 <- simulate(population, cycles = 65, ageCap = 30)  # 60 years (25 to 85)
t2 <- Sys.time()
t2 - t1

t1 <- Sys.time()
results_35 <- simulate(population, cycles = 65, ageCap = 35)  # 60 years (25 to 85)
t2 <- Sys.time()
t2 - t1

t1 <- Sys.time()
results_40 <- simulate(population, cycles = 65, ageCap = 40)  # 60 years (25 to 85)
t2 <- Sys.time()
t2 - t1

t1 <- Sys.time()
results_45 <- simulate(population, cycles = 65, ageCap = 45)  # 60 years (25 to 85)
t2 <- Sys.time()
t2 - t1

state_counter <- function(x){
  t <- c(sum(x == "healthy"), sum(x == "precancer"), sum(x == "cancer"), sum(x == "dead"))
  names(t) = c("healthy", "precancer", "cancer", "dead")
  return(t)
}

cost_counter<- function(x){
  t <- c(sum(x == "healthy"), sum(x == "precancer"), sum(x == "cancer"), sum(x == "dead"))
  names(t) = c("healthy", "precancer", "cancer", "dead")
  p <- c(0, 10, 20, 0)
  return(sum(t*p))
}

results_26 <- matrix(unlist(lapply(results_26, state_counter)), byrow = T, ncol = 4)
results_30 <- matrix(unlist(lapply(results_30, state_counter)), byrow = T, ncol = 4)
results_35 <- matrix(unlist(lapply(results_35, state_counter)), byrow = T, ncol = 4)
results_40 <- matrix(unlist(lapply(results_40, state_counter)), byrow = T, ncol = 4)
results_45 <- matrix(unlist(lapply(results_45, state_counter)), byrow = T, ncol = 4)


results_26_final <- as_tibble(results_26) %>%
  mutate(time = seq_along(V1)) %>% rename(healthy = V1, precancer = V2, cancer = V3, dead = V4) %>% 
  pivot_longer(cols = -c(time))

results_30_final <- as_tibble(results_30) %>%
  mutate(time = seq_along(V1)) %>% rename(healthy = V1, precancer = V2, cancer = V3, dead = V4) %>% 
  pivot_longer(cols = -c(time))

results_35_final <- as_tibble(results_35) %>%
  mutate(time = seq_along(V1)) %>% rename(healthy = V1, precancer = V2, cancer = V3, dead = V4) %>% 
  pivot_longer(cols = -c(time))

results_40_final <- as_tibble(results_40) %>%
  mutate(time = seq_along(V1)) %>% rename(healthy = V1, precancer = V2, cancer = V3, dead = V4) %>% 
  pivot_longer(cols = -c(time))

results_45_final <- as_tibble(results_45) %>%
  mutate(time = seq_along(V1)) %>% rename(healthy = V1, precancer = V2, cancer = V3, dead = V4) %>% 
  pivot_longer(cols = -c(time))

p1 <- results_26_final %>% 
  ggplot(aes(x = time, y = value, group = name)) + 
  geom_line(aes(color = name)) + 
  scale_color_jama()

p2 <- results_30_final %>% 
  ggplot(aes(x = time, y = value, group = name)) + 
  geom_line(aes(color = name)) + 
  scale_color_jama()

p3 <- results_35_final %>% 
  ggplot(aes(x = time, y = value, group = name)) + 
  geom_line(aes(color = name)) + 
  scale_color_jama()

p4 <- results_40_final %>% 
  ggplot(aes(x = time, y = value, group = name)) + 
  geom_line(aes(color = name)) + 
  scale_color_jama()

results <- rbind(results_26_final, results_30_final, results_35_final, results_40_final, results_40_final) %>% 
  add_column(group = rep(c("<= 26", "<= 30", "<= 35", "<= 40", "<= 45"), each = (4*65))) 
  
p <- results %>% 
  mutate(t = time + 20, value = value/n) %>% 
  filter(name %in% c("healthy", "dead")) %>%
  ggplot(aes(x = t, y = value)) + 
  geom_line(aes(color = name, linetype = group)) + 
  scale_color_aaas() + 
  theme_bw() + 
  theme(legend.position = "bottom") + 
  labs(linetype = "Vaccination age cap", 
       x = "Age", y = "Number of people", color = "Status") +
  guides(
    color = guide_legend(position = "top"),
    linetype  = guide_legend(position = "bottom")
  )

ggplotly(p) 

cost_pre <- 100
cost_can <- 500
cost_26 <- cumsum(results_26%*%c(0, cost_pre, cost_can, 0))
cost_30 <- cumsum(results_30%*%c(0, cost_pre, cost_can, 0))
cost_35 <- cumsum(results_35%*%c(0, cost_pre, cost_can, 0))
cost_40 <- cumsum(results_40%*%c(0, cost_pre, cost_can, 0))
cost_45 <- cumsum(results_45%*%c(0, cost_pre, cost_can, 0))

p_cost <- as_tibble(cbind(cost_26, cost_30, cost_35, cost_40, cost_45)) %>% 
  mutate(time = (seq_along(cost_26) + 19)) %>% 
  pivot_longer(cols = -c(time)) %>% 
  mutate(value = value/n) %>% 
  ggplot(aes(x = time, y = value)) + 
  geom_line(aes(color = name)) + 
  scale_color_aaas() + 
  theme_bw() + 
  theme(legend.position = "bottom") + 
  labs(color = "Vaccination age cap", 
       x = "Age", y = "Cost/person") +
  guides(
    color = guide_legend(position = "bottom")
  )

ggplotly(p_cost)
  
