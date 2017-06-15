library(lubridate)
library(tidyr)

# These packages need to be loaded from local files
install.packages("src/libraries/hts_5.0.zip", lib = ".", repos = NULL, verbose = TRUE)
success <- library("hts", lib.loc = ".", logical.return = TRUE, verbose = TRUE)

install.packages("src/libraries/dplyr_0.4.1.zip", lib = ".", repos = NULL, verbose = TRUE)
success <- library("dplyr", lib.loc = ".", logical.return = TRUE, verbose = TRUE)

# Source the utility functions
source("src/forecast_util.R")

replace.inf.values <- TRUE
ml.model.version <- "1.0.0"


distribution_forecast_entry <- function(dataset, db_params) {
  
  # Start logging
  ML_CALL_LOG <- append_log("Starting the ML pipeline ...")
  
  print("Setting parameters ...")
  
  ML_CALL_LOG <- append_log("Setting forecasting parameters ... ")
  params <- make_params(db_params[1,])
  
  print('Pre-processing data ...')
  
  # Prepare the dataset for modeling
  ML_CALL_LOG <- append_log("Pre-processing data ... ")
  dataset_model <- process_dataset(dataset, params)
  
  print('Forecasting ...')
 
  # Call the forecaster
  ML_CALL_LOG <- append_log("Forecasting ... ")
  final_fcast <- forecast_main(dataset_model, params)
  final_fcast <- transform(final_fcast, ForecastParametersId = params$FORECAST_ID, ModelVersion = ml.model.version)
  
  print('Computing evaluation metrics ...')
  
  # Compute evaluation metrics
  ML_CALL_LOG <- append_log("Computing evaluation metrics ... ")
  accuracy_df <- get_historical_accuracy(dataset_model, params)
  
  if(replace.inf.values) {
    
    check.vec <- t(accuracy_df)
    check.vec[is.infinite(check.vec)] <- NA
    accuracy_df[1,] <- check.vec
  }
  
  print('Saving forecast history ...')
  
  ML_CALL_LOG <- append_log("Done ... ")
  fcst_eval_rec <- data.frame(ForecastParametersId = params$FORECAST_ID,
                              ModelVersion = ml.model.version,
                              MLCallDate = Sys.time(),
                              RMSE = accuracy_df$RMSE,
                              MAE = accuracy_df$MAE,
                              MPE = accuracy_df$MPE,
                              MAPE = accuracy_df$MAPE,
                              MASE = accuracy_df$MASE,
                              SMAPE = accuracy_df$SMAPE,
                              MLCallLog = ML_CALL_LOG)
  
  print('Done.')
  
  return(list(fcst_eval_rec, final_fcast))
}
