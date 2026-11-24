# ==============================================================================
# 1. Load necessary packages
# ==============================================================================
library(rvest)
library(httr2)
library(stringr)
library(tibble)
library(dplyr)

# ==============================================================================
# 2. Scraping WIPO website functions
# ==============================================================================
extract_wipo_links <- function(url,x_path) {
  page <- read_html(url)
  link_nodes <- page %>%
    html_elements(xpath = x_path)

  file_info <- tibble(
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

get_wipo_file <- function(url,x_path, output_dir = "downloads") {
  files_info_df <- (extract_wipo_links(url, x_path))
  if (!dir.exists(output_dir)){dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)}
  for (i in seq_len(nrow(files_info_df))) {
    file_url <- files_info_df$href[i]
    file_name <- files_info_df$label[i]

    clean_url <- sub("\\?.*$", "", file_url)
    url_ext   <- tolower(tools::file_ext(basename(clean_url)))

    temp_file <- tempfile(fileext = ifelse(url_ext != "", paste0(".", url_ext), ""))
    request(file_url) %>%
      req_user_agent("Mozilla/5.0 (R scraper)") %>%
      req_perform(path = temp_file)
    
    if (url_ext == "zip") {
      temp_unzip <- tempfile()
      extracted <- unzip(temp_file, exdir = temp_unzip)
        # Unzip into a temporary folder first
        temp_unzip <- tempfile()
        extracted <- unzip(temp_file, exdir = temp_unzip)
            
      for (j in (1:length(extracted))) {
          f <- extracted[j]
          final_path <- file.path(output_dir, paste0(file_name, " ", j," ",basename(f)))
          file.copy(f, final_path, overwrite = TRUE)}
      }
    else{
      final_path <- file.path(output_dir, paste0(file_name," ",basename(clean_url)))
      file.copy(temp_file, final_path, overwrite = TRUE)}
  }
}

# ==============================================================================
# 3. Download files
# ==============================================================================

url <- "https://www.wipo.int/publications/en/details.jsp?id=4886"
x_path <- '//*[@id="tech"]/following-sibling::*//li[.//a]'
files_info_df <- (extract_wipo_links(url, x_path))
output_dir = "downloads"
get_wipo_file(url,x_path)

