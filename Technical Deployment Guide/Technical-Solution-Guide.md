# Shipping and Distribution Demand Forecasting 

## Outline

  1. [Introduction](#introduction)
  2. [Architecture](#architecture)
  3. [Technical details and workflow](#technical-details-and-workflow)
  4. [Provisioned Resources](#provisioned-resources)
  5. [Data Schema](#data-schema)
  6. [Simulated Data](#simulated-data)
  7. [Solution Customization](#solution-customization)

## Introduction  
The Shipping and Distribution Demand Forecasting Solution uses historical demand time series to forecast demand in future periods. For instance, a shipping or delivery company wants to predict the quantities of the different products its customers will commit at future times.  Similarly a vendor or insurer wants to know the number of products that will be returned due to  failure over the course of a year. A company can use these forecasts as input to an allocation tool that optimizes delivery vehicles or routes, or to plan capacity in the longer term.

Characteristic of all of these forecasting cases are:

- There are numerous kinds of items with differing volumes, that roll up under one or more category levels.
- There is a history available for the quantity of the item at each time in the past.
- The volumes of the items differ widely, with possibly a substantial number that have zero volume at times. 
- The history of items shows both trend and seasonality, possibly at multiple time scales. 
- The quantities commited or returned are not strongly price sensitive. In other words, the delivery company cannot 
  strongly influence quantities by short-term changes in prices, although there may be other determinants that
  affect volume, such as weather. 
  
Under these conditions we can take advantage of the hierarchy formed among the time series of the different items.  By enforcing consistency so that the quantities lower in the hierarchy (e.g. individual product quantities) sum to the quantities above (customer product totals) we improve the accuracy of the overall forecast. The same applies if individual items are grouped into categories, even possibly categories that overlap.  For example, one might be interested in forecasting demand of all products in total, by location, by product category, by customer, etc. 

This solution computes forecasts at all aggregation levels in the hierarchy for each time period specified. For simplicity, we will refer to both hierarchial and grouped time series as "hierarchical time series."

### Automatically installing solutions in the Cloud

A "solution" refers to an assembly of Azure resources, such as predictive services, cloud storage an so on, 
that consitute an application. The _Deploy_ button on this page runs a service that automates the set of steps to create a runnable copy of this application in your Azure subscription.  If you don't already have a subscription, then you need to sign up for one on [Azure](https://azure.microsoft.com/) first. 

In addition if you are a System Integrator and ISV, you will be able to customize this solution to build derivative applications on Azure for your clients' specific needs. You can find the entire sources for this "Cortana Intelligence Quick Start" (CIQS) Installer on TODO [this Github repository]().  

### The fundamentals of hierarchical forecasting 

Time series data can often be disaggregated by attributes of interest to form groups of time series or a hierarchy. For example, one might be interested in forecasting demand of all products in total, by location, by product category, by customer, etc. Forecasting grouped time series data is challenging because the generated forecasts need to satisfy the aggregate requirement, that is, lower-level forecasts need to sum up to the higher-level forecasts. There are many approaches that solve this problem, differing in the way they aggregate individual time series forecasts across the groups or the hierarchy. 

The novelty of this solution is to generate accurate forecasts that satisfy aggregation requirements; that is, lower-level forecasts need to sum up to the higher-level forecasts, and the individual forecasts are more accurate than just independantly generated ones. The challenge has spawned many approaches to solving this problem, differing in the way they aggregate individual time series forecasts across the groups or the hierarchy. This solution exposes several approaches to forecasting grouped time series as a parameter, namely bottom-up, top-down and a combination approach ([Hyndman et al.](http://otexts.org/fpp/9/4)).

### Customizations and limitations

The solution "out of the box" takes the monthly historical data you provide, and predicts the demand broken out by three levels of hierarchy, customer, product and, destination. Therefore, the solution assumes:
  - a specific data schema (described in more detail below in [Data Schema](#data-schema) section),
  - a monthly demand time series.

A number of configurations can be made through the exposed solution parameters. These parameters are stored in the SQL table (described in the [Data Schema section](#data-schema)) and passed on to the Azure Machine Learning web service that generates the forecasts. Some of these parameters are the starting and ending dates of the historical demand, the number of periods to forecast, the structure of the hierarchy or grouping rules, and so on. 

If you want to make more extensive customizations to the machine learning web-service, we provide the [R code used in the web-service](./ADF/code/). For example, if you would like to modify the the web service to forecast weekly time series demand data (rather than monthly), this will require changes to the R code. Note that more extensive modifications to the web service, such as modifications to its inputs and outputs, may require changes to the auxiliary AML files and the SQL data tables where the data resides.  

## Architecture

The following chart describes the solution architecture. 

![Solution Architecture](https://github.com/Azure/cortana-intelligence-shipping-and-distribution-forecasting/blob/master/Technical%20Deployment%20Guide/media/architecture.PNG)

The solution uses five types of resources hosted and managed in Azure: 

* **Azure SQL Server** instance (Azure SQL) for persistent storage, 
* **Azure Machine Learning** (AML) webservice to host the R forecasting code, 
* **Azure Blob Storage** for intermediate storage of generated forecasts,
* **Azure Data Factory** (ADF) that orchestrates regular runs of the AML model,  
* **Power BI** dashboard to display and drill down on the forecasts. 

## Technical details and workflow

The deployment goes through several provisioning and setup steps, using a combination of **Azure Resource Manager (ARM)** templates and **Azure Functions**. ARM templates are JSON files that define the resources you need to deploy for your solution. Azure Functions is a serverless compute service that enables you to run code on-demand without having to explicitly provision or manage infrastructure. We will describe ARM templates and Azure Functions used in this solution in later sections.

The resources deployed in this solution are provisioned in the following order:

1. **Setup SQL Server Account**: The first step in the workflow sets up a SQL server account. The user is prompted for credentials, and asked to specify the following parameters:
    * **sqlServerUser**: SQL Server username
    * **sqlServerPasswd**: SQL Server password

    > [NOTE]
    > The server admin login and password that you specify here are required to log in to the server and its databases. Remember or record this information for later use. 
    >  

2. **Deploying SQL Server Resources**: In this step, an **Azure SQL Server** and **Azure SQL Database** are provisioned. These resources are described in *SqlDeploy.json* ARM template. Azure SQL Database is used to store the historical demand data and the prediction results received from the Azure Machine Learning service. 

3. **Configuring Blob Storage**: **Azure Storage Account** is configured in this step for storing the following: 1) R code used for forecasting, that is turned into Azure Machine Learning web service, later in the process, 2) intermediate forecasting results, before they are loaded into the Azure SQL Database. This step creates a container for ADF intermediate storage, a container for Azure Machine Learning R module, and copies the module zip file to the previously created container. This is accomplished with *BlobStorageSetup* Azure function.

4. **Creating SQL Database Objects**: In this step, Azure Function *SqlDbSetup* creates all necessary database objects: tables and stored procedures. In addition, it populates the demand SQL table with a sample data set, stored in a sample file, *ExampleDemandData.csv*.

5. **Deploying ML Webservice**: Once the R code used for forecasting is copied to Azure Storage, this step creates an **Azure Machine Learning** service by executing *FcastMlDeploy.json* ARM template. This template deploys the R code as **Custom R Module** in Azure ML Studio and links web service inputs and outputs to relevant storage accounts. The resulting AML webservice is used to generate the demand forecasts.

6. **Retrieving ML Webservice Credentials**: In this step of the deployment process, we only retrieve the ML webservice API key. This is accomplished with *GetMLApiKey* Azure Function. The webservice API key is used later by the Azure Data Factory that schedules the calls to the webservice.

7. **Deploying Data Factory**: **Azure Data Factory** handles orchestration, and scheduling of the monthly demand forecast. In this step of the deployment process, we set up the Data Factory pipeline - define resources it orchestrates, provide their credential, define scheduling timeline, etc. This is accomplished with the *DataFactoryDeploy.json* ARM template. At this point in time the Data Factory is not active yet - we will activate it as the last step of the deployment process.

8. **Activating Data Factory Pipelines**: Finally, Azure Function *StartPipelines* activates the Data Factory, and triggers the activities performed by it, most notably, the generation of the monthly forecast on the example data set. 


## Provisioned Resources

Once the solution is deployed to the subscription, you can see the services deployed by clicking the resource group name on the final deployment screen in the CIS.

![CIS resource group link](https://github.com/Azure/cortana-intelligence-shipping-and-distribution-forecasting/blob/master/Technical%20Deployment%20Guide/media/ciqs_resources.png)

This will show all the resources under this resource group on [Azure management portal](https://portal.azure.com/). After successful deployment, the entire solution is automatically started on cloud. You can monitor the progress from the following resources.

#### Azure Functions

Six Azure Functions are created during the deployment to start certain Azure services. We described the tasks performed by these functions in the [Technical Details and Workflow](#technical-details-and-workflow) section above. You can monitor these functions' progress by clicking the link on your deployment page.

* **BlobStorageSetup**: Sets up Azure blob storage.
* **GetMLApiKey**: Retrievs ML webservice key.
* **SqlDbSetup**: Sets up SQL database objects.
* **StartPipelines**: Activates data factory pipeline.

#### Azure Data Factory

Azure Data Factory is used to schedule machine learning model. You can monitor the data pipelines by clicking the link on your deployment page.

#### Azure SQL Database

Azure SQL database is used to save the data and forecast results. You can use the SQL server and database name showing on the last page of deployment with the username and password that you set up in the beginning of your deployment to log in your database and check the results.

#### Azure Machine Learning Web Service

You can view your forecasting model on machine learning experiment by navigating to your Machine Learning Workspace. The machine learning model is deployed as Azure Web Service to be invoked by the Azure Data Factory. You can view your the web service API manual by clicking the link on your deployment page.

#### Power BI Dashboard

Once the solution is deployed, the forecasting web service generates forecasts for a simulated sample data set, included with this solution. To view the generated forecasts, and drill down by customer, product, and destination, you can click on the Power BI dashboard link on your deployment page.  


## Data Schema

Here we describe the valid data schemas and fields for SQL tables used by the solution. 
    
The solution consumes four database tables: __HistoricalOrders__, __ForecastParameters__, __StatisticalForecast__, and __ForecastHistory__. The solution reads historical orders data from __HistoricalOrders__ database, and a set of forecasting parameters from the __ForecastParameters__ table. These two data sources are then used in the forecasting model which generates future demand forecasts, and a set of evaluation metrics on the historical data. Generated forecast is written into __StatisticalForecast__ table, while evaluation metrics as well as additional logging infromation is written into __ForecastHistory__ table.

Figure below shows the data sources to the forecasting model and the respective SQL tables.

![DBSourceFlow](https://github.com/Azure/cortana-intelligence-shipping-and-distribution-forecasting/blob/master/Technical%20Deployment%20Guide/media/dbschema_sourcediagram.PNG)

Here we provide more information about the tables used, their columns, valid values and constraints.

### Input table 1 - Historical orders 

Table __HistoricalOrders__ contains data on historical orders. We provide field descriptions in a table below. All fields in this table except the Date and Quantity are used as disaggregation variables for the grouped (or hierarchical) time series. Date is used as time series time points, and Quantity is used as a time series data point that is used for modeling and forecasting.

| Field | Description| Type | Example | Comments |
|:-----:|:----|:----|:----|:----|
| CustomerName | Individual customer name | Text | Contoso | Key |
| ProductCategory | Product category being distributed | Text | Plastics | Key |
| Destination | Region or country of destination | Text | Europe | Key |
| Date | Date of the order | Date | 01-01-2017 | This field needs to be aggregated to monthly level. Current solution only allows monthly order data, so the dates will always be the first of the month (e.g. 01-01-2017, 01-02-2017, etc.); Key|
| Quantity | Historical order quantity | Numeric | 50  | This is the the field the forecasting model will forecast. |

 The following columns form the composite __primary key__ for HistoricalOrders table: __(CustomerName, ProductCategory, Destination, Date)__.


### Input table 2 - Forecasting parameters

Table __ForecastParameters__ contains parameters that define the forecasting approach used to generate the forecasts. Field descriptions are given in the table below. In particular, parameters that define time series approaches used for forecasting originate from the ['hts'](https://cran.r-project.org/web/packages/hts/index.html) R package which is used for hierarchical or grouped time series forecasting. For a more detailed overview (beyond what is provided in the table below), please refer to package documentation or the author's book [Forecasting: principles and practice (Chapter 9.4)](https://www.otexts.org/fpp/9/4).

| Field | Description| Type | Example | Comments |
|:-----:|:----|:----|:----|:----|
|ForecastParametersId | Unique identifier for each set of forecasts produced by the forecasting model | Text| AUG2017 | Key | 
|EarliestOrderHistoryDate | Earliest order date to include | Date | 07-01-2014 | This field can be used to filter out noisy data from training (for example, earlier data points that do not reflect most recent trends and can degrade the time series analysis) |
|LatestOrderHistoryDate | Latest order date to include | Date | 04-01-2017 | Similar to above, this field can be used to filter out later data points from training (for example, the current month can be exluded from training, as its orders are not complete yet). Notice that the forecasting model will generate forecasts from this date on.|
|ForecastHorizonMonths | Number of months to forecast, forecasting horizon | Numeric | 3 | The forecasting model will generate forecasts for ForecastHorizonMonths from the LatestOrderHistoryDate. |
|EvaluationWindow | Number of months history to use for computing evaluation metrics | Numeric | 5 | The forecasting model returns evaluation metrics based on the historical data, and uses most recent months specified with this parameter to compute those metrics. For example, for EvaluationWindow = 3, forecast evaluation is performed on the last 3 months.|
|GTSorHTS | | Text | gts | Valid values: "gts" (for grouped time series), "hts" (for hierarchical time series). |
|CombiningGTSMethod | | Text | bu | Valid values: "bu" (bottom-up approach), "comb" (optimal combination approach as described in [Hyndman et al. (2015)](http://robjhyndman.com/papers/hgts7.pdf))|
|UnivariateTSMethod | | Text | arima | Valid values: "ets" (Exponential smoothing or ETS), "arima" (ARIMA) |
|GTSCombWeights | | Text | nseries |Valid values: "ols", "wls", "nseries". These are weights used for the optimal combination method ("comb"). "ols" uses an unweighted combination, "wls" uses weights based on forecast variances , weights="nseries" uses weights based on the number of series aggregated at each node. |

 The following column forms the __primary key__ for ForecastParameters table: __ForecastParametersId__.

### Output table 1 - Forecast output

When the forecasting model generates the forecasts, they are stored in the __StatisticalForecast__ table. See the table below for field descriptions. Forecasts are generated at the disaggregated level specified by the fields in the input table HistoricalOrders, so this table has a very similar schema to the one of HistoricalOrders table. Note that each time we generate new forecasts, they are appended to this table, and are uniquely identified by the ForecastParametersId and ModelVersion parameters (ForecastParametersId links back to the ForecastParameters table). 

| Field | Description| Type | Example | Comments |
|:-----:|:----|:----|:----|:----|
| CustomerName | Individual customer name | Text | Contoso | Key |
| ProductCategory | Product category being distributed | Text | Plastics | Key |
| Destination | Region or country of destination | Text | Europe | Key |
| ForecastDate | Date of the order | Date | 01-01-2017 | This field needs to be aggregated to monthly level. Current solution only allows monthly order data, so the dates will always be the first of the month (e.g. 01-01-2017, 01-02-2017, etc.); Key|
| Quantity | Historical order quantity | Numeric | 50  | This is the the field the forecasting model will forecast. |
|ForecastParametersId | Unique identifier for each set of forecasts produced by the forecasting model | Text| AUG2017 | Key | 
|ModelVersion | Forecasting model version | Text | 1.2.0 | Key |

 The following columns form the composite __primary key__ for Forecast table: __(ForecastParametersId, ModelVersion, CustomerName, ProductCategory, Destination, ForecastDate)__.


### Output table 2 - Forecast history and evaluation

Table __ForecastHistory__ contains information about forecasting runs. This is a reference table that links generated forecasts with specific parameters and a model version used (via ForecastParametersId and ModelVersion). Additionally, this table provides evaluation metrics for the forecasting run (computed on historical data), as well as the log generated by the forecasting model. See the following table for more information about the ForecastHistory fields.

| Field | Description| Type | Example | Comments |
|:-----:|:----|:----|:----|:----|
|ForecastParametersId | Unique identifier for each set of forecasts produced by the forecasting model | Text| AUG2017 | Key | 
|ModelVersion | Forecasting model version | Text | 1.2.0 | Key |
|MLCallDate | DateTime of call to forecasting model| Date | 12-01-2017 | |
|RMSE | Root mean squared error | Numeric | 2.34 | [More details](https://en.wikipedia.org/wiki/Mean_absolute_scaled_error)  |
|MAE | Mean absolute error | Numeric| 1.39 | [More details](https://en.wikipedia.org/wiki/Mean_absolute_error) |
|MPE | Mean percentage error | Numeric | 6.05 | [More details](https://en.wikipedia.org/wiki/Mean_percentage_error) |
|MAPE | Mean absolute percentage error | Numeric | 2.5 | [More details](https://en.wikipedia.org/wiki/Mean_absolute_percentage_error) |
|MASE | Mean absolute scaled error |Numeric | 3.45 |[More details](https://en.wikipedia.org/wiki/Mean_absolute_scaled_error) |
|SMAPE | Symmetric mean absolute percentage error| Numeric| 2.67 |[More details](https://en.wikipedia.org/wiki/Symmetric_mean_absolute_percentage_erroreaqn ) |
|MLCallLog | Forecasting log | Text |  | This log is generated by the forecasting model, and can be used to track down any issues or look up more information about the forecasting run. |

 The following columns form the composite __primary key__ for ForecastHistory table: __(ForecastParametersId, ModelVersion)__.


## Simulated Data

The solution comes with an example demand data set pre-loaded into the provisioned SQL database. This example data set is generated by an R script, and saved into a .csv file which was used to populate a SQL table containing historical demand during the deployment process. [The R script simulates grouped time series](./ADF/db/ExampleDataGen.R) over a number of customers, products and destinations, and is made available in this solution for any further modifications.


 ## Solution Customization

If you would like to customize the solution to your data and business needs, beyond what can be done through R code customization, you can customize the ARM template files used in the automated deployment. 

* **SqlDeploy.json**: Deploys Azure SQL Server
* **FcastMlDeploy.json**: Deploys ML Webservice
* **DataFactoryDeploy.json**: Sets up Data Factory pipelines

We described these templates in some detail in the [Technical Details and Workflow](#technical-details-and-workflow) section above. However, for demonstration, let's walk through a simple customization scenario, where we will modify the pipeline to generate forecasts on weekly basis, rather than monthly. 

The frequency of runs is specified in the *DataFactoryDeploy.json*. There are four main sections in an ARM template: parameters, variables, resource, and outputs (as shown below). Parameters are values that are provided when deployment is executed to customize resource deployment.
variables are values that are used as JSON fragments in the template to simplify template language expressions. Resources section is the core section of the ARM template and it lists all resource types that are deployed or updated in a resource group. Outputs are values that are returned after deployment.

```
{
  "$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {...},
  "variables": {...},
  "resources": [...],
  "outputs": {...}
}
```

Frequency at which the Azure Data Factory schedules the pipeline is specified under the *variables* section. To change this frequency, navigate to the *pipelineFrequency* variable under the *variables*, and change the value from Month to Week.

```
"variables": {
  "namePrefix": "[resourceGroup().name]",
  "uniqueNamePrefix": "[toLower(concat(variables('namePrefix'), uniqueString(subscription().subscriptionId)))]",
  "dataFactoryName": "[concat(variables('uniqueNamePrefix'),'df')]",
  "pipelineFrequency": "Week",
  "pipelineStartDate": "2017-03-01T00:00:00Z",
  ...
},
```

For more information about ARM templates, please refer to the Azure Resource Manager [documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/) page. 