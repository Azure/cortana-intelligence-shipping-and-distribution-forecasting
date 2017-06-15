-- ===================================================
-- Description:	Commands for creating all SQL tables in the PCS
-- ===================================================

# Input table 1 - Historical orders 
CREATE TABLE [FcastML].[HistoricalOrders](
	[CustomerName] [nvarchar](100) NOT NULL,
	[ProductCategory] [nvarchar](100) NOT NULL,
	[Destination] [nvarchar](100) NOT NULL,
	[ForecastDate] [date] NOT NULL,
	[Quantity] [float] NOT NULL,
 CONSTRAINT [PK_HistoricalOrders] PRIMARY KEY CLUSTERED 
(
	[CustomerName],
	[ProductCategory],
	[Destination],
	[ForecastDate]
))
GO 

# Input table 2 - Forecasting parameters
CREATE TABLE [FcastML].[ForecastParameters](
	[ForecastParametersId] [nvarchar](100) NOT NULL,
	[ModelVersion] [nvarchar](100) NOT NULL,
	[MLCallDate] [date] NOT NULL,
	[EarliestOrderHistoryDate] [date] NOT NULL,
	[LatestOrderHistoryDate] [date] NOT NULL,
	[ForecastHorizonMonths] [int] NOT NULL,
	[EvaluationWindow] [int] NOT NULL,
	[GTSorHTS] [nvarchar](10),
	[CombiningGTSMethod] [nvarchar](10),
	[UnivariateTSMethod] [nvarchar](10),
	[GTSCombWeights] [nvarchar](10),
 CONSTRAINT [PK_ForecastParameters] PRIMARY KEY CLUSTERED 
(
	[ForecastParametersId] ASC,
	[ModelVersion] ASC
) 
)
GO


# Output table 1 - Forecast results
CREATE TABLE [FcastML].[StatisticalForecast](
	[CustomerName] [nvarchar](100) NOT NULL,
	[ProductCategory] [nvarchar](100) NOT NULL,
	[Destination] [nvarchar](100) NOT NULL,
	[ForecastDate] [date] NOT NULL,
	[Quantity] [float] NOT NULL,
	[ForecastParametersId] [nvarchar](100) NOT NULL,
	[ModelVersion] [nvarchar](100) NOT NULL,
 CONSTRAINT [PK_StatisticalForecast] PRIMARY KEY CLUSTERED 
(
	[ForecastParametersId] ASC,
	[ModelVersion] ASC,
	[CustomerName],
	[ProductCategory],
	[Destination],
	[ForecastDate]
) 
)
GO

# Output table 2 - Forecast history and evaluation
CREATE TABLE [FcastML].[ForecastHistory](
	[ForecastParametersId] [nvarchar](100) NOT NULL,
	[ModelVersion] [nvarchar](100) NOT NULL,
	[MLCallDate] [date] NOT NULL,
	[RMSE] [float] NULL,
	[MAE] [float] NULL,
	[MPE] [float] NULL,
	[MAPE] [float] NULL,
	[MASE] [float] NULL,
	[SMAPE] [float] NULL,
	[MLCallLog] [nvarchar](max) NULL,
 CONSTRAINT [PK_ForecastHistory] PRIMARY KEY CLUSTERED 
(
	[ForecastParametersId] ASC,
	[ModelVersion] ASC
)
)
GO
