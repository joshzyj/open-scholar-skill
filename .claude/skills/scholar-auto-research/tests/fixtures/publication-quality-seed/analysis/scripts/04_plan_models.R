# Planned model execution script for fixture validation.
library(modelsummary)
library(ggplot2)
source("analysis/scripts/viz_setting.R")
ggplot(data.frame(x = 1, y = 1), aes(x = x, y = y)) + geom_point() + theme_Publication()
print("run models")
