# ==============================================================================
# 1. Load necessary packages
# ==============================================================================
library(rvest)
library(httr2)
library(stringr)
library(tibble)
library(dplyr)
library(readxl)
library(tidyr)
library(purrr)
library(sf)
library(rnaturalearth)

# ==============================================================================
# 2. Scraping WIPO website functions
# ==============================================================================
extract_wipo_links <- function(url, x_path) {
  page <- read_html(url)
  link_nodes <- page %>%
    html_elements(xpath = x_path)

  tibble(
    # Extract strictly the HTML text/nodes inside <li> that appear BEFORE the first <a> tag
    label = vapply(link_nodes, function(node) {
      node %>%
        html_elements(xpath = ".//a[1]/preceding-sibling::node()") %>%
        html_text() %>%
        paste(collapse = " ") %>%
        str_squish()
    }, character(1)),
    href = link_nodes %>%
      html_element("a") %>%
      html_attr("href") %>%
      url_absolute(base = url)
  ) %>%
    filter(str_detect(href, regex("\\.(zip|xlsx?)(\\?.*)?$", ignore_case = TRUE))) %>%
    distinct(href, .keep_all = TRUE)
}

get_wipo_file <- function(url, x_path, output_dir = "downloads") {
  files_info_df <- extract_wipo_links(url, x_path)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  }

  for (i in seq_len(nrow(files_info_df))) {
    file_url  <- files_info_df$href[i]
    file_name <- files_info_df$label[i]

    clean_url <- sub("\\?.*$", "", file_url)
    url_ext   <- tolower(tools::file_ext(basename(clean_url)))

    temp_file <- tempfile(fileext = ifelse(url_ext != "", paste0(".", url_ext), ""))
    request(file_url) %>%
      req_user_agent("Mozilla/5.0 (R scraper)") %>%
      req_perform(path = temp_file)

    if (url_ext == "zip") {
      temp_unzip <- tempfile()
      extracted  <- unzip(temp_file, exdir = temp_unzip)

      for (j in seq_along(extracted)) {
        f <- extracted[j]
        final_path <- file.path(output_dir, paste0(file_name, " ", j, " ", basename(f)))
        file.copy(f, final_path, overwrite = TRUE)
      }
    } else {
      final_path <- file.path(output_dir, paste0(file_name, " ", basename(clean_url)))
      file.copy(temp_file, final_path, overwrite = TRUE)
    }
  }
}

# ==============================================================================
# 3. Download files
# ==============================================================================
url <- "https://www.wipo.int/publications/en/details.jsp?id=4886"
x_path <- '//*[@id="tech"]/following-sibling::*//li[.//a]'
output_dir <- "downloads"

get_wipo_file(url, x_path, output_dir = output_dir)

# ==============================================================================
# 4. Filter & clean Excel tables for Choropleth maps
# ==============================================================================
extract_origin_tabs <- function(file_paths) {
  results <- list()

  for (path in file_paths) {
    # Skip the first sheet ('toc')
    tab_names <- excel_sheets(path)[-1]
    for (tab in tab_names) {
      raw_sheet <- suppressMessages(
        read_excel(path, sheet = tab, col_names = FALSE, .name_repair = "unique")
      )

      content_name <- trimws(as.character(raw_sheet[[1, 1]]))
      has_office_title <- !is.na(content_name) &&
        str_detect(content_name, regex("\\boffices?\\b", ignore_case = TRUE))
      if (has_office_title) next

      is_empty <- raw_sheet %>%
        mutate(across(everything(), ~ is.na(.x) | trimws(as.character(.x)) == "")) %>%
        reduce(`&`)
      last_blank <- ifelse(any(is_empty), max(which(is_empty)), NA_integer_)
      skip_rows  <- ifelse(!is.na(last_blank), last_blank, 2)

      table_header <- suppressMessages(
        read_excel(path, sheet = tab, skip = skip_rows, n_max = 0, .name_repair = "unique")
      )
      first_col <- trimws(names(table_header)[1])
      keep <- !is.na(first_col) && str_detect(first_col, regex("^(origins?|countr(y|ies))$", ignore_case = TRUE))

      if (keep) {
        results[[length(results) + 1]] <- tibble(
          file_path = path,
          tab_name = tab,
          content_name = content_name
        )
      }
    }
  }

  bind_rows(results)
}

read_clean_table <- function(path, sheet) {
  raw_sheet <- suppressMessages(
    read_excel(path, sheet = sheet, col_names = FALSE, .name_repair = "unique")
  )

  is_empty <- raw_sheet %>%
    mutate(across(everything(), ~ is.na(.x) | trimws(as.character(.x)) == "")) %>%
    reduce(`&`)

  first_blank <- which(is_empty)[1]
  table_title <- trimws(as.character(raw_sheet[[1]][1]))

  if (!is.na(first_blank) && first_blank > 2) {
    note_lines <- trimws(as.character(raw_sheet[[1]][2:(first_blank - 1)]))
    note_lines <- note_lines[!is.na(note_lines) & note_lines != ""]
    table_note <- paste(note_lines, collapse = "\n")
    skip_rows  <- first_blank
  } else {
    table_note <- NA_character_
    skip_rows  <- if (!is.na(first_blank)) first_blank else 1
  }

  remaining_rows <- seq(skip_rows + 1, nrow(raw_sheet))
  remaining_rows <- remaining_rows[!is_empty[remaining_rows]]
  block_groups   <- split(remaining_rows, cumsum(is_empty)[remaining_rows])

  valid_tables <- list()

  for (rows_idx in block_groups) {
    if (length(rows_idx) < 2) next

    start_row <- min(rows_idx)
    end_row   <- max(rows_idx)

    sub_tbl <- suppressMessages(
      read_excel(
        path = path,
        sheet = sheet,
        skip = start_row - 1,
        n_max = end_row - start_row,
        na = c("", "...", "..", "-", "n/a", "N/A"),
        .name_repair = "unique"
      )
    ) %>%
      select(where(~ !all(is.na(.x) | trimws(as.character(.x)) == "")))

    if (ncol(sub_tbl) < 2) next

    key_col <- names(sub_tbl)[1]
    sub_tbl <- sub_tbl %>%
      mutate(across(all_of(key_col), ~ trimws(as.character(.x)))) %>%
      filter(!is.na(.data[[key_col]]), .data[[key_col]] != "")

    valid_tables[[length(valid_tables) + 1]] <- sub_tbl
  }

  if (length(valid_tables) == 0) {
    return(list(
      table_title = table_title,
      table_note = table_note,
      table_data = tibble()
    ))
  }

  combined_data <- reduce(valid_tables, function(x, y) {
    full_join(x, y, by = setNames(names(y)[1], names(x)[1]))
  })

  list(
    table_title = table_title,
    table_note = table_note,
    table_data = combined_data
  )
}

clean_country_name <- function(x) {
  x_clean <- trimws(as.character(x))
  unname(recode(
    x_clean,
    "USA" = "United States of America",
    "United States" = "United States of America",
    "US" = "United States of America",
    "U.S." = "United States of America",
    "UK" = "United Kingdom",
    "Great Britain" = "United Kingdom",
    "Russia" = "Russian Federation",
    "South Korea" = "Republic of Korea",
    "Korea, Republic of" = "Republic of Korea",
    "North Korea" = "Dem. Rep. Korea",
    "Vietnam" = "Viet Nam",
    "Iran" = "Iran (Islamic Republic of)",
    "Syria" = "Syrian Arab Republic",
    "Venezuela" = "Venezuela (Bolivarian Republic of)",
    "Bolivia" = "Bolivia (Plurinational State of)",
    "Tanzania" = "United Republic of Tanzania",
    "Czech Republic" = "Czechia",
    "Ivory Coast" = "Côte d'Ivoire",
    "DR Congo" = "Democratic Republic of the Congo",
    "Congo, Dem. Rep." = "Democratic Republic of the Congo",
    "Congo" = "Republic of the Congo",
    "Turkiye" = "Turkey",
    "Türkiye" = "Turkey",
    .default = x_clean
  ))
}

# ==============================================================================
# 5. Pre-compute all tables & lightweight world map for Shinylive
# ==============================================================================
files <- list.files(path = output_dir, full.names = TRUE)

master_origin_tabs <- extract_origin_tabs(files) %>%
  distinct(content_name, .keep_all = TRUE) %>%
  filter(!is.na(content_name))

precomputed_tables <- setNames(
  lapply(seq_len(nrow(master_origin_tabs)), function(i) {
    row <- master_origin_tabs[i, ]
    res <- read_clean_table(row$file_path, row$tab_name)
    df  <- res$table_data

    if (ncol(df) >= 2) {
      key_col <- names(df)[1]
      df <- df %>%
        filter(!str_detect(.data[[key_col]], regex("^total", ignore_case = TRUE))) %>%
        mutate(.country_match = clean_country_name(.data[[key_col]]))
    }
    res$table_data <- df
    res
  }),
  master_origin_tabs$content_name
)

world_sf <- ne_countries(scale = "small", returnclass = "sf") %>%
  filter(!is.na(name), iso_a3 != "ATA") %>%
  distinct(name, .keep_all = TRUE) %>%
  select(name, geometry)

dir.create("app", showWarnings = FALSE)
saveRDS(
  list(tables = precomputed_tables, world_sf = world_sf),
  file = "app/wipo_bundle.rds",
  compress = "xz"
)