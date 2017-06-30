/*
	Create input tables HistoricalOrders and ForecastParameters.
	These belong to the FcastML schema.
*/

CREATE SCHEMA FcastML
GO

CREATE TABLE [FcastML].[HistoricalOrders](
	[CustomerName] [nvarchar](100) NOT NULL,
	[ProductCategory] [nvarchar](100) NOT NULL,
	[Destination] [nvarchar](100) NOT NULL,
	[Date] [date] NOT NULL,
	[Quantity] [float] NOT NULL,
 CONSTRAINT [PK_HistoricalOrders] PRIMARY KEY CLUSTERED 
(
	[CustomerName],
	[ProductCategory],
	[Destination],
	[Date]
))
GO 

CREATE TABLE [FcastML].[ForecastParameters](
	[ForecastParametersId] [nvarchar](100) NOT NULL,
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
	[ForecastParametersId] ASC
) 
)
GO

/*
	Create output tables ForecastHistory and StatisticalForecast.
	These belong to the FcastML schema.
*/
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
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)
)
GO


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

/*************************************
Objects used exlcusively in the Extract,
Transform, Load process
*************************************/
CREATE SCHEMA FcastETL
GO

/*
	Create types for the output tables. 
	These are used in table-values parameter passes in later stored procs.
*/
CREATE TYPE [FcastETL].[ForecastHistoryType] AS TABLE(
	[ForecastParametersId] [nvarchar](100) NOT NULL,
	[ModelVersion] [nvarchar](100) NOT NULL,
	[MLCallDate] [date] NOT NULL,
	[RMSE] [float] NULL,
	[MAE] [float] NULL,
	[MPE] [float] NULL,
	[MAPE] [float] NULL,
	[MASE] [float] NULL,
	[SMAPE] [float] NULL,
	[MLCallLog] [nvarchar](max) NULL
)
GO

CREATE TABLE [FcastETL].[ForecastHistory](
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
	[SliceStart] [bigint] NOT NULL,
	[SliceEnd] [bigint] NOT NULL
)
GO


CREATE TYPE [FcastETL].[StatisticalForecastType] AS TABLE(
	[CustomerName] [nvarchar](100) NOT NULL,
	[ProductCategory] [nvarchar](100) NOT NULL,
	[Destination] [nvarchar](100) NOT NULL,
	[ForecastDate] [date] NOT NULL,
	[Quantity] [float] NOT NULL,
	[ForecastParametersId] [nvarchar](100) NOT NULL,
	[ModelVersion] [nvarchar](100) NOT NULL
)
GO

CREATE TABLE [FcastETL].[StatisticalForecast](
	[CustomerName] [nvarchar](100) NOT NULL,
	[ProductCategory] [nvarchar](100) NOT NULL,
	[Destination] [nvarchar](100) NOT NULL,
	[ForecastDate] [date] NOT NULL,
	[Quantity] [float] NOT NULL,
	[ForecastParametersId] [nvarchar](100) NOT NULL,
	[ModelVersion] [nvarchar](100) NOT NULL,
	[SliceStart] [bigint] NOT NULL,
	[SliceEnd] [bigint] NOT NULL
)
GO

/*
	Stored procs for ETL. 
*/ 

/*
	Load initial set of parameters into ForecastParameters table.
	Input: Earliest date in the HistoricalOrders table for training,
			and number of historical months to include in the parameter
			table.
*/
CREATE PROCEDURE [FcastETL].[spLoadInitialForecastParameters]
(
	@EarliestOrderHistoryDate [Date],
	@StartMonth [Date],
	@EndMonth [Date]
) 
AS
BEGIN
	DELETE FROM FcastML.ForecastParameters

	DECLARE @SliceMonth [Date] = @StartMonth

	WHILE (@SliceMonth <= @EndMonth)
	BEGIN
		INSERT INTO FcastML.ForecastParameters VALUES
		(FORMAT(@SliceMonth,'yyyyMM'),@EarliestOrderHistoryDate,@SliceMonth,6,3,'gts','bu','ets','nseries')

		SET @SliceMonth = DATEADD(month, 1, @SliceMonth)
	END
END
GO

/*
	Translate all the dates in the HistoricalOrders table
	so that the latest date lines up with the reference month
*/
CREATE PROCEDURE [FcastETL].[spRefreshHistoricalOrderDates]
(
	@ReferenceMonth [Date]
)
AS
BEGIN
	DECLARE @LatestHistoricalOrderDate Date = (select max(Date) from FcastML.HistoricalOrders)

	SELECT [CustomerName]
	,[ProductCategory]
	,[Destination]
	,DATEADD(month, DATEDIFF(month, @LatestHistoricalOrderDate, @ReferenceMonth), Date) as [Date] 
	,[Quantity]
	INTO FcastETL.HistoricalOrdersTemp
	FROM FcastML.HistoricalOrders

	DELETE FROM FcastML.HistoricalOrders

	INSERT INTO FcastML.HistoricalOrders
	SELECT * FROM FcastETL.HistoricalOrdersTemp

	DROP TABLE FcastETL.HistoricalOrdersTemp
END
GO

CREATE PROCEDURE [FcastETL].[spGetEarliestHistoricalOrderDate]
AS
BEGIN
	SELECT MIN(Date) FROM FcastML.HistoricalOrders
END
GO

/*
	These ETL Procs are called by ADF
*/

CREATE PROCEDURE [FcastETL].[spReadSliceForecastParameters]
(
	@SliceStart [date],
	@SliceEnd [date]
) 
AS
BEGIN
	SELECT TOP 1 [ForecastParametersId],
	[EarliestOrderHistoryDate],
	[LatestOrderHistoryDate],
	[ForecastHorizonMonths],
	[EvaluationWindow],
	[GTSorHTS],
	[CombiningGTSMethod],
	[UnivariateTSMethod],
	[GTSCombWeights]
	  FROM FcastML.ForecastParameters
	 WHERE LatestOrderHistoryDate >= @SliceStart AND LatestOrderHistoryDate < @SliceEnd
END
GO


CREATE PROCEDURE [FcastETL].[spWriteForecastHistory] 
(
	@ForecastHistory [FcastETL].[ForecastHistoryType] READONLY,
	@SliceStart [bigint],
	@SliceEnd [bigint]
)
AS
BEGIN
	INSERT INTO [FcastETL].[ForecastHistory] SELECT *,@SliceStart,@SliceEnd FROM @ForecastHistory
END
GO


CREATE PROCEDURE [FcastETL].[spWriteStatisticalForecast] 
(
	@StatisticalForecast [FcastETL].[StatisticalForecastType] READONLY,
	@SliceStart [bigint],
	@SliceEnd [bigint]
)
AS
BEGIN
	INSERT INTO [FcastETL].[StatisticalForecast] SELECT *,@SliceStart,@SliceEnd FROM @StatisticalForecast
END
GO


CREATE PROCEDURE [FcastETL].[spUpdateForecastMLTables]
(
	@SliceStart [bigint],
	@SliceEnd [bigint]
) 
AS
BEGIN
    DELETE FH
	FROM [FcastML].[ForecastHistory] AS FH 
	INNER JOIN 
	(
		SELECT * FROM [FcastETL].[ForecastHistory]
		WHERE SliceStart = @SliceStart AND SliceEnd = @SliceEnd
	) etl
	ON FH.ForecastParametersId=etl.ForecastParametersId AND
		FH.ModelVersion=etl.ModelVersion

	INSERT INTO [FcastML].[ForecastHistory] 
	SELECT [ForecastParametersId]
      ,[ModelVersion]
      ,[MLCallDate]
      ,[RMSE]
	  ,[MAE]
	  ,[MPE]
	  ,[MAPE]
	  ,[MASE]
	  ,[SMAPE]
	  ,[MLCallLog]
	FROM [FcastETL].[ForecastHistory]
	WHERE SliceStart = @SliceStart AND SliceEnd = @SliceEnd

	DELETE SF
	FROM [FcastML].[StatisticalForecast] AS SF 
	INNER JOIN 
	(
		SELECT * FROM [FcastETL].[StatisticalForecast]
		WHERE SliceStart = @SliceStart AND SliceEnd = @SliceEnd
	) etl
	ON SF.ForecastParametersId=etl.ForecastParametersId AND
		SF.ModelVersion=etl.ModelVersion
	
	INSERT INTO [FcastML].[StatisticalForecast] 
	SELECT [CustomerName]
		  ,[ProductCategory]
	      ,[Destination]
	      ,[ForecastDate]
	      ,[Quantity]
          ,[ForecastParametersId]
          ,[ModelVersion]
	FROM [FcastETL].[StatisticalForecast]
	WHERE SliceStart = @SliceStart AND SliceEnd = @SliceEnd

	DELETE FHETL
	FROM [FcastETL].[ForecastHistory] as FHETL
	WHERE SliceStart = @SliceStart AND SliceEnd = @SliceEnd

	DELETE SFETL
	FROM [FcastETL].[StatisticalForecast] as SFETL
	WHERE SliceStart = @SliceStart AND SliceEnd = @SliceEnd
END
GO


