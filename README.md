# World Intellectual Property Indicators (WIPI) 2026 — Choropleth Map with R


An automated data pipeline and interactive **R Shiny** dashboard that scrapes statistical datasets from the **World Intellectual Property Organization (WIPO)**, and renders global choropleth maps.

---

## Table of Contents
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Running the App](#running-the-app)
- [Project Structure](#project-structure)
- [Configuration & Customization](#configuration--customization)
- [Contributing](#contributing)
- [License & Data Attribution](#license--data-attribution)

## Getting Started

### Prerequisites

- **R** (`>= 4.1.0`)
- An active internet connection on initial launch to fetch WIPO datasets.

### Installation

1. **Install required R packages:**
   ```r
   install.packages(c(
     "rvest",
     "stringr",
     "httr2",
     "readxl",
     "readr",
     "tibble",
     "dplyr",
     "tidyverse",
     "digest",
     "purrr",
     "shiny",
     "ggplot2",
     "sf",
     "rnaturalearth",
     "rnaturalearthdata",
     "jsonlite",
     "scales"
   ))
   ```

### Running the App

Launch the Shiny application from R or RStudio:

```r
shiny::runApp("scraping.R")
```

## Project Structure

```text
├── scraping.R              # Complete pipeline: WIPO scraper, Excel parser, spatial normalizer, and Shiny app
├── downloads/         # Created automatically at runtime to store downloaded/extracted WIPO files (gitignored)
├── .gitignore         # Recommended to ignore downloads/ and local R session files
└── README.md          # Project documentation
```

