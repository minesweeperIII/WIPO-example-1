# World Intellectual Property Indicators (WIPI) 2026 — Choropleth Map with R

An automated data pipeline and interactive **R Shiny** dashboard that scrapes statistical datasets from the **World Intellectual Property Organization (WIPO)**, parses country-level Excel tables, and renders global choropleth maps.

**Data Source:** [WIPO World Intellectual Property Indicators](https://www.wipo.int/publications/en/details.jsp?id=4886)

---

## Project Structure   

```text
├── scraping.R         # Scrapes and extracts WIPO Excel/ZIP datasets into downloads/
├── shinyApp.R         # Parses Excel tables, normalizes country names, and launches the Shiny map app
├── downloads/         # Created automatically by scraping.R to store WIPO datasets
├── .gitignore         # Ignores downloads/ and local R session files
└── README.md          # Project documentation
```

## Getting Started

### Prerequisites

- **R** (`>= 4.1.0`)
- An active internet connection when running scraping.R to fetch datasets from WIPO.

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

### Usage

#### 1. Scraping data    

Run the scraping script to download and extract the WIPO Excel workbooks into the "downloads" folder:
```r     
source("scraping.R")
```    

#### 2. Running the App

Once the datasets are downloaded, launch the interactive Shiny dashboard from R or RStudio:    

```r
shiny::runApp("shinyApp.R")
```

