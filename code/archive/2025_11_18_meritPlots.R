rm(list = ls())

pacman::p_load(here, tidyverse, ggsci, patchwork, plotly, lubridate, ggpubfigs, readxl)

data <- read_xlsx(file.path(here(), "data", "2025_11_18_pctData.xlsx"), sheet = 2) 

plot_tv_vacPrev <- data |> 
  filter(AgeAtYear %in% c(25, 30, 35, 40, 45)) |>
  mutate(AgeAtYear = factor(AgeAtYear, levels = c(25, 30, 35, 40, 45))) |> 
  ggplot(aes(x = CY, y = PCT_ROW)) + 
  geom_line(aes(color = AgeAtYear), linewidth = 2) + 
  geom_point(size = 6) + 
  scale_color_bmj() + 
  theme_big_simple() + 
  labs(x = "Calendar Year", y = "Vaccination prevalence (%)")


factor = 1.650
# ggsave(file.path("/Users/soumik/Desktop/2025_11_18_simulation.pdf"), 
#        plot_sim, 
#        height = factor*8.5, 
#        width = factor*11, 
#        units = "in")

ggsave(file.path(file.path(here(), "documents", "2025_11_18_prevPlots.pdf")), 
       plot_tv_vacPrev, 
       height = factor*8.5, 
       width = factor*11, 
       units = "in")

