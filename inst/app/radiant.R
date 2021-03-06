################################################################################
## function to save app state on refresh or crash
################################################################################

## drop NULLs in list
toList <- function(x) reactiveValuesToList(x) %>% .[!sapply(., is.null)]

saveSession <- function(session = session) {
  if (!exists("r_sessions")) return()
  if (exists("r_state") && !is_empty(r_state)) {
    rs <- r_state
    rs_input <- toList(input)
    rs[names(rs_input)] <- rs_input
  } else {
    rs <- toList(input)
  }

  r_sessions[[r_ssuid]] <- list(
    r_data    = toList(r_data),
    r_state = rs,
    timestamp = Sys.time()
  )

  ## saving session information to file
  fn <- paste0(normalizePath("~/radiant.sessions"),"/r_", r_ssuid, ".rds")
  saveRDS(r_sessions[[r_ssuid]], file = fn)
}

observeEvent(input$refresh_radiant, {
  if (isTRUE(getOption("radiant.local"))) {
    fn <- normalizePath("~/radiant.sessions")
    file.remove(list.files(fn, full.names = TRUE))
  } else {
    fn <- paste0(normalizePath("~/radiant.sessions"),"/r_", r_ssuid, ".rds")
    if (file.exists(fn)) unlink(fn, force = TRUE)
  }

  try(r_ssuid <- NULL, silent = TRUE)
})

saveStateOnRefresh <- function(session = session) {
  session$onSessionEnded(function() {
    isolate({
      url_query <- parseQueryString(session$clientData$url_search)
      if (not_pressed(input$refresh_radiant) && not_pressed(input$stop_radiant) &&
          is.null(input$uploadState) && !"fixed" %in% names(url_query)) {
        saveSession(session)
      } else {
        if (is.null(input$uploadState)) {
          if (exists("r_sessions")) {
            sshhr(try(r_sessions[[r_ssuid]] <- NULL, silent = TRUE))
            sshhr(try(rm(r_ssuid), silent = TRUE))
          }
        }
      }
    })
  })
}

################################################################
## functions used across tools in radiant
################################################################

## get active dataset and apply data-filter if available
.getdata <- reactive({
  req(input$dataset)
  selcom <- input$data_filter %>% gsub("\\n","", .) %>% gsub("\"","\'",.)
  if (is_empty(selcom) || input$show_filter == FALSE) {
    isolate(r_data$filter_error <- "")
  } else if (grepl("([^=!<>])=([^=])",selcom)) {
    isolate(r_data$filter_error <- "Invalid filter: never use = in a filter but == (e.g., year == 2014). Update or remove the expression")
  } else {
    seldat <- try(filter_(r_data[[input$dataset]], selcom), silent = TRUE)
    if (is(seldat, 'try-error')) {
      isolate(r_data$filter_error <- paste0("Invalid filter: \"", attr(seldat,"condition")$message,"\". Update or remove the expression"))
    } else {
      isolate(r_data$filter_error <- "")
      if ("grouped_df" %in% class(seldat)) {
        return(droplevels(ungroup(seldat)))
      } else {
        return(droplevels(seldat))
      }
    }
  }

  if ("grouped_df" %in% class(r_data[[input$dataset]])) {
    ungroup(r_data[[input$dataset]])
  } else {
    r_data[[input$dataset]]
  }
})

## same as .getdata but without filters etc.
# .getdata_transform <- reactive({
#   if (is.null(input$dataset)) return()
#   if ("grouped_df" %in% class(r_data[[input$dataset]])) {
#     ungroup(r_data[[input$dataset]])
#   } else {
#     r_data[[input$dataset]]
#   }
# })

## using a regular function to avoid a full data copy
.getdata_transform <- function(dataset = input$dataset) {
  if (is.null(dataset)) return()
  if ("grouped_df" %in% class(r_data[[dataset]])) {
    ungroup(r_data[[dataset]])
  } else {
    r_data[[dataset]]
  }
}

.getclass <- reactive({
  getclass(.getdata())
})

groupable_vars <- reactive({
  .getdata() %>%
    summarise_each(funs(is.factor(.) || is.logical(.) || lubridate::is.Date(.) || is.integer(.) ||
                        ((n_distinct(., na.rm = TRUE)/n()) < .30))) %>%
    {which(. == TRUE)} %>%
    varnames()[.]
})

groupable_vars_nonum <- reactive({
  .getdata() %>%
    summarise_each(funs(is.factor(.) || is.logical(.) || lubridate::is.Date(.) || is.integer(.) ||
                   is.character(.))) %>%
    {which(. == TRUE)} %>%
    varnames()[.]
})


## used in compare proportions
two_level_vars <- reactive({
  .getdata() %>%
    summarise_each(funs(n_distinct(., na.rm = TRUE))) %>%
    { . == 2 } %>%
    which(.) %>%
    varnames()[.]
})

## used in visualize - don't plot Y-variables that don't vary
varying_vars <- reactive({
  .getdata() %>%
    summarise_each(funs(does_vary(.))) %>%
    as.logical %>%
    which %>%
    varnames()[.]
})

## getting variable names in active dataset and their class
varnames <- reactive({
  .getclass() %>% names %>%
    set_names(., paste0(., " {", .getclass(), "}"))
})

## cleaning up the arguments for data_filter and defaults passed to report
clean_args <- function(rep_args, rep_default = list()) {
  if (!is.null(rep_args$data_filter)) {
    if (rep_args$data_filter == "")
      rep_args$data_filter  <- NULL
    else
      rep_args$data_filter %<>% gsub("\\n","", .) %>% gsub("\"","\'",.)
  }

  if (length(rep_default) == 0) rep_default[names(rep_args)] <- ""

  ## removing default arguments before sending to report feature
  for (i in names(rep_args)) {
    if (!is.language(rep_args[[i]]) && !is.call(rep_args[[i]]) && all(is.na(rep_args[[i]]))) {
      rep_args[[i]] <- NULL; next
    }
    if (!is.symbol(rep_default[[i]]) && !is.call(rep_default[[i]]) && all(is_not(rep_default[[i]]))) next
    if (length(rep_args[[i]]) == length(rep_default[[i]]) && all(rep_args[[i]] == rep_default[[i]]))
      rep_args[[i]] <- NULL
  }

  rep_args
}

## check if a variable is null or not in the selected data.frame
not_available <- function(x)
  if (any(is.null(x)) || (sum(x %in% varnames()) < length(x))) TRUE else FALSE

## check if a variable is null or not in the selected data.frame
available <- function(x) not_available(x) == FALSE

## check if a button was NOT pressed
not_pressed <- function(x) if (is.null(x) || x == 0) TRUE else FALSE

pressed <- function(x) if (!is.null(x) && x > 0) TRUE else FALSE

## check for duplicate entries
has_duplicates <- function(x)
  if (length(unique(x)) < length(x)) TRUE else FALSE

## is x some type of date variable
is_date <- function(x) inherits(x, c("Date", "POSIXlt", "POSIXct"))

## drop elements from .._args variables obtained using formals
r_drop <- function(x, drop = c("dataset","data_filter")) x[-which(x %in% drop)]

## convert a date variable to character for printing
d2c <- function(x) if (is_date(x)) as.character(x) else x

## truncate character fields for show_data_snippet
trunc_char <- function(x) if (is.character(x)) strtrim(x,40) else x

## show a few rows of a dataframe
show_data_snippet <- function(dat = input$dataset, nshow = 7, title = "", filt = "") {

  if (is.character(dat) && length(dat) == 1) dat <- getdata(dat, filt = filt, na.rm = FALSE)
  nr <- nrow(dat)
  ## avoid slice with variables outside of the df in case a column with the same
  ## name exists
  dat <- dat[1:min(nshow, nr),, drop = FALSE]
  dat %>%
    mutate_each(funs(trunc_char)) %>%
    mutate_each(funs(d2c)) %>%
    xtable::xtable(.) %>%
    print(type = 'html',  print.results = FALSE, include.rownames = FALSE,
          sanitize.text.function = identity,
          html.table.attributes = "class='table table-condensed table-hover'") %>%
    paste0(title, .) %>%
    {if (nr <= nshow) . else paste0(.,'\n<label>', nshow,' of ', formatnr(nr,dec = 0), ' rows shown. See View-tab for details.</label>')} %>%
    enc2utf8
}

suggest_data <- function(text = "", dat = "diamonds")
  paste0(text, "For an example dataset go to Data > Manage, select 'examples' from the\n'Load data of type' dropdown, and press the 'Load examples' button. Then\nselect the \'", dat, "\' dataset.")

## function written by @wch https://github.com/rstudio/shiny/issues/781#issuecomment-87135411
capture_plot <- function(expr, env = parent.frame()) {
  structure(
    list(expr = substitute(expr), env = env),
    class = "capture_plot"
  )
}

## function written by @wch https://github.com/rstudio/shiny/issues/781#issuecomment-87135411
print.capture_plot <- function(x, ...) {
  eval(x$expr, x$env)
}

################################################################
## functions used to create Shiny in and outputs
################################################################

## textarea where the return key submits the content
returnTextAreaInput <- function(inputId, label = NULL, value = "") {
  tagList(
    tags$label(label, `for` = inputId),br(),
    tags$textarea(value, id=inputId, type = "text", rows="2",
                  class="returnTextArea form-control")
  )
}

returnTextInput <- function(inputId, label = NULL, value = "") {
  tagList(
    tags$label(label, `for` = inputId),
    tags$input(id = inputId, type = "text", value = value,
               class = "returnTextInput form-control")
  )
}

plot_width <- function()
  if (is.null(input$viz_plot_width)) r_data$plot_width else input$viz_plot_width

plot_height <- function()
  if (is.null(input$viz_plot_height)) r_data$plot_height else input$viz_plot_height

## fun_name is a string of the main function name
## rfun_name is a string of the reactive wrapper that calls the main function
## out_name is the name of the output, set to fun_name by default
register_print_output <- function(fun_name, rfun_name,
                                  out_name = fun_name) {

  ## Generate output for the summary tab
  output[[out_name]] <- renderPrint({
    ## when no analysis was conducted (e.g., no variables selected)
    get(rfun_name)() %>%
      {if (is.character(.)) cat(.,"\n") else .} %>%
      rm(.)
  })
  return(invisible())
}

# fun_name is a string of the main function name
# rfun_name is a string of the reactive wrapper that calls the main function
# out_name is the name of the output, set to fun_name by default
register_plot_output <- function(fun_name, rfun_name,
                                 out_name = fun_name,
                                 width_fun = "plot_width",
                                 height_fun = "plot_height") {

  ## Generate output for the plots tab
  output[[out_name]] <- renderPlot({

    ## when no analysis was conducted (e.g., no variables selected)
    get(rfun_name)() %>% { if (is.null(.)) " " else . } %>%
    { if (is.character(.)) {
        plot(x = 1, type = 'n', main = paste0("\n\n\n\n\n\n\n\n",.) ,
             axes = FALSE, xlab = "", ylab = "")
      } else {
        withProgress(message = 'Making plot', value = 1, print(.))
      }
    }
  }, width=get(width_fun), height=get(height_fun))

  return(invisible())
}

plot_downloader <- function(plot_name, width = plot_width(),
                            height = plot_height(), pre = ".plot_", po = "dl_") {

  ## link and output name
  lnm <- paste0(po, plot_name)

  ## create an output
  output[[lnm]] <- downloadHandler(
    filename = function() { paste0(plot_name, ".png") },
    content = function(file) {

        ## download graphs in higher resolution than shown in GUI (504 dpi)
        pr <- 7
        png(file=file, width = width*pr, height = height*pr, res=72*pr)
          print(get(paste0(pre, plot_name))())
        dev.off()
    }
  )
  downloadLink(lnm, "", class = "fa fa-download alignright")
}

stat_tab_panel <- function(menu, tool, tool_ui, output_panels,
                           data = input$dataset) {
  sidebarLayout(
    sidebarPanel(
      wellPanel(
        HTML(paste("<label><strong>Menu:", menu, "</strong></label><br>")),
        HTML(paste("<label><strong>Tool:", tool, "</strong></label><br>")),
        if (!is.null(data))
          HTML(paste("<label><strong>Data:", data, "</strong></label>"))
      ),
      uiOutput(tool_ui)
    ),
    mainPanel(
      output_panels
    )
  )
}

################################################################
## functions used for app help
################################################################
help_modal <- function(modal_title, link, help_file,
                       author = "Vincent Nijs",
                       year = lubridate::year(lubridate::now())) {
  sprintf("<div class='modal fade' id='%s' tabindex='-1' role='dialog' aria-labelledby='%s_label' aria-hidden='true'>
            <div class='modal-dialog'>
              <div class='modal-content'>
                <div class='modal-header'>
                  <button type='button' class='close' data-dismiss='modal' aria-label='Close'><span aria-hidden='true'>&times;</span></button>
                  <h4 class='modal-title' id='%s_label'>%s</h4>
                  </div>
                <div class='modal-body'>%s<br>
                  &copy; %s (%s) <a rel='license' href='http://creativecommons.org/licenses/by-nc-sa/4.0/' target='_blank'><img alt='Creative Commons License' style='border-width:0' src ='imgs/80x15.png' /></a>
                </div>
              </div>
            </div>
           </div>
           <i title='Help' class='fa fa-question' data-toggle='modal' data-target='#%s'></i>",
           link, link, link, modal_title, help_file, author, year, link) %>%
  enc2utf8 %>% HTML
}

help_and_report <- function(modal_title, fun_name, help_file,
                            author = "Vincent Nijs",
                            year = lubridate::year(lubridate::now())) {
  sprintf("<div class='modal fade' id='%s_help' tabindex='-1' role='dialog' aria-labelledby='%s_help_label' aria-hidden='true'>
            <div class='modal-dialog'>
              <div class='modal-content'>
                <div class='modal-header'>
                  <button type='button' class='close' data-dismiss='modal' aria-label='Close'><span aria-hidden='true'>&times;</span></button>
                  <h4 class='modal-title' id='%s_help_label'>%s</h4>
                  </div>
                <div class='modal-body'>%s<br>
                  &copy; %s (%s) <a rel='license' href='http://creativecommons.org/licenses/by-nc-sa/4.0/' target='_blank'><img alt='Creative Commons License' style='border-width:0' src ='imgs/80x15.png' /></a>
                </div>
              </div>
            </div>
           </div>
           <i title='Help' class='fa fa-question alignleft' data-toggle='modal' data-target='#%s_help'></i>
           <i title='Report results' class='fa fa-edit action-button shiny-bound-input alignright' href='#%s_report' id='%s_report'></i>
           <div style='clear: both;'></div>",
          fun_name, fun_name, fun_name, modal_title, help_file, author, year, fun_name, fun_name, fun_name) %>%
  enc2utf8 %>% HTML %>% withMathJax
}

## function to render .md files to html
inclMD <- function(path) {
  markdown::markdownToHTML(path, fragment.only = TRUE, options = "",
                           stylesheet = "")
}

# inclRmd <- function(path, r_environment = parent.frame()) {
inclRmd <- function(path) {
  paste(readLines(path, warn = FALSE), collapse = '\n') %>%
  knitr::knit2html(text = ., fragment.only = TRUE, quiet = TRUE,
    envir = r_environment, options = "", stylesheet = "") %>%
    HTML %>% withMathJax
}

## capture the state of a dt table
dt_state <- function(fun, vars = "", tabfilt = "", tabsort = "", nr = 0) {

  ## global search
  search <- input[[paste0(fun, "_state")]]$search$search
  if (is.null(search)) search <- ""

  ## table ordering
  order <- input[[paste0(fun,"_state")]]$order
  if (length(order) == 0) {
    order <- "NULL"
  } else {
    order <- list(order)
  }

  ## column filters, gsub needed for factors
  sc <- input[[paste0(fun, "_search_columns")]] %>% gsub("\\\"","'",.)
  sci <- which(sc != "")
  nr_sc <- length(sci)
  if (nr_sc > 0) {
    sc <- list(lapply(sci, function(i) list(i, sc[i])))
  } else if (nr_sc == 0) {
    sc <-  "NULL"
  }

  dat <- get(paste0(".",fun))()$tab %>% {nr <<- nrow(.); .[1,,drop = FALSE]}

  if (order != "NULL" || sc != "NULL") {

    ## get variable class and name
    # gc <- get(paste0(".",fun))()$tab %>% {nr <<- nrow(.); .} %>% getclass %>%
    gc <- getclass(dat) %>% {if (is_empty(vars[1])) . else .[vars]}
    cn <- names(gc)

    if (length(cn) > 0) {
      if (order != "NULL") {
        tabsort <- c()
        for (i in order[[1]]) {
          cname <- cn[i[[1]] + 1]
          if (i[[2]] == "desc") cname <- paste0("desc(", cname, ")")
          tabsort <- c(tabsort, cname)
        }
        tabsort <- paste0(tabsort, collapse = ", ")
      }

      if (sc != "NULL") {
        tabfilt <- c()
        for (i in sc[[1]]) {
          cname <- cn[i[[1]]]
          type <- gc[cname]
          if (type == "factor") {
            cname <- paste0(cname, " %in% ", sub("\\[","c(", i[[2]]) %>% sub("\\]",")", .))
          } else if (type %in% c("numeric","integer")) {
            bnd <- strsplit(i[[2]], "...", fixed = TRUE)[[1]]
            cname <- paste0(cname, " >= ", bnd[1], " & ", cname, " <= ", bnd[2]) %>% gsub("  ", " ", .)
          } else if (type %in% c("date","period")) {
            bnd <- strsplit(i[[2]], "...", fixed = TRUE)[[1]] %>% gsub(" ", "", .)
            cname <- paste0(cname, " >= '", bnd[1], "' & ", cname, " <= '", bnd[2], "'") %>% gsub("  ", " ", .)
          } else if (type == "character") {
            cname <- paste0("grepl('", i[[2]], "', ", cname, ", fixed = TRUE)")
          } else {
            message("Variable ", cname, " has type ", type, ". This type is not currently supported to generate code for R > Report")
            next
          }
          tabfilt <- c(tabfilt, cname)
        }
        tabfilt <- paste0(tabfilt, collapse = " & ")
      }
    }
  }

  # tabslice <- if (ts < 2) "1" else paste0("1:",ts)

  list(search = search, order = order, sc = sc, tabsort = tabsort, tabfilt = tabfilt, nr = nr)
}

## used by View - remove or use more broadly
find_env <- function(dataset) {
  if (exists("r_environment")) {
    r_environment
  } else if (exists("r_data") && !is.null(r_data[[dataset]])) {
    pryr::where("r_data")
  } else if (exists(dataset)) {
    pryr::where(dataset)
  }
}

## used by View - remove or use more broadly
save2env <- function(dat, dataset,
                     dat_name = dataset,
                     mess = "") {

  env <- find_env(dataset)
  env$r_data[[dat_name]] <- dat
  if (dataset != dat_name) {
    message(paste0("Dataset r_data$", dat_name, " created in ", environmentName(env), " environment\n"))
    env$r_data[['datasetlist']] <- c(dat_name, env$r_data[['datasetlist']]) %>% unique
  } else {
    message(paste0("Dataset r_data$", dataset, " changed in ", environmentName(env), " environment\n"))
  }

  ## set to previous description
  env$r_data[[paste0(dat_name,"_descr")]] <- env$r_data[[paste0(dataset,"_descr")]]

  if (mess != "")
    env$r_data[[paste0(dat_name,"_descr")]] %<>% paste0("\n\n",mess)
}

## use the value in the input list if available and update r_state
state_init <- function(var, init = "") {
  isolate({
    ivar <- input[[var]]
    if (var %in% names(input) || length(ivar) > 0) {
      ivar <- input[[var]]
      if (is_empty(ivar)) r_state[[var]] <<- NULL
    } else {
      ivar <- .state_init(var, init)
    }
    ivar
  })
}

## need a separate function for checkboxGroupInputs
state_group <- function(var, init = "") {
  isolate({
    ivar <- input[[var]]
    if (var %in% names(input) || length(ivar) > 0) {
      ivar <- input[[var]]
      if (is_empty(ivar)) r_state[[var]] <<- NULL
    } else {
      ivar <- .state_init(var, init)
      r_state[[var]] <<- NULL ## line that differs for CBG inputs
    }
    ivar
  })
}

.state_init <- function(var, init = "") {
  rs <- r_state[[var]]
  if (is_empty(rs)) init else rs
}

state_single <- function(var, vals, init = character(0)) {
  isolate({
    ivar <- input[[var]]
    if (var %in% names(input) && is.null(ivar)) {
      r_state[[var]] <<- NULL
      ivar
    } else if (available(ivar) && all(ivar %in% vals)) {
      if (length(ivar) > 0) r_state[[var]] <<- ivar
      ivar
    } else if (available(ivar) && any(ivar %in% vals)) {
       ivar[ivar %in% vals]
    } else {
      if (length(ivar) > 0 && all(ivar %in% c("None","none",".","")))
        r_state[[var]] <<- ivar
      .state_single(var, vals, init = init)
    }
    # .state_single(var, vals, init = init)
  })
}

.state_single <- function(var, vals, init = character(0)) {
  rs <- r_state[[var]]
  if (is_empty(rs)) init else vals[vals == rs]
}

state_multiple <- function(var, vals, init = character(0)) {
  isolate({
    ivar <- input[[var]]
    if (var %in% names(input) && is.null(ivar)) {
      r_state[[var]] <<- NULL
      ivar
    } else if (available(ivar) && all(ivar %in% vals)) {
      if (length(ivar) > 0) r_state[[var]] <<- ivar
      ivar
    } else if (available(ivar) && any(ivar %in% vals)) {
      ivar[ivar %in% vals]
    } else {
      if (length(ivar) > 0 && all(ivar %in% c("None","none",".","")))
        r_state[[var]] <<- ivar
      .state_multiple(var, vals, init = init)
    }
  })
}

.state_multiple <- function(var, vals, init = character(0)) {
  rs <- r_state[[var]]
  ## "a" %in% character(0) --> FALSE, letters[FALSE] --> character(0)
  if (is_empty(rs)) vals[vals %in% init] else vals[vals %in% rs]
}

## cat to file
## use with tail -f ~/r_cat.txt in a terminal
cf <- function(...) {
  cat(paste0("\n--- called from: ", environmentName(parent.frame()), " (", lubridate::now(), ")\n"), file = "~/r_cat.txt", append = TRUE)
  out <- paste0(capture.output(...), collapse = "\n")
  cat("--\n", out, "\n--", sep = "\n", file = "~/r_cat.txt", append = TRUE)
}
