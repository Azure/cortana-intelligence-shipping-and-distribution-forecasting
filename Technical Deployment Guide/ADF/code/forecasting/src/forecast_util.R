#####################################################################
##############   User defined functions and global vars     #########
#####################################################################

ML_CALL_LOG <- ""

string.to.datetime <- function(dates) {
  as.POSIXct(as.numeric(as.POSIXct(dates, format = "%m/%d/%Y %I:%M:%S %p", tz = 'UTC', origin = "1970-01-01"), tz = "UTC"), tz = "UTC", origin = "1970-01-01")
}

string.to.Date <- function(dates) {
  base::as.Date(string.to.datetime(dates), format = "%Y-%m-%d") 
}

# Function defines internal parameters and adds them to the set that we read from the input ForecastParameters DB.
# 
# Input: db_params - a list of parameters read from ForecastParameters DB
#        
#
# Output: params - a list containing the full set of parameters needed for the modeling step

make_params <- function(db_params) {
  
  # Initialize parameter list
  params <- list()
  
  # Set parameters read from the DB
  
  # Unique identifier for each set of forecasts produced by the forecasting model
  if (!is.na(db_params$ForecastParametersId)) {
    params$FORECAST_ID <- as.character(db_params$ForecastParametersId)
  } else {
    stop('Parameter ForecastId not read in from DB.')
  }
  
  #  Earliest order date to include
  if (!is.na(db_params$EarliestOrderHistoryDate)) {
    params$TRAINING_FIRST_DATE <- string.to.Date(db_params$EarliestOrderHistoryDate)
  } else {
    params$TRAINING_FIRST_DATE <- base::as.Date("1900-01-01", format = "%Y-%m-%d")
    update_log_and_message("Parameter EarliestOrderHistoryDate not read in from DB. It will be set to 1900-01-01; no early data will be filtered out.")
  }
  
  #  Latest order date to include
  if (!is.na(db_params$LatestOrderHistoryDate)) {
    params$TRAINING_LAST_DATE <- string.to.Date(db_params$LatestOrderHistoryDate)
  } else {
    params$TRAINING_LAST_DATE <- base::as.Date("2900-01-01", format = "%Y-%m-%d")
    update_log_and_message("Parameter LatestOrderHistoryDate not read in from DB. It will be set to 2900-01-01; no recent data will be filtered out.")
  }
  
  if(params$TRAINING_FIRST_DATE > params$TRAINING_LAST_DATE) {
    params$TRAINING_FIRST_DATE <- base::as.Date("1900-01-01", format = "%Y-%m-%d")
    params$TRAINING_LAST_DATE <- base::as.Date("2900-01-01", format = "%Y-%m-%d")
    msg <- "EarliestOrderHistoryDate and LatestOrderHistoryDate are invalid; all data will be used for training."
    ML_CALL_LOG <- append_log(msg)
    warning(msg)
  }

  # Number of months to forecast, forecasting horizon
  if (!is.na(db_params$ForecastHorizonMonths)) {
    if(db_params$ForecastHorizonMonths > 0){
      params$HORIZON <- db_params$ForecastHorizonMonths
    } else {
      params$HORIZON <- 3
      update_log_and_message("Parameter ForecastHorizonMonths has to be a positive number. It will be set to a default value HORIZON = 3.")
    }
  } else {
    params$HORIZON <- 3
    update_log_and_message("Parameter ForecastHorizonMonths not read in from DB. It will be set to a default value HORIZON = 3.")
  }

  # Number of months history to use for computing evaluation metrics
  if (!is.na(db_params$EvaluationWindow)) {
    if(db_params$EvaluationWindow > 0){
      params$EVALUATION_WINDOW <- db_params$EvaluationWindow
    } else {
      params$EVALUATION_WINDOW <- 3
      update_log_and_message("Parameter EvaluationWindow has to be a positive number. It will be set to a default value 3.")
    }
  } else {
    params$EVALUATION_WINDOW <- 3
    update_log_and_message("Parameter EvaluationWindow not read in from DB. It will be set to a default value 3.")
  }
  
  # Parameter to indicate whether to use:
  # gts - grouped time series modeling
  # hts - hierarchical time series modeling
  if (!is.na(db_params$GTSorHTS)) {
    if (db_params$GTSorHTS %in% c("gts", "hts")){
      params$GTSorHTS <- db_params$GTSorHTS
    } else {
      params$GTSorHTS <- "gts"
      update_log_and_message("Parameter GTSorHTS needs to be set to either gts or hts. It will be set to a default mode 'gts' - grouped time series forecasting.")
    }
  } else {
    params$GTSorHTS <- "gts"
    update_log_and_message("Parameter GTSorHTS not read in from DB. It will be set to a default mode 'gts' - grouped time series forecasting.")
  }
  
  # Method to use for Hierarchical clustering:
  # bu - Bottom up
  # comb - Optimal combination 
  # tdgsa, tdgsf, tdfp - Top down approaches
  valid_combinations <- (((db_params$CombiningGTSMethod %in% c("bu", "comb")) & (params$GTSorHTS == "gts"))) | 
    (((db_params$CombiningGTSMethod %in% c("bu", "comb", "tdgsa", "tdgsf", "tdfp")) & (params$GTSorHTS == "hts")))
  
  if (!is.na(db_params$CombiningGTSMethod)) {
    if(valid_combinations){
      params$GTSMETHOD <- db_params$CombiningGTSMethod
    } else {
      params$GTSMETHOD <- "bu"
      update_log_and_message("Parameter CombiningGTSMethod not valid (for gts valid methods are: bu, comb; for hts valid methods are: bu, comb, tdgsa, tdgsf, tdfp). It will be set to a default mode 'bu' - bottom up.")
    }
  } else {
    params$GTSMETHOD <- "bu"
    update_log_and_message("Parameter CombiningGTSMethod not read in from DB. It will be set to a default mode 'bu' - bottom up.")
  }
  
  # Method to use for univariate time series forecasting for individual nodes in the tree: 
  # arima - Arima
  # ets - Exponential smoothing
  if (!is.na(db_params$UnivariateTSMethod)) {
    if(db_params$UnivariateTSMethod %in% c("arima", "ets")){
      params$TSMETHOD <- db_params$UnivariateTSMethod
    } else{
      params$TSMETHOD <- 'arima'
      update_log_and_message("Parameter UnivariateTSMethod needs to be set to either arima or ets. It will be set to a default method 'arima'.")
    }
  } else {
    params$TSMETHOD <- 'arima'
    update_log_and_message("Parameter UnivariateTSMethod not read in from DB. It will be set to a default mode 'arima'.")
  }
  
  # Weights used when GTSMETHOD = "comb"
  # c("ols", "wls", "nseries")
  if (!is.na(db_params$GTSCombWeights)) {
    if (db_params$GTSCombWeights %in% c("ols", "wls", "nseries")){
      params$COMBHTS_WEIGHTS <- db_params$GTSCombWeights
    } else {
      params$COMBHTS_WEIGHTS <- 'ols'
      update_log_and_message("Parameter GTSCombWeights needs to be set to either ols, wls, or nseris. It will be set to a default value 'ols' - ordinary least squares.")
    }
  } else {
    params$COMBHTS_WEIGHTS <- 'ols'
    update_log_and_message("Parameter GTSCombWeights not read in from DB. It will be set to a default value 'ols' - ordinary least squares.")
  }
  
  ## Set parameters not read from the DB
  
  # Time series frequency, currently only monthly
  params$FREQUENCY <- 12
  
  # Variables to do forecasting across
  params$FORECASTING_VARS <- c('CustomerName', 'ProductCategory', 'Destination')
  
  
  return(params)
  
}



# Function that processes the data pulled from the DB
# 
# Input: dataset  - dataset pulled from the DB and processed by process_dataset()
#        params   - a list of global parameters used throughout the project
#
# Output: dataset - processed dataset

process_dataset <- function(dataset, params){
  
  # 1) Convert date(s) to Date objects
  # 2) Exclude dates <TRAINING_LAST_DATE and >=TRAINING_FIRST_DATE (this also eliminates NAs)
  # 3) Omit rows with incomplete data
  
  
  dataset <- dataset %>% 
    mutate(Date = string.to.Date(Date))
  
  # Check that TRAINING_FIRST_DATE and TRAINING_LAST_DATE are within the date range in the data set
  min_date <- min(dataset$Date, na.rm = TRUE)
  max_date <- max(dataset$Date, na.rm = TRUE)
  
  if(params$TRAINING_FIRST_DATE > max_date | params$TRAINING_LAST_DATE < min_date){
    
    msg <- 'EarliestOrderHistoryDate and LatestOrderHistoryDate are outside of the range of dates in the data set. All data will be used for training.'
    params$TRAINING_FIRST_DATE <- min_date
    params$TRAINING_LAST_DATE <- max_date
    
    ML_CALL_LOG <- append_log(msg)
    warning(msg)
  }
  
  dataset <- dataset %>%
    filter(Date >= params$TRAINING_FIRST_DATE & Date <= params$TRAINING_LAST_DATE) %>%
    na.omit()
  
  return(dataset)
}


# Util functions to update a global ML_CALL_LOG variable and print out a
# message of caution

append_log <- function(msg){
  ML_CALL_LOG <<- sprintf("%s [%s] %s", ML_CALL_LOG, Sys.time(), msg, "\n")
}

update_log_and_message <- function(msg = ""){
  ML_CALL_LOG <- append_log(msg)
  message(msg)
}


# Function that computes mean absolute error (MAE)
#
# Input: forecast - a vector containing forecasted values
#        actual   - a vector containing actual values
#
# Output: e       - mean absolute error scalar

mae <- function(forecast, actual){
  
  if (length(forecast) != length(actual)) {
    return (NA);
  } else if (length(forecast) == 0 || length(actual) == 0) {
    return (NA);
  }
  else{
    e <- mean(abs(actual - forecast))
  }
  
  return(e)
}


# Function that computes root mean squared error (RMSE)
#
# Input: forecast - a vector containing forecasted values
#        actual   - a vector containing actual values
#
# Output: e       - root mean squared scalar

rmse <- function(forecast, actual){
  if (length(forecast) != length(actual)) {
    return (NA);
  } else if (length(forecast) == 0 || length(actual) == 0) {
    return (NA);
  }
  else{
    e <- sqrt(mean((actual - forecast)^2))
  }
  
  return(e)
}


# Function that computes mean percentage error (MPE)
#
# Input: forecast - a vector containing forecasted values
#        actual   - a vector containing actual values
#
# Output: e       - mean percentage error scalar

mpe <- function(forecast, actual){
  
  if (length(forecast) != length(actual)) {
    return (NA);
  } else if (length(forecast) == 0 || length(actual) == 0) {
    return (NA);
  }
  else{
    e <- 100*(actual - forecast)/actual
    e[is.nan(e)] <- 0
    e <- mean(e)  
  }
  
  return(e)
}


# Function that computes mean absolute percentage error (MAPE)
#
# Input: forecast - a vector containing forecasted values
#        actual   - a vector containing actual values
#
# Output: e       - mean absolute percentage error scalar

mape <- function(forecast, actual){
  if (length(forecast) != length(actual)) {
    return (NA);
  } else if (length(forecast) == 0 || length(actual) == 0) {
    return (NA);
  }
  else{
    e <- abs(100*(actual - forecast)/actual)
    e[is.nan(e)] <- 0
    e <- mean(e)
  }
  return(e)
}

# Compute symmetric MAPE as percentage. Two zeros make zero error. One zero makes 100% error.
#
# Input: forecast - a vector containing forecasted values
#        actual   - a vector containing actual values
#
# Output: e       - symmetric MAPE scalar

smape <- function(forecast, actual) {
  if (length(forecast) != length(actual)) {
    return (NA);
  } else if (length(forecast) == 0 || length(actual) == 0) {
    return (NA);
  }
  else{
    diff_vals <- abs(forecast - actual)
    sum_vals <- 0.5*(abs(forecast) + abs(actual))
    not_zero <- sum_vals!=0
    e <- 0.0
    if(sum(not_zero) > 0) {
      e <- 100*sum(diff_vals[not_zero]/sum_vals[not_zero])/sum(not_zero)
    }
  }
  return(e)
}


# Function that returns forecast for horizon h, given training data
#
# Input: data_train - training data
#        params     - a list of global parameters used throughout the project
#        univariate - logical indicator whether the time series si univariate or not
#
# Output: fcasts  - forecasts for horizon h


make_forecast <- function(data_train, params, univariate=FALSE){
  
  if (univariate){
    fit <- auto.arima(data_train)
    fcasts <- forecast(fit, h = params$HORIZON)
    fcasts <- fcasts$mean
    
    fcasts[fcasts < 0] <- 0
    
  } else {
    
    # Forecast the next HORIZON months based on the training data
    fcasts <- forecast.gts(data_train,  
                           h=params$HORIZON, 
                           method=params$GTSMETHOD, 
                           fmethod = params$TSMETHOD, 
                           weights = params$COMBHTS_WEIGHTS)
    # remove negative values from forecast
    fcasts$bts[fcasts$bts < 0] <- 0
  }
  
  return(fcasts)
  
}

# Function that formats the output of make_forecast into a data frame
#
# Input: fcasts     - output of make_forecast()
#        ts_names   - the names of time series (returned by create_gts_data)
#        univariate - logical indicator whether the time series si univariate or not
#
# Output: fcast_output  - forecast data frame

format_fcast <- function(fcasts, ts_names, univariate=FALSE){
  
  if (univariate){
    
    fts <- fcasts
    
  } else {
    
    fts <- fcasts$bts
  }
  
  fcast_labels <-  as.yearmon(time(fts))
  bfcasts <- as.data.frame(t(fts))
  colnames(bfcasts) <- fcast_labels
  fcast_output <- cbind(ts_names, bfcasts)
  rownames(fcast_output) <- NULL
  
  return(fcast_output)
  
}


# A helper function that fills in missing values in an inclomplete time series with zeros
# 
# Input: ts_data  - a time series data frame generated in create_ts_data() function 
#        ts_seq   - a sequence of dates for which to complete the time series
#
# Output: complete_ts - a complete ts data frame with no missing values

complete_ts <- function(ts_data, ts_seq){
  
  # merge data with full time sequence
  ts_seq <- data.frame(Date = ts_seq)
  complete_ts <- ts_data %>% right_join(ts_seq, by = "Date")
  
  # find NAs introduced by the merge
  nas <- !complete.cases(complete_ts)
  q <- which(names(complete_ts) == "Quantity")
  grp <- unique(complete_ts[!nas, -q])
  
  # fill in the NAs
  complete_ts$Quantity[nas] <- 0
  grp <- unique(complete_ts[!nas, -q])
  complete_ts[nas, -q] <- sapply(grp, rep.int, times=sum(nas))
  
  return(complete_ts)
  
}



# Function that creates grouped time series object from a data set
# 
# Input: dataset  - dataset pulled from the DB and processed by process_dataset()
#        params   - a list of global parameters used throughout the project
#
# Output: all_ts  - grouped time series (gts) or ordinary time series (ts) object

create_gts_data <- function(dataset, params){
  
  keep_vars <- c('Date', params$FORECASTING_VARS)
  dots <- lapply(keep_vars, as.symbol)
  
  # Aggregate to monthly data
  bts <- dataset %>% 
    dplyr::select(Date, one_of(params$FORECASTING_VARS), Quantity) %>% 
    dplyr::group_by_(.dots=dots) %>% 
    dplyr::summarise(Quantity = sum(Quantity)) %>%
    tidyr::unite(unique_group, -Date, -Quantity) %>% 
    tidyr::spread(unique_group, Quantity, fill=0) %>%
    dplyr::arrange(Date) %>%
    dplyr::ungroup()
  
  ts_start <- bts$Date[1]
  
  bts <- bts %>% select(-Date)
  
  # Create multivariate time series object
  all_ts <- ts(bts, start = c(year(ts_start), month(ts_start)), frequency = params$FREQUENCY)
  
  
  # Create grouped time series object 
  if(length(params$FORECASTING_VARS) == 1){ # Handling 1-level deep hierarchy
    
    unique_groups <- data.frame(colnames(bts))
    colnames(unique_groups) <- c(params$FORECASTING_VARS)
    
    if(dim(all_ts)[2] == 1){ # univariate ts (special case)
      all_bts <- all_ts
    }
    else {
      all_bts <- gts(all_ts)
      all_bts$labels[[params$FORECASTING_VARS]] <- colnames(all_bts$groups)
      
    }
    
    
  } else{
    
    unique_groups <- data.frame(ug = colnames(bts)) %>%
      tidyr::separate(col=ug, params$FORECASTING_VARS, sep="_")
    
    novar <- unique_groups %>% summarise_each(funs(n_distinct))
    rmcol <- which(novar == 1)
    
    if(length(rmcol)>0) {
      bts_groups <- unique_groups[, -rmcol]
    } else {
      bts_groups <- unique_groups
    }
    
    
    bts_groups <- t(as.matrix(bts_groups))
    all_bts <- gts(all_ts, groups = bts_groups)
    
  }
  
  # Return time series and the time series names
  return(list(ts = all_bts, ts_names = unique_groups))
  
}



# Function that creates time series object from a data set
# 
# Input: dataset  - dataset pulled from the DB and processed by process_dataset()
#        params   - a list of global parameters used throughout the project
#
# Output: all_ts  - hierarchical time series (hts) or ordinary time series (ts) object

create_hts_data <- function(dataset, params){
  
  keep_vars <- c('Date', params$FORECASTING_VARS)
  dots <- lapply(keep_vars, as.symbol)
  
  # Aggregate to monthly data
  monthly_data <- dataset %>% 
    dplyr::select(Date, one_of(params$FORECASTING_VARS), Quantity) %>% 
    dplyr::group_by_(.dots=dots) %>% 
    dplyr::summarise(Quantity = sum(Quantity)) %>%
    as.data.frame()
  
  # Create complete time sequence for filling out the missing values in the TS later
  min_date <- min(dataset$Date, na.rm = TRUE)
  max_date <- max(dataset$Date, na.rm = TRUE)
  full_tseq <- seq(min_date, max_date, by="month")
  
  # Identify hierarhy sub-categories
  hts_vars <- params$FORECASTING_VARS
  md <- monthly_data[, hts_vars]
  umd <- unique(md)
  nodes <- list()
  
  # Get the structure of the hierarchy - variable nodes:
  # Handle the case when only one variable specified for disaggregation
  if(length(hts_vars) == 1){
    
    unique_subgroups <- data.frame(umd)
    unique_subgroups$dummy <- rep("1", length(umd))
    colnames(unique_subgroups) <- c(hts_vars, "dummy")
    nodes[[1]] <- length(unique(unique_subgroups[, 1]))
    
    # Create subcategories time
    ngroups <- dim(unique_subgroups)[1]
    all_ts <- matrix(nrow = length(full_tseq), ncol = ngroups)
    for (i in 1:ngroups){
      this_ts <- unique_subgroups[i,]
      this_ts_data <- merge(monthly_data, this_ts)
      this_ts_data$dummy <- NULL
      this_ts_data_complete <- complete_ts(this_ts_data, full_tseq)
      all_ts[,i] <- this_ts_data_complete$Quantity
    }
    
    
  } else {
    
    unique_subgroups <- umd[do.call("order", umd[hts_vars]), ] 
    # Get the nodes for the time series hierarchy
    nodes[[1]] <- length(unique(unique_subgroups[, 1]))
    for (i in 1:(length(hts_vars)-1)){
      curr_vars <- hts_vars[1:i]
      result <- unique_subgroups %>% 
        dplyr::group_by_(.dots = curr_vars) %>% 
        dplyr::summarise(count = length(unique(unique_subgroups[,i+1])))
      nodes[[i+1]] <- result$count
    }
    
    # Create subcategories time
    ngroups <- dim(unique_subgroups)[1]
    all_ts <- matrix(nrow = length(full_tseq), ncol = ngroups)
    for (i in 1:ngroups){
      this_ts <- unique_subgroups[i,]
      this_ts_data <- merge(monthly_data, this_ts)
      this_ts_data_complete <- complete_ts(this_ts_data, full_tseq)
      all_ts[,i] <- this_ts_data_complete$Quantity
    }
  }
  
  
  all_ts <- ts(all_ts, start = c(year(min_date), month(min_date)), frequency = params$FREQUENCY)
  
  # Create hierarchical time series object only for multivariate time series
  # For univariate time series return all_ts as is
  
  if(dim(unique_subgroups)[1] > 1){
    colnames(all_ts) <- apply(unique_subgroups, 1, paste, collapse="_")
    all_ts <- hts(all_ts, nodes)
  }
  
  # Remove dummy variable if one created
  if("dummy" %in% names(unique_subgroups)) unique_subgroups$dummy <- NULL
  
  # Return time series and the time series names
  return(list(ts = all_ts, ts_names = unique_subgroups))
  
}


# Function that runs the grouped forecast on training data set and calculates 
# evaluation metrics on the test data set
#
# Input: dataset  - dataset pulled from the DB and processed by process_dataset()
#        params   - a list of global parameters used throughout the project
#
# Output: output  - a list containing 
#                     - RMSE averaged over all forecast months
#                     - nodename of the computer on which the function ran

forecast_main <- function(dataset, params = NULL){
  
  if(is.null(params)) params <- make_params()
  
  # assume it's multivariate ts
  univariate = FALSE
  
  # Create time series data set
  if(params$GTSorHTS == "gts"){
    ts_data <- create_gts_data(dataset, params)
  } else if(params$GTSorHTS == "hts"){
    ts_data <- create_hts_data(dataset, params)
  }
  
  all_ts <- ts_data$ts
  
  # Check if the ts is univariate
  if(dim(ts_data$ts_names)[1] == 1) univariate = TRUE
  
  if(univariate){
    tseries <- all_ts
  } else{
    tseries <- all_ts$bts
  }
  
  # Forecast the next HORIZON months
  fcasts <- make_forecast(all_ts, params, univariate)
  
  # format the forecasts for the input to further functions
  fcast_output <- format_fcast(fcasts, ts_data$ts_names, univariate)
  
  # Convert forecast data frame from wide to narrow format
  melt_cols <- setdiff(colnames(fcast_output), params$FORECASTING_VARS)
  fcast_output <- fcast_output %>% tidyr::gather_("ForecastDate", "Quantity", melt_cols)

  return(fcast_output)
  
}


# Function that computes cross validation on the data
# RMSE - root mean squared error
# MAE - mean absolute error
#
# Input: dataset  - dataset pulled from the DB and processed by process_dataset()
#        params   - a list of global parameters used throughout the project
#        nfolds   - number of folds for cross-validation
#
# Output: dataframe containing computed accuracy measures and the original dataset

get_crossval_accuracy <- function(dataset, params, nfolds = 3){
  
  ML_CALL_LOG <- append_log(paste("Running cross-validation for", nfolds, "folds to compute historical evaluation metrics."))
  
  # Always forecasting 1 month ahead for cross-validation
  horizon = 1
  
  # Assume it's multivariate ts
  univariate = FALSE
  
  ############# SPLIT TRAINING AND TESTING ############
  
  # Create time series data set
  ts_data <- create_gts_data(dataset, params)
  all_ts <- ts_data$ts
  
  # Check if the ts is univariate
  if(dim(ts_data$ts_names)[1] == 1) univariate = TRUE
  
  if(univariate){
    tseries <- all_ts
  } else{
    tseries <- all_ts$bts
  }
  
  time_points <- time(tseries)
  
  test_indices <- as.list((length(time_points) - (horizon - 1) - (nfolds - 1)) : (length(time_points) - (horizon - 1)))
  
  # Modify the default horizon
  tmp_params <- params
  tmp_params$HORIZON <- horizon
  
  eval_list <- lapply(test_indices, 
                      
                      function(tstart) {
                        
                        # --- Forecast on training set
                        
                        print('Running a cross validation fold.')
                        ML_CALL_LOG <- append_log("Running a cross validation fold.")
                        
                        # Get training data
                        data_train <- window(all_ts, start = time_points[1], end=time_points[tstart-1])
                        
                        # Compute the MAE for a naive forecast on each training series
                        # These will be used in the MASE calculation
                        first_train_date <- as.Date.yearmon(time_points[1])
                        last_train_date <- as.Date.yearmon(time_points[tstart-1])
                        
                        data_mne <- dataset %>%
                                    filter(Date >= first_train_date & Date <= last_train_date) %>%
                                    group_by_(.dots = params$FORECASTING_VARS) %>%
                                    summarise(naiveMAE = mean(abs(diff(Quantity)))) %>%
                                    ungroup()
                        
                        
                        # Forecast the next HORIZON months based on the training data
                        fcasts <- make_forecast(data_train, tmp_params, univariate)
                        
                        # Format the forecasts for the input to further functions
                        final_fcast <- format_fcast(fcasts, ts_data$ts_names, univariate)
                        
                        month_cols <- (length(params$FORECASTING_VARS)+1):dim(final_fcast)[2]
                        colnames(final_fcast)[month_cols] <- paste0('fcast', 1:length(month_cols)) -> fcast_labs
                        
                        # --- Extract actuals (this needs to be done from dataset, since the ts object does not contain the bottom level ts)
                        
                        first_test_date <- as.Date.yearmon(time_points[tstart])
                        last_test_date <- as.Date.yearmon(time_points[tstart + horizon - 1])
                        
                        id_vars <- c(params$FORECASTING_VARS, 'Date')
                        id_vars <- lapply(id_vars, as.symbol)
                        
                        data_test <- dataset %>% 
                          filter(Date >= first_test_date & Date <= last_test_date) %>%
                          group_by_(.dots=id_vars) %>% 
                          summarise(Quantity = sum(Quantity)) %>%
                          arrange(Date) %>%
                          spread(Date, Quantity, fill=0)
                        
                        colnames(data_test)[month_cols] <- paste0('actual', 1:length(month_cols)) -> actual_labs
                        
                        # --- Compute evaluation metrics
                        
                        # Merge testing and forecasted data
                        merge_data <- data_test %>%
                          full_join(final_fcast, by=params$FORECASTING_VARS) %>%
                          left_join(data_mne, by=params$FORECASTING_VARS) %>%
                          as.data.frame()
                        
                        merge_data[is.na(merge_data)] <- 0 
                        
                        # Compute evaluation metrics across the horizon for each time series 
                        merge_data$RMSE <- apply(merge_data, 1, function(x) rmse(as.numeric(x[fcast_labs]), as.numeric(x[actual_labs])))
                        merge_data$MAE <- apply(merge_data, 1, function(x) mae(as.numeric(x[fcast_labs]), as.numeric(x[actual_labs])))
                        merge_data$MAPE <- apply(merge_data, 1, function(x) mape(as.numeric(x[fcast_labs]), as.numeric(x[actual_labs])))
                        merge_data$MPE <- apply(merge_data, 1, function(x) mpe(as.numeric(x[fcast_labs]), as.numeric(x[actual_labs])))
                        #merge_data$MASE <- apply(merge_data, 1, function(x) as.numeric(x[c("MAE")])/as.numeric(x[c("naiveMAE")]))
                        merge_data <- transform(merge_data, MASE = MAE/naiveMAE)
                        merge_data$SMAPE <- apply(merge_data, 1, function(x) smape(as.numeric(x[fcast_labs]), as.numeric(x[actual_labs])))
                        
                        return(merge_data)
                      }
  )
  
  return(eval_list)
  
}


# Function that computes performance measures on historical data:
# RMSE - root mean squared error
# MAE - mean absolute error
# Tolerance PASS - percentage of forecasts that pass tolerance threshold (+- 25% of actuals)
#
# It runs the cross-validation and averages the obtained cross-evaluation metrics
#
# Input: dataset  - dataset pulled from the DB and processed by process_dataset()
#        params   - a list of global parameters used throughout the project
#
# Output: dataframe containing computed evaluation measures

get_historical_accuracy <- function(dataset, params){
  
  # Run cross-validation
  crossval_result <- get_crossval_accuracy(dataset, params, nfolds = params$EVALUATION_WINDOW)
  
  # Print out overall accuracy measures
  avg_metrics <- lapply(crossval_result, function(x){
    x %>% 
      summarise(RMSE = rmse(x$fcast1, x$actual1),
                MAE = mae(x$fcast1, x$actual1),
                MAPE = mape(x$fcast1, x$actual1),
                MPE = mpe(x$fcast1, x$actual1),
                MASE = mean(x$MASE),
                SMAPE = smape(x$fcast1, x$actual1))
  })  %>% bind_rows() %>% colMeans() 
  
  # Format and return accuracy metrics
  
  metrics_df <- as.data.frame(t(avg_metrics))
  colnames(metrics_df) <- c('RMSE', 'MAE', 'MAPE', 'MPE', 'MASE', 'SMAPE')
  rownames(metrics_df) <- NULL
  
  return(metrics_df)
  
}

