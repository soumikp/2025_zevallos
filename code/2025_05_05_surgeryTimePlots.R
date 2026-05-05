rm(list = ls())

pacman::p_load(here, tidyverse, ggsci, patchwork, plotly, lubridate, ggpubfigs)

data <- read.csv(file.path(here(), "data", "surgery_by_year_HPV.csv")) |> 
  select(c(1,2,3,4, 5))

model_pos <- lm(surgery_percent ~ Year, data = data |>  mutate(Year = Year - 2013) |> filter(HPV_status == "Positive") )
model_neg <- lm(surgery_percent ~ Year, data = data |>  mutate(Year = Year - 2013) |> filter(HPV_status == "Negative") )
model_uk <- lm(surgery_percent ~ Year, data = data |>  mutate(Year = Year - 2013) |> filter(HPV_status == "Unknown") )

model_pos <- sprintf("%0.2f", c(summary(model_pos)$coefficients[2,1], confint(model_pos)[2,]))
model_neg <- sprintf("%0.2f", c(summary(model_neg)$coefficients[2,1], confint(model_neg)[2,]))
model_uk <- sprintf("%0.2f", c(summary(model_uk)$coefficients[2,1], confint(model_uk)[2,]))

data |> 
  group_by(HPV_status) |> 
  summarise(pos = (max(surgery_percent) +  min(surgery_percent))/2)

plot <- data |> 
  mutate(Year = ymd(paste0(Year, "-01-01"))) |> 
  mutate(text = case_when(HPV_status == "Positive" ~ paste0("Slope of fitted line (95% CI)\n", model_pos[1], " (", model_pos[2], " to ", model_pos[3], ")"), 
                          HPV_status == "Negative" ~ paste0("Slope of fitted line (95% CI)\n", model_neg[1], " (", model_neg[2], " to ", model_neg[3], ")"), 
                          HPV_status == "Unknown" ~ paste0("Slope of fitted line (95% CI)\n", model_uk[1], " (", model_uk[2], " to ", model_uk[3], ")")), 
         text_y_pos = case_when(HPV_status == "Positive" ~ 36.2, 
                                HPV_status == "Negative" ~ 29.1,
                                HPV_status == "Unknown" ~ 28.3)) |> 
  ggplot(aes(x = Year, y = surgery_percent, group = HPV_status)) + 
  geom_point(aes(color = HPV_status), size = 2) + 
  geom_line(aes(color = HPV_status, linetype = HPV_status), linewidth = 1) + 
  geom_smooth(aes(color = HPV_status), method = "lm", se = TRUE, fill = "gray90") +
  geom_text(aes(y = text_y_pos, x = ymd(paste0(2021, "-01-01")), label = text), hjust = 1) + 
  scale_color_manual(values = friendly_pal("contrast_three")) + 
  labs(y = "% of surgeries", x = "Year", color = "HPV Status", linetype = "HPV Status") + 
  facet_grid(rows = vars(HPV_status), scales = "free") + 
  theme_bw() + 
  theme(legend.position = "bottom", 
        strip.background = element_rect(fill = "black"), 
        strip.text = element_text(color = "white", face = "bold", size = 12),
        axis.text = element_text(face = "bold", size = 12),
        axis.title = element_text(face = "bold", size = 12)) + 
  scale_x_continuous(breaks = ymd(paste0(c(2013:2021), "-01-01")), labels = c(2013:2021)) + 
  scale_linetype_manual(values = c("twodash", "dotted", "dashed")) #+ 
  #scale_y_continuous(limits = c(23, 46), breaks = seq(25, 45, 5), labels = seq(25,45, 5))

factor <- 1.00
ggsave(file.path(here(), "analysis", "2025_05_05_surgeryTimePlots.pdf"), plot, 
       width = factor*8.5,  height = factor*11, units = "in", device = pdf())




