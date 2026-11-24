# ==============================================================================
# 1. Load necessary packages (Dashboard & Map App)
# ==============================================================================
library(readxl)
library(dplyr)
library(tidyr)
library(purrr)
library(stringr)
library(tibble)
library(shiny)
library(ggplot2)
library(sf)
library(rnaturalearth)

# ==============================================================================
# 2. Filtering only tables that can be made into Choropleth map
# ==============================================================================

extract_origin_tabs <- function(file_paths) {

  results <- list()
  
  for (path in file_paths) {
    # Skip the first sheet ('toc')
    tab_names <- excel_sheets(path)[-1]    
    for (tab in tab_names) {
      # 1. Read sheet raw to get content name and find the first empty row separating Notes from the table
      raw_sheet <- read_excel(path, sheet = tab, col_names = FALSE, .name_repair = "unique")
      
      # First line is always the name of the content
      content_name <- trimws(as.character(raw_sheet[[1, 1]]))
      has_office_title <- !is.na(content_name) && 
        str_detect(content_name, regex("\\boffices?\\b", ignore_case = TRUE))
      if (has_office_title) next
      
      # Detect completely empty rows
      is_empty <- raw_sheet %>%
        mutate(across(everything(), ~ is.na(.x) | trimws(as.character(.x)) == "")) %>%
        reduce(`&`)
      last_blank <- ifelse((any(is_empty)), max(which(is_empty)), NA_integer_)
      skip_rows <- ifelse(!is.na(last_blank), last_blank, 2)
      
      # 2. Read only the header row after the blank line and check whether column 1 is named country or origin
      table_header <- read_excel(path, sheet = tab, skip = skip_rows, n_max = 0, .name_repair = "unique")
      first_col <- trimws(names(table_header)[1])
      keep <- !is.na(first_col) && str_detect(first_col, regex("^(origins?|countr(y|ies))$", ignore_case = TRUE))   
      
      # 3. Store file path, tab name, and content name if condition is met
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
output_dir = "downloads"
files <- list.files(
  path = output_dir, 
  full.names = TRUE
)
master_origin_tabs <- extract_origin_tabs(files)


# ==============================================================================
# 3. Extracting data from excel files
# ==============================================================================
read_clean_table <- function(path, sheet) {
  raw_sheet <- suppressMessages(
    read_excel(path, sheet = sheet, col_names = FALSE, .name_repair = "unique")
  )
  
  # 1. Check which rows have nothing other than NA or whitespace
  is_empty <- raw_sheet %>%
    mutate(across(everything(), ~ is.na(.x) | trimws(as.character(.x)) == "")) %>%
    reduce(`&`)
  
  first_blank <- which(is_empty)[1]
  
  # 2. Grab Row 1 directly from column 1 for the table title
  table_title <- trimws(as.character(raw_sheet[[1]][1]))
  
  # 3. Grab Notes directly from column 1 (rows 2 up to first_blank - 1)
  if (!is.na(first_blank) && first_blank > 2) {
    note_lines <- trimws(as.character(raw_sheet[[1]][2:(first_blank - 1)]))
    note_lines <- note_lines[!is.na(note_lines) & note_lines != ""]
    table_note <- paste(note_lines, collapse = "\n")
    skip_rows <- first_blank
  } else {
    table_note <- NA_character_
    skip_rows <- if (!is.na(first_blank)) first_blank else 1
  }
  
  # 4. Identify all contiguous non-empty table blocks after skip_rows
  remaining_rows <- seq(skip_rows + 1, nrow(raw_sheet))
  remaining_rows <- remaining_rows[!is_empty[remaining_rows]]
  
  # Split row indices whenever there is at least one blank row between them
  block_groups <- split(remaining_rows, cumsum(is_empty)[remaining_rows])
  
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
        .name_repair = "unique"
      )
    )
    
    sub_tbl <- sub_tbl %>%
      select(where(~ !all(is.na(.x) | trimws(as.character(.x)) == "")))
    
    if (ncol(sub_tbl) < 2) next
    
    key_col <- names(sub_tbl)[1]
    sub_tbl <- sub_tbl %>%
      mutate(across(all_of(key_col), ~ trimws(as.character(.x)))) %>%
      filter(!is.na(.data[[key_col]]), .data[[key_col]] != "")
    
    valid_tables[[length(valid_tables) + 1]] <- sub_tbl
  }
  
  if (length(valid_tables) == 0) {
    return(tibble(
      table_title = table_title,
      table_note = table_note,
      table_data = list(tibble())
    ))
  }
  
  # 5. Combine multiple tables using whatever the name of the first column is
  combined_data <- reduce(valid_tables, function(x, y) {
    full_join(x, y, by = setNames(names(y)[1], names(x)[1]))
  })
  
  return(tibble(
    table_title = table_title,
    table_note = table_note,
    table_data = list(combined_data)
  ))
}
# ==============================================================================
# 4. Load World Map & Country Name Normalizer
# ==============================================================================
world_sf <- ne_countries(scale = "medium", returnclass = "sf") %>%
  filter(!is.na(name), iso_a3 != "ATA") %>% # <-- CHANGED: Drop NA names
  distinct(name, .keep_all = TRUE)

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
# 5. Shiny UI 
# ==============================================================================
options(shiny.sanitize.errors = FALSE)

ui <- fluidPage(
  titlePanel("World Intellectual Property Indicators 2026"),
  
  sidebarLayout(
    sidebarPanel(
      width = 3,
      selectInput(
        inputId = "selected_content",
        label = "1. Select Table Name:",
        choices = {
          vals <- unique(na.omit(as.character(master_origin_tabs$content_name)))
          as.list(setNames(vals, vals))
        },
        selectize = FALSE
      ),
      hr(),
      uiOutput("column_selector_ui"),
      hr(),
      helpText("Select one or more variables to display choropleth maps.")
    ),
    
    mainPanel(
      width = 9,
      h3(textOutput("display_title")),
      div(
        style = "background-color: #f8f9fa; padding: 12px; border-left: 4px solid #007bff; margin-bottom: 20px; white-space: pre-wrap;",
        textOutput("display_note")
      ),
      uiOutput("maps_container")
    )
  )
)

# ==============================================================================
# 6. Shiny Server
# ==============================================================================
server <- function(input, output, session) {
  
  parsed_tab <- reactive({
    req(input$selected_content)
    
    row_info <- master_origin_tabs %>%
      filter(content_name == input$selected_content) %>%
      slice(1)
    
    req(nrow(row_info) == 1)
    read_clean_table(row_info$file_path, row_info$tab_name)
  })
  
  table_structure <- reactive({
    res <- parsed_tab()
    req(nrow(res) == 1)
    
    df <- res$table_data[[1]]
    req(!is.null(df), ncol(df) >= 2)
    
    key_col <- names(df)[1]
    other_cols <- names(df)[-1]
    
    char_cols <- other_cols[vapply(df[other_cols], function(col) {
      is.character(col) || is.factor(col)
    }, logical(1))]
    
    facet_col <- if (length(char_cols) >= 1) char_cols[1] else NULL
    metric_cols <- setdiff(other_cols, char_cols)
    
    list(
      df = df,
      key_col = key_col,
      facet_col = facet_col,
      metric_cols = metric_cols
    )
  })
  
  output$display_title <- renderText({
    res <- parsed_tab()
    req(nrow(res) == 1)
    res$table_title[1]
  })
  
  output$display_note <- renderText({
    res <- parsed_tab()
    req(nrow(res) == 1)
    note <- res$table_note[1]
    if (is.na(note) || note == "") "No notes available for this table." else note
  })
  
  output$column_selector_ui <- renderUI({
    st <- table_structure()
    req(length(st$metric_cols) >= 1)
    
    vals <- unique(na.omit(as.character(st$metric_cols)))
    metric_choices <- as.list(setNames(vals, vals))
    
    tagList(
      if (!is.null(st$facet_col)) {
        div(
          style = "margin-bottom: 10px; font-size: 0.9em; color: #495057;",
          strong("Faceted by: "), st$facet_col
        )
      },
      checkboxGroupInput(
        inputId = "selected_cols",
        label = "2. Select Variables to Map:",
        choices = metric_choices,
        selected = vals[1]
      )
    )
  })
  
  output$maps_container <- renderUI({
    st <- table_structure()
    req(input$selected_cols)
    
    plot_height <- if (!is.null(st$facet_col)) "650px" else "460px"
    
    plot_output_list <- lapply(seq_along(input$selected_cols), function(i) {
      plotname <- paste0("world_map_", i)
      div(
        style = "margin-bottom: 35px; border: 1px solid #e0e0e0; padding: 12px; border-radius: 6px;",
        plotOutput(outputId = plotname, height = plot_height)
      )
    })
    
    do.call(tagList, plot_output_list)
  })
  
  observe({
    res <- parsed_tab()
    st <- table_structure()
    cols <- input$selected_cols
    req(cols)
    
    df <- st$df
    key_col <- st$key_col
    facet_col <- st$facet_col
    
    df_mapped <- df %>%
      filter(!str_detect(.data[[key_col]], regex("^total", ignore_case = TRUE))) %>%
      mutate(.country_match = clean_country_name(.data[[key_col]]))
    
    lapply(seq_along(cols), function(i) {
      col_name <- cols[i]
      plotname <- paste0("world_map_", i)
      
      output[[plotname]] <- renderPlot({
        if (!is.null(facet_col)) {
          facet_levels <- unique(na.omit(trimws(as.character(df_mapped[[facet_col]]))))
          
          base_grid <- tidyr::crossing(
            tibble(name = world_sf$name),
            tibble(!!facet_col := facet_levels)
          ) %>%
            left_join(world_sf, by = "name") %>%
            st_as_sf()
          
          plot_df <- df_mapped %>%
            transmute(
              .country_match,
              !!facet_col := trimws(as.character(.data[[facet_col]])),
              val = suppressWarnings(as.numeric(str_replace_all(as.character(.data[[col_name]]), ",", "")))
            ) %>%
            filter(!is.na(.data[[facet_col]]), .data[[facet_col]] != "")
          
          map_data <- base_grid %>%
            left_join(plot_df, by = c("name" = ".country_match", facet_col))
          
          p <- ggplot(map_data) +
            geom_sf(aes(fill = val), color = "white", linewidth = 0.12) +
            facet_wrap(vars(.data[[facet_col]]))
          
        } else {
          plot_df <- df_mapped %>%
            transmute(
              .country_match,
              val = suppressWarnings(as.numeric(str_replace_all(as.character(.data[[col_name]]), ",", "")))
            )
          
          map_data <- world_sf %>%
            left_join(plot_df, by = c("name" = ".country_match"))
          
          p <- ggplot(map_data) +
            geom_sf(aes(fill = val), color = "white", linewidth = 0.15)
        }
        
        # Prevent scale_fill_viridis_c() from crashing if all matched values are NA
        has_values <- any(!is.na(map_data$val))
        
        fill_scale <- if (has_values) {
          scale_fill_viridis_c(
            option = "plasma",
            na.value = "#e9ecef",
            labels = scales::comma
          )
        } else {
          scale_fill_gradient(
            low = "#e9ecef",
            high = "#e9ecef",
            na.value = "#e9ecef",
            guide = "none"
          )
        }
        
        p +
          fill_scale +
          labs(
            title = col_name,
            subtitle = if (has_values) res$table_title[1] else paste0(res$table_title[1], " (No matching numeric country data)"),
            fill = col_name
          ) +
          theme_minimal(base_size = 13) +
          theme(
            axis.text = element_blank(),
            axis.ticks = element_blank(),
            panel.grid = element_blank(),
            plot.title = element_text(face = "bold", size = 15),
            strip.text = element_text(face = "bold", size = 12),
            legend.position = "bottom",
            legend.key.width = unit(2, "cm")
          )
      })
    })
  })
}

shinyApp(ui = ui, server = server)
