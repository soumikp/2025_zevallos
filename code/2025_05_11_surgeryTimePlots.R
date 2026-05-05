rm(list = ls())

pacman::p_load(here, tidyverse, ggsci, patchwork, plotly, lubridate, ggpubfigs)

data <- read.csv(file.path(here(), "data", "2025_05_06", "Surgery by HPV, facility location and type, and year, 2013-2021.csv")) |> 
  select(c(1,2,3,4,5,6, 7))


model_pos <- lm(percent_yes ~ Year, data = data |>  mutate(Year = YEAR_OF_DIAGNOSIS.f - 2013) |> filter(HPV_status_new == "Positive") )
model_neg <- lm(percent_yes ~ Year, data = data |>  mutate(Year = YEAR_OF_DIAGNOSIS.f - 2013) |> filter(HPV_status_new == "Negative") )
model_uk <- lm(percent_yes ~ Year, data = data |>  mutate(Year = YEAR_OF_DIAGNOSIS.f - 2013) |> filter(HPV_status_new == "Unknown") )

model_pos <- sprintf("%0.2f", c(summary(model_pos)$coefficients[2,1], confint(model_pos)[2,]))
model_neg <- sprintf("%0.2f", c(summary(model_neg)$coefficients[2,1], confint(model_neg)[2,]))
model_uk <- sprintf("%0.2f", c(summary(model_uk)$coefficients[2,1], confint(model_uk)[2,]))

data$HPV_status_new <- factor(data$HPV_status_new, levels = c("Positive", "Negative", "Unknown"))


plot <- data |> 
  #group_by(HPV_status_new, FACILITY_LOCATION_LABEL, YEAR_OF_DIAGNOSIS.f) |>
  #summarise(percent_yes = 100*sum(yes_surgery)/sum(total_n)) |>
  #ungroup() |> 
  mutate(Year = ymd(paste0(YEAR_OF_DIAGNOSIS.f, "-01-01"))) |> 
  ggplot(aes(x = Year, y = percent_yes, group = HPV_status_new)) + 
  geom_point(aes(color = HPV_status_new), size = 2) + 
  #geom_line(aes(color = HPV_status_new, linetype = HPV_status_new), linewidth = 1) + 
  geom_smooth(aes(color = HPV_status_new), method = "lm", se = TRUE, fill = "gray90") +
  scale_color_manual(values = friendly_pal("contrast_three")) + 
  labs(y = "% of surgeries", x = "\nYear", color = "HPV Status", linetype = "HPV Status") + 
  facet_grid(cols = vars(HPV_status_new), scales = "free", rows = vars(FACILITY_LOCATION_LABEL)) + 
  theme_bw() + 
  theme(legend.position = "bottom", 
        strip.background = element_rect(fill = "black"), 
        strip.text = element_text(color = "white", face = "bold", size = 12),
        axis.text = element_text(face = "bold", size = 12),
        axis.title = element_text(face = "bold", size = 12)) + 
  scale_x_continuous(breaks = ymd(paste0(c(2013:2021), "-01-01")), labels = c(2013:2021)) + 
  scale_linetype_manual(values = c("twodash", "dotted", "dashed")) #+ 
#scale_y_continuous(limits = c(23, 46), breaks = seq(25, 45, 5), labels = seq(25,45, 5))

factor <- 2
ggsave(file.path(here(), "analysis", "2025_05_11_surgeryTimePlots_location.pdf"), plot, 
       height = factor*6,  width = factor*11, units = "in", device = pdf())




