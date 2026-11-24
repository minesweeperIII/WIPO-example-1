# World Intellectual Property Indicators (WIPI) 2026 — Choropleth Map with R

An automated data pipeline that scrapes statistical datasets from the **World Intellectual Property Organization (WIPO)** and renders interactive global choropleth maps.

**Data Source:** [WIPO World Intellectual Property Indicators](https://www.wipo.int/publications/en/details.jsp?id=4886)

**Live App:** https://minesweeperiii.github.io/WIPO-example-1/         

---

## Project Structure   

```text
├── scraping.R             # Scrapes WIPO datasets, cleans tables, and bundles data into app/wipo_bundle.rds
├── app/
│   ├── app.R              # Shiny choropleth map application
│   └── wipo_bundle.rds    # Pre-processed WIPO tables and simplified Natural Earth world geometry
├── docs/                  # Exported static Shinylive/WebAssembly site 
│   ├── index.html
|   ├── app.json
|   ├── shinylive-sw.js
│   ├── shinylive/
│   └── .nojekyll          # Only important for GitHub Pages hosting
├── downloads/             # Raw scraped WIPO Excel/ZIP files (gitignored)
├── .gitignore
└── README.md
```

## Getting Started

### Prerequisites

- **R** (`>= 4.1.0`)
- An active internet connection when running scraping.R to fetch datasets from WIPO.

### Installation

**Install required R packages:**
   
   ```r
   install.packages(c(
   "rvest", "httr2", "stringr", "tibble", "dplyr",
   "readxl", "tidyr", "purrr", "sf", "rnaturalearth",
   "shiny", "ggplot2", "shinylive", "httpuv"
   ))
   ```

### Usage    

Run the following from the project root directory in R:   

#### 1. Scraping data, clean, and generate app/wipo_bundle.rds to prepare for Shiny             

```r   
source("scraping.R")
```
#### 2. Locally launch Shiny app 

```r
shiny::runApp("app")
```
### Optional 
#### After Step 1, export the Shiny app to docs/ as static WebAssembly files      

```r
shinylive::export(appdir = "app", destdir = "docs")
```
#### Preview static interactive Shiny app locally

The loading is slow at the beginning (same as the Live App). 

```r
httpuv::runStaticServer("docs")
```


