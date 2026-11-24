# ==============================================================================
# 1. Load necessary packages & WebR options
# ==============================================================================
options(shiny.useragg = TRUE)
options(shiny.sanitize.errors = FALSE)

library(shiny)
library(dplyr)
library(tidyr)
library(stringr)
library(tibble)
library(ggplot2)
library(sf)
library(scales)

# ==============================================================================
# 2. Load pre-processed tables & world map
# ==============================================================================
bundle <- readRDS("app/wipo_bundle.rds")
precomputed_tables <- bundle$tables
world_sf <- bundle$world_sf

# Strip PROJ/CRS metadata so WebR does not fail on GDAL/PROJ database lookups
sf::st_crs(world_sf) <- NA

# ==============================================================================
# 3. Shiny UI
# ==============================================================================
ui <- fluidPage(
  titlePanel("World Intellectual Property Indicators 2026"),
  
  sidebarLayout(
    sidebarPanel(
      width = 3,
      selectInput(
        inputId = "selected_content",
        label = "1. Select Table Name:",
        choices = names(precomputed_tables),
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
# 4. Shiny Server
# ==============================================================================
server <- function(input, output, session) {
  
  parsed_tab <- reactive({
    req(input$selected_content)
    precomputed_tables[[input$selected_content]]
  })
  
  table_structure <- reactive({
    res <- parsed_tab()
    df <- res$table_data
    req(!is.null(df), ncol(df) >= 2, nrow(df) >= 1)
    
    other_cols <- setdiff(names(df)[-1], ".country_match")
    
    char_cols <- other_cols[vapply(df[other_cols], function(col) {
      is.character(col) || is.factor(col)
    }, logical(1))]
    
    facet_col <- if (length(char_cols) >= 1) char_cols[1] else NULL
    metric_cols <- setdiff(other_cols, char_cols)
    
    list(
      df = df,
      facet_col = facet_col,
      metric_cols = metric_cols
    )
  })
  
  output$display_title <- renderText({
    parsed_tab()$table_title
  })
  
  output$display_note <- renderText({
    note <- parsed_tab()$table_note
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
    
    df_mapped <- st$df
    facet_col <- st$facet_col
    
    lapply(seq_along(cols), function(i) {
      col_name <- cols[i]
      plotname <- paste0("world_map_", i)
      
      output[[plotname]] <- renderPlot({
        # Guard against transient mismatches while switching tables
        req(col_name %in% names(df_mapped))
        if (!is.null(facet_col)) {
          req(facet_col %in% names(df_mapped))
        }
        
        if (!is.null(facet_col)) {
          facet_levels <- unique(na.omit(trimws(as.character(df_mapped[[facet_col]]))))
          req(length(facet_levels) >= 1)
          
          base_grid <- tidyr::crossing(
            tibble(name = world_sf$name),
            tibble(!!facet_col := facet_levels)
          ) %>%
            left_join(world_sf, by = "name")
          
          plot_df <- df_mapped %>%
            transmute(
              .country_match,
              !!facet_col := trimws(as.character(.data[[facet_col]])),
              val = suppressWarnings(as.numeric(str_replace_all(as.character(.data[[col_name]]), ",", "")))
            ) %>%
            filter(!is.na(.data[[facet_col]]), .data[[facet_col]] != "")
          
          map_data <- base_grid %>%
            left_join(plot_df, by = c("name" = ".country_match", facet_col)) %>%
            st_as_sf(sf_column_name = "geometry")
          
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
            left_join(plot_df, by = c("name" = ".country_match")) %>%
            st_as_sf(sf_column_name = "geometry")
          
          p <- ggplot(map_data) +
            geom_sf(aes(fill = val), color = "white", linewidth = 0.15)
        }
        
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
            subtitle = if (has_values) res$table_title else paste0(res$table_title, " (No matching numeric country data)"),
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
      }, res = 96)
    })
  })
}

shinyApp(ui = ui, server = server)