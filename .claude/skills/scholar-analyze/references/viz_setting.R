# Publication-quality visualization functions for social science journals
# Targets: Nature (NHB, NCS), Science Advances, ASR, AJS, Demography, PNAS
#
# Provides:
#   theme_Publication()                    — base theme (scales with base_size)
#   scale_fill_Publication()               — discrete fill (Wong 2011)
#   scale_colour_Publication()             — discrete colour (Wong 2011)
#   scale_fill_continuous_Publication()    — continuous fill (viridis)
#   scale_colour_continuous_Publication()  — continuous colour (viridis)
#   scale_fill_diverging_Publication()     — diverging fill (blue-white-red)
#   set_geom_defaults_Publication()        — auto-size points/lines for canvas
#   assemble_panels()                      — multi-panel figure with tags
#   save_fig_cmyk()                        — CMYK export for print journals
#   preview_grayscale()                    — check B&W readability

library(grid)
library(ggplot2)
library(scales)

# ── Theme ─────────────────────────────────────────────────────────────────────

theme_Publication <- function(base_size = 12, base_family = "Helvetica Neue") {
  # Scale line weights and tick geometry with base_size
  lw <- base_size / 24            # axis/tick linewidth: 0.5pt at size 12, 0.33pt at size 8
  tick_len <- -0.12 * base_size   # inward ticks scale proportionally
  tick_margin <- 0.15 * base_size # mm offset so labels clear the inward ticks

  # Enforce minimum text size (Nature rejects < 5pt after scaling)
  axis_text_rel <- max(rel(0.85), rel(5 / base_size))

  theme_bw(base_size = base_size, base_family = base_family) %+replace%
    theme(
      # Text — propagate base_family (Nature requires sans-serif)
      text              = element_text(family = base_family, colour = "black"),
      plot.title        = element_text(size = rel(1.2), hjust = 0.5,
                                       margin = margin(b = base_size * 0.4)),

      # Panel — element_blank() is more bulletproof than colour=NA for border
      panel.background  = element_rect(fill = "white", colour = NA),
      plot.background   = element_rect(fill = "white", colour = NA),
      panel.border      = element_blank(),
      panel.grid.major  = element_blank(),
      panel.grid.minor  = element_blank(),

      # Axes — linewidth scales so Nature single-col (base_size=8) gets ~0.3pt
      axis.line         = element_line(colour = "black", linewidth = lw),
      axis.ticks        = element_line(colour = "black", linewidth = lw),
      axis.ticks.length = unit(tick_len, "pt"),
      axis.title        = element_text(size = rel(1)),
      axis.title.y      = element_text(angle = 90, vjust = 2),
      axis.title.x      = element_text(vjust = -0.2),
      axis.text         = element_text(size = axis_text_rel, colour = "black"),
      axis.text.x       = element_text(margin = margin(t = tick_margin)),
      axis.text.y       = element_text(margin = margin(r = tick_margin)),

      # Legend — explicit blank background prevents PDF ghost outlines
      legend.background = element_rect(fill = "white", colour = NA),
      legend.key        = element_rect(fill = "white", colour = NA),
      legend.key.size   = unit(base_size * 0.9, "pt"),
      legend.position   = "right",
      legend.margin     = margin(t = 0),
      legend.title      = element_text(face = "italic"),
      legend.text       = element_text(size = rel(0.8)),

      # Facets
      strip.background  = element_rect(fill = "#f0f0f0", colour = NA),
      strip.text        = element_text(face = "bold", size = rel(0.9)),

      # Panel tags (A, B, C) — Nature style: bold, top-left
      plot.tag          = element_text(face = "bold", size = rel(1.2)),
      plot.tag.position = "topleft",

      # Margins — 5pt minimum so typesetters don't clip
      plot.margin       = margin(5, 5, 5, 5, "pt")
    )
}


# ── Wong 2011 colorblind-safe palette (Nature Methods 8:441) ──────────────────

.wong_palette <- c("#0072B2", "#E69F00", "#009E73", "#CC79A7",
                   "#56B4E9", "#F0E442", "#D55E00", "#000000")

scale_fill_Publication <- function(...) {
  discrete_scale("fill", "Publication",
                 manual_pal(values = .wong_palette), ...)
}

scale_colour_Publication <- function(...) {
  discrete_scale("colour", "Publication",
                 manual_pal(values = .wong_palette), ...)
}


# ── Continuous scale helpers ──────────────────────────────────────────────────

scale_fill_continuous_Publication <- function(option = "viridis", ...) {
  scale_fill_viridis_c(option = option, ...)
}

scale_colour_continuous_Publication <- function(option = "viridis", ...) {
  scale_colour_viridis_c(option = option, ...)
}

## Diverging (correlation matrices, change scores)
scale_fill_diverging_Publication <- function(
    low = "#0072B2", mid = "white", high = "#D55E00", ...) {
  scale_fill_gradient2(low = low, mid = mid, high = high, ...)
}


# ── Geom defaults setter ─────────────────────────────────────────────────────
# Auto-adjust point/line sizes so figures are legible at the target canvas size.
# Call once after sourcing: set_geom_defaults_Publication("nature_single")

set_geom_defaults_Publication <- function(preset = "default") {
  presets <- list(
    default       = list(point_size = 1.5, line_size = 0.6, errorbar_size = 0.5),
    nature_single = list(point_size = 1.0, line_size = 0.4, errorbar_size = 0.3),
    nature_double = list(point_size = 1.5, line_size = 0.5, errorbar_size = 0.4),
    asr           = list(point_size = 1.5, line_size = 0.6, errorbar_size = 0.5),
    ajs           = list(point_size = 1.5, line_size = 0.6, errorbar_size = 0.5),
    demography    = list(point_size = 1.5, line_size = 0.6, errorbar_size = 0.5),
    ncs           = list(point_size = 1.0, line_size = 0.4, errorbar_size = 0.3),
    ncs_double    = list(point_size = 1.5, line_size = 0.5, errorbar_size = 0.4),
    social_forces = list(point_size = 1.5, line_size = 0.6, errorbar_size = 0.5),
    gender_soc    = list(point_size = 1.5, line_size = 0.6, errorbar_size = 0.5),
    lang_soc      = list(point_size = 1.5, line_size = 0.5, errorbar_size = 0.4),
    j_socioling   = list(point_size = 1.5, line_size = 0.5, errorbar_size = 0.4),
    ling_inquiry  = list(point_size = 1.5, line_size = 0.5, errorbar_size = 0.4),
    apsr          = list(point_size = 1.5, line_size = 0.6, errorbar_size = 0.5),
    jmf           = list(point_size = 1.5, line_size = 0.6, errorbar_size = 0.5),
    pdr           = list(point_size = 1.5, line_size = 0.6, errorbar_size = 0.5),
    smr           = list(point_size = 1.5, line_size = 0.5, errorbar_size = 0.4),
    poetics       = list(point_size = 1.5, line_size = 0.5, errorbar_size = 0.4),
    dubois        = list(point_size = 1.5, line_size = 0.6, errorbar_size = 0.5),
    pnas          = list(point_size = 1.0, line_size = 0.4, errorbar_size = 0.3),
    pnas_double   = list(point_size = 1.5, line_size = 0.5, errorbar_size = 0.4),
    sciadv        = list(point_size = 1.5, line_size = 0.5, errorbar_size = 0.4)
  )
  p <- presets[[preset]]
  if (is.null(p)) {
    message("Unknown preset '", preset, "'. Using default.")
    p <- presets[["default"]]
  }
  update_geom_defaults("point",    list(size = p$point_size, stroke = 0.3))
  update_geom_defaults("line",     list(linewidth = p$line_size))
  update_geom_defaults("smooth",   list(linewidth = p$line_size))
  update_geom_defaults("errorbar", list(linewidth = p$errorbar_size))
  update_geom_defaults("errorbarh", list(linewidth = p$errorbar_size))
  message("Geom defaults set for '", preset, "': point=", p$point_size,
          ", line=", p$line_size, ", errorbar=", p$errorbar_size)
}


# ── Multi-panel assembly ─────────────────────────────────────────────────────
# Wraps patchwork with consistent sizing + bold uppercase tags.
# Usage: assemble_panels(p1, p2, p3, ncol = 2, tag_size = 14)

assemble_panels <- function(..., ncol = NULL, nrow = NULL,
                            tag_size = 14, tag_face = "bold") {
  if (!requireNamespace("patchwork", quietly = TRUE))
    stop("Install patchwork: install.packages('patchwork')")

  plots <- list(...)
  combined <- patchwork::wrap_plots(plots, ncol = ncol, nrow = nrow) +
    patchwork::plot_annotation(tag_levels = "A") &
    theme(plot.tag = element_text(face = tag_face, size = tag_size))
  combined
}


# ── CMYK export helper ───────────────────────────────────────────────────────
# For print journals (ASR, AJS, Demography) that want CMYK color space.
# Requires ghostscript (gs) installed.

save_fig_cmyk <- function(p, name, width = 6, height = 4.5, dpi = 300,
                          output_root = Sys.getenv("OUTPUT_ROOT", "output")) {
  dir.create(file.path(output_root, "figures"), showWarnings = FALSE, recursive = TRUE)
  rgb_path  <- file.path(output_root, "figures", paste0(name, ".pdf"))
  cmyk_path <- file.path(output_root, "figures", paste0(name, "-cmyk.pdf"))
  # Save RGB PDF first
  ggsave(rgb_path, plot = p, device = cairo_pdf, width = width, height = height)
  # Convert to CMYK via ghostscript
  gs_cmd <- sprintf(
    'gs -dSAFER -dBATCH -dNOPAUSE -dNOCACHE -sDEVICE=pdfwrite -sColorConversionStrategy=CMYK -dProcessColorModel=/DeviceCMYK -sOutputFile="%s" "%s"',
    cmyk_path, rgb_path
  )
  result <- system(gs_cmd, intern = TRUE, ignore.stderr = TRUE)
  if (file.exists(cmyk_path)) {
    message("Saved CMYK: ", cmyk_path)
  } else {
    message("CMYK conversion failed (is ghostscript installed?). RGB saved: ", rgb_path)
  }
}


# ── Journal dimension presets ──────────────────────────────────────────────────
# Usage: dims <- jdims[["asr"]]; save_fig(p, "fig1", width=dims$w, height=dims$h)
# Or use save_fig(p, "fig1", journal="asr") for automatic lookup.

jdims <- list(
  default       = list(w = 6,   h = 4.5,  base_size = 12),
  # Nature family
  nhb_single    = list(w = 3.5, h = 3,    base_size = 8),
  nhb_double    = list(w = 7.1, h = 4.5,  base_size = 10),
  ncs_single    = list(w = 3.5, h = 3,    base_size = 8),
  ncs_double    = list(w = 7.1, h = 4.5,  base_size = 10),
  # Science / PNAS
  sciadv        = list(w = 7,   h = 4.5,  base_size = 10),
  pnas          = list(w = 3.4, h = 3,    base_size = 8),
  pnas_double   = list(w = 7,   h = 4.5,  base_size = 10),
  # Sociology journals
  asr           = list(w = 6.5, h = 4.5,  base_size = 12),
  ajs           = list(w = 6.5, h = 4.5,  base_size = 12),
  demography    = list(w = 6.5, h = 4.5,  base_size = 11),
  social_forces = list(w = 6.5, h = 4.5,  base_size = 12),
  gender_soc    = list(w = 6.5, h = 4.5,  base_size = 12),
  dubois        = list(w = 6.5, h = 4.5,  base_size = 12),
  # Political science
  apsr          = list(w = 6.5, h = 4.5,  base_size = 12),
  # Family / population
  jmf           = list(w = 6.5, h = 4.5,  base_size = 12),
  pdr           = list(w = 6.5, h = 4.5,  base_size = 11),
  # Methods / culture
  smr           = list(w = 6,   h = 4,    base_size = 11),
  poetics       = list(w = 6,   h = 4,    base_size = 11),
  # Linguistics
  lang_soc      = list(w = 6,   h = 4,    base_size = 11),
  j_socioling   = list(w = 6,   h = 4,    base_size = 11),
  ling_inquiry  = list(w = 6,   h = 4,    base_size = 11)
)


# ── Unified save_fig helper ──────────────────────────────────────────────────
# Usage: save_fig(p, "fig1", journal = "asr")
#        save_fig(p, "fig1", width = 6.5, height = 4.5)

save_fig <- function(p, name, width = NULL, height = NULL, journal = NULL,
                     dpi = 300, output_root = Sys.getenv("OUTPUT_ROOT", "output")) {
  dir.create(file.path(output_root, "figures"), showWarnings = FALSE, recursive = TRUE)

  if (!is.null(journal)) {
    dims <- jdims[[journal]]
    if (is.null(dims)) dims <- jdims[["default"]]
    if (is.null(width))  width  <- dims$w
    if (is.null(height)) height <- dims$h
  }
  if (is.null(width))  width  <- 6
  if (is.null(height)) height <- 4.5

  pdf_path <- file.path(output_root, "figures", paste0(name, ".pdf"))
  png_path <- file.path(output_root, "figures", paste0(name, ".png"))

  ggsave(pdf_path, plot = p, device = cairo_pdf, width = width, height = height)
  ggsave(png_path, plot = p, device = "png", width = width, height = height, dpi = dpi)

  message("Saved: ", pdf_path, " + ", png_path)
}


# ── Grayscale preview ─────────────────────────────────────────────────────────
# Check if your figure is readable when printed in B&W.
# Returns the grayscale version — inspect visually.

preview_grayscale <- function(p) {
  p + scale_colour_grey() + scale_fill_grey()
}
