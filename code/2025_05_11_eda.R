rm(list = ls())

pacman::p_load(here, tidyverse, ggsci, patchwork, plotly, lubridate, ggpubfigs)

data <- read.csv(file.path(here(), "data", "2025_05_06", "Surgery by HPV, facility location and type, and year, 2013-2021.csv")) |> 
  select(c(1,2,3,4,5,6, 7)) |>
  rename(HPV_status = HPV_status_new, 
         YEAR = YEAR_OF_DIAGNOSIS.f)

# Basic data cleaning
surgery_data <- data %>%
  mutate(
    HPV_status = factor(HPV_status, levels = c("Positive", "Negative", "Unknown")),
    YEAR = as.numeric(YEAR),
    surgery_pct = (yes_surgery / total_n) * 100
  )

# Basic summary statistics
summary_stats <- surgery_data %>%
  filter(FACILITY_LOCATION_LABEL != "Unknown", 
         FACILITY_TYPE_LABEL != "Unknown") |> 
  group_by(YEAR, HPV_status) %>%
  summarize(
    avg_surgery_pct = mean(surgery_pct, na.rm = TRUE),
    median_surgery_pct = median(surgery_pct, na.rm = TRUE),
    sd_surgery_pct = sd(surgery_pct, na.rm = TRUE),
    n_facilities = n(),
    .groups = "drop"
  )

# Print summary statistics
print(summary_stats)

# Create overall trend plot
p1 <- ggplot(summary_stats |> mutate(YEAR = ymd(paste0(YEAR, "01-01"))), aes(x = YEAR, y = avg_surgery_pct, color = HPV_status)) +
  geom_line(size = 1) +
  geom_point(size = 2) +
  geom_errorbar(aes(ymin = avg_surgery_pct - sd_surgery_pct, 
                    ymax = avg_surgery_pct + sd_surgery_pct), linetype = "dashed") +
  facet_grid(cols = vars(HPV_status)) + 
  geom_smooth() + 
  labs(title = "Overall Trend of Surgery Percentage by HPV Status",
       x = "Year", y = "% of Patients Receiving Surgery") +
  theme_bw() + 
  theme(legend.position = "bottom", 
        strip.background = element_rect(fill = "black"), 
        strip.text = element_text(color = "white", face = "bold", size = 12),
        axis.text = element_text(face = "bold", size = 12),
        axis.title = element_text(face = "bold", size = 12)) + 
  scale_x_date(breaks = ymd(paste0(c(2013:2021), "-01-01")), labels = c(2013:2021)) + 
  scale_linetype_manual(values = c("twodash", "dotted", "dashed")) + 
  scale_color_aaas()

print(p1)

# Analyze by facility location
location_summary <- surgery_data %>%
  filter(FACILITY_LOCATION_LABEL != "Unknown", 
         FACILITY_TYPE_LABEL != "Unknown") |> 
  group_by(YEAR, HPV_status, FACILITY_LOCATION_LABEL) %>%
  summarize(
    avg_surgery_pct = mean(surgery_pct, na.rm = TRUE),
    n_facilities = n(),
    .groups = "drop"
  )

# Plot by location
p2 <- ggplot(location_summary |> mutate(YEAR = ymd(paste0(YEAR, "01-01"))), 
             aes(x = YEAR, y = avg_surgery_pct, color = HPV_status)) +
  geom_line() +
  geom_point() +
  facet_grid(cols = vars(FACILITY_LOCATION_LABEL), rows = vars(HPV_status), scales = "free") +
  geom_smooth(method = "lm") + 
  labs(title = "Surgery Percentage Trends by Facility Location",
       x = "Year", y = "% of Patients Receiving Surgery") +
  theme_bw() + 
  theme(legend.position = "bottom", 
        strip.background = element_rect(fill = "black"), 
        strip.text = element_text(color = "white", face = "bold", size = 12),
        axis.text = element_text(face = "bold", size = 12),
        axis.title = element_text(face = "bold", size = 12)) + 
  scale_x_date(breaks = ymd(paste0(c(2013:2021), "-01-01")), labels = c(2013:2021)) + 
  scale_linetype_manual(values = c("twodash", "dotted", "dashed")) + 
  scale_color_aaas() + 
  theme(axis.text.x = element_text(angle = 90, hjust = 1))

print(p2)

# Analyze by facility type
type_summary <- surgery_data %>%
  filter(FACILITY_LOCATION_LABEL != "Unknown", 
         FACILITY_TYPE_LABEL != "Unknown") |> 
  group_by(YEAR, HPV_status, FACILITY_TYPE_LABEL) %>%
  summarize(
    avg_surgery_pct = mean(surgery_pct, na.rm = TRUE),
    n_facilities = n(),
    .groups = "drop"
  )

# Plot by facility type
p3 <- ggplot(type_summary |> mutate(YEAR = ymd(paste0(YEAR, "01-01"))), 
             aes(x = YEAR, y = avg_surgery_pct, color = HPV_status)) +
  geom_line() +
  geom_point() +
  facet_grid(cols = vars(FACILITY_TYPE_LABEL), rows = vars(HPV_status), scales = "free") +
  geom_smooth(method = "lm") + 
  labs(title = "Surgery Percentage Trends by Facility Type",
       x = "Year", y = "% of Patients Receiving Surgery") +
  theme_bw() + 
  theme(legend.position = "bottom", 
        strip.background = element_rect(fill = "black"), 
        strip.text = element_text(color = "white", face = "bold", size = 12),
        axis.text = element_text(face = "bold", size = 12),
        axis.title = element_text(face = "bold", size = 12)) + 
  scale_x_date(breaks = ymd(paste0(c(2013:2021), "-01-01")), labels = c(2013:2021)) + 
  scale_linetype_manual(values = c("twodash", "dotted", "dashed")) + 
  scale_color_aaas() + 
  theme(axis.text.x = element_text(angle = 90, hjust = 1))

print(p3)

# Calculate variation metrics
variation_by_location <- surgery_data %>%
  filter(FACILITY_LOCATION_LABEL != "Unknown", 
         FACILITY_TYPE_LABEL != "Unknown") |> 
  group_by(YEAR, FACILITY_LOCATION_LABEL) %>%
  summarize(
    location_cv = sd(surgery_pct, na.rm = TRUE) / mean(surgery_pct, na.rm = TRUE),
    .groups = "drop"
  ) #|> 
  #pivot_wider(names_from = FACILITY_LOCATION_LABEL, values_from = location_cv)

variation_by_type <- surgery_data %>%
  filter(FACILITY_LOCATION_LABEL != "Unknown", 
         FACILITY_TYPE_LABEL != "Unknown") |> 
  group_by(YEAR, FACILITY_TYPE_LABEL) %>%
  summarize(
    type_cv = sd(surgery_pct, na.rm = TRUE) / mean(surgery_pct, na.rm = TRUE),
    .groups = "drop"
  )#|> 
  #pivot_wider(names_from = FACILITY_TYPE_LABEL, values_from = type_cv)

# Plot coefficient of variation over time
p4 <- ggplot(variation_by_location, aes(x = YEAR, y = location_cv, 
                                        color = FACILITY_LOCATION_LABEL)) +
  geom_smooth(aes(group = FACILITY_LOCATION_LABEL), se = FALSE) +
  geom_point() +
  labs(title = "Variation in Surgery Rates by Location Over Time",
       x = "Year", y = "Coefficient of Variation") +
  theme_minimal() + 
  scale_x_continuous(breaks = c(2013:2021), labels = c(2013:2021)) + 
  scale_color_aaas()

print(p4)

# Plot coefficient of variation over time
p5 <- ggplot(variation_by_type, aes(x = YEAR, y = type_cv, 
                                        color = FACILITY_TYPE_LABEL)) +
  geom_smooth(aes(group = FACILITY_TYPE_LABEL), se = FALSE) +
  geom_point() +
  labs(title = "Variation in Surgery Rates by Type Over Time",
       x = "Year", y = "Coefficient of Variation") +
  theme_minimal() + 
  scale_x_continuous(breaks = c(2013:2021), labels = c(2013:2021)) + 
  scale_color_aaas()

print(p5)

# Create heatmap of surgery rates by region and year for HPV positive cases
p6 <- surgery_data %>%
  group_by(HPV_status, FACILITY_LOCATION_LABEL, FACILITY_TYPE_LABEL) |> 
  filter(FACILITY_LOCATION_LABEL != "Unknown", 
         FACILITY_TYPE_LABEL != "Unknown") |> 
  summarise(pct = 100*sum(yes_surgery)/sum(total_n)) |> 
  ungroup() |> 
  ggplot() + 
  geom_tile(aes(y = FACILITY_LOCATION_LABEL, x = FACILITY_TYPE_LABEL, 
                fill = pct), color = "black") + 
  facet_grid(cols = vars(HPV_status)) + 
  scale_fill_gsea(alpha = 0.5) + 
  scale_x_discrete(expand = c(0, 0)) + 
  scale_y_discrete(expand = c(0, 0)) + 
  geom_text(aes(y = FACILITY_LOCATION_LABEL, x = FACILITY_TYPE_LABEL, 
                label = sprintf("%0.2f", pct)), fontface = "bold") + 
  theme_bw() + 
  theme(legend.position = "bottom", 
        strip.background = element_rect(fill = "black"), 
        strip.text = element_text(color = "white", face = "bold", size = 12),
        axis.text = element_text(face = "bold", size = 12),
        axis.title = element_text(face = "bold", size = 12)) + 
  theme(axis.text.x = element_text(angle = 90, hjust = 1)) + 
  labs(x = "", y = "")

print(p6)

factor <- 1
ggsave(file.path(here(), "analysis", "2025_05_11_eda1_hpv.pdf"), 
       p1, 
       height = factor*8.5,  width = factor*11, units = "in", device = pdf())

ggsave(file.path(here(), "analysis", "2025_05_11_eda2_hpv_location.pdf"), 
       p2, 
       height = factor*8.5,  width = factor*11, units = "in", device = pdf())

ggsave(file.path(here(), "analysis", "2025_05_11_eda3_hpv_type.pdf"), 
       p3, 
       height = factor*8.5,  width = factor*11, units = "in", device = pdf())

ggsave(file.path(here(), "analysis", "2025_05_11_eda4_var_location.pdf"), 
       p4, 
       height = factor*8.5,  width = factor*11, units = "in", device = pdf())

ggsave(file.path(here(), "analysis", "2025_05_11_eda5_var_type.pdf"), 
       p5, 
       height = factor*8.5,  width = factor*11, units = "in", device = pdf())

ggsave(file.path(here(), "analysis", "2025_05_11_eda6_loc_type.pdf"), 
       p6, 
       height = factor*8.5,  width = factor*11, units = "in", device = pdf())



