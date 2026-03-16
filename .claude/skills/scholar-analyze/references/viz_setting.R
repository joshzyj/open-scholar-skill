# define some visualization functions
## let us define some ggplot themes and scales
theme_Publication <- function(base_size=12, base_family="Helvetica Neue") {
  library(grid)
  library(ggthemes)
  (theme_foundation(base_size=base_size)
    + theme(plot.title = element_text(size = rel(1.2), hjust = 0.5),
            text = element_text(),
            panel.background = element_rect(colour = NA),
            plot.background = element_rect(colour = NA),
            panel.border = element_rect(colour = NA),
            axis.title = element_text(size = rel(1)),
            axis.title.y = element_text(angle=90,vjust =2),
            axis.title.x = element_text(vjust = -0.2),
            axis.text = element_text(), 
            axis.line = element_line(colour="black"),
            axis.ticks = element_line(),
            axis.ticks.length = unit(-1.4, "mm"),
            axis.text.x = element_text(margin = unit(c(t = 1, r = 2.5, b = 0, l = 0), "mm")),
            axis.text.y = element_text(margin = unit(c(t = 1, r = 0, b =0, l =2.5), "mm")),
            panel.grid.major = element_blank(),
            panel.grid.minor = element_blank(),
            legend.key = element_rect(colour = NA),
            legend.position = "right",
            #            legend.direction = "horizontal",
            #            legend.key.size= unit(0.2, "cm"),
            legend.margin = margin(t=0,unit="cm"),
            legend.title = element_text(face="italic"),
            plot.margin=unit(c(1,1,1,1),"mm"),
            strip.background=element_rect(colour="#f0f0f0",fill="#f0f0f0"),
            strip.text = element_text(face="bold")
    ))
  
}

scale_fill_Publication <- function(...){
  library(scales)
  discrete_scale("fill","Publication",
                 manual_pal(values = c("#386cb0","#fdb462",
                                       "#7fc97f","#ef3b2c",
                                       "#662506","#a6cee3",
                                       "#fb9a99","#bdbdbd","#984ea3",
                                       "#fa9fb5","#feb24c",
                                       "#9ebcda","#e0ecf4",
                                       "#f03b20","#8856a7")), ...)
  
}

scale_colour_Publication <- function(...){
  library(scales)
  discrete_scale("colour","Publication",
                 manual_pal(values = c("#984ea3","#fdb462",
                                       "#7fc97f","#ef3b2c",
                                       "#662506","#a6cee3",
                                       "#fb9a99","#bdbdbd",
                                       "#fa9fb5","#feb24c",
                                       "#9ebcda","#e0ecf4",
                                       "#f03b20","#8856a7")), ...)
  
}
