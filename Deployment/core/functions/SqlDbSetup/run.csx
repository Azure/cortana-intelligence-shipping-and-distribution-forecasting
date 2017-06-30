#r "System.Data"
#r "Microsoft.SqlServer.Smo"
#r "Microsoft.SqlServer.ConnectionInfo"
#load "..\CiqsHelpers\All.csx"

using System;
using System.Collections.Generic;
using System.IO;
using System.Globalization;
using System.Threading;
using System.Net;
using System.Data;
using System.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Common;

public static async Task<object> Run(HttpRequestMessage req, TraceWriter log)
{
    var parametersReader = await CiqsInputParametersReader.FromHttpRequestMessage(req);
    string sqlServerName = parametersReader.GetParameter<string>("sqlServerName");
    string sqlServerUser = parametersReader.GetParameter<string>("sqlServerUser");
    string sqlServerPasswd = parametersReader.GetParameter<string>("sqlServerPasswd");
    string sqlDbName = parametersReader.GetParameter<string>("sqlDbName");
    string sqlScriptPath = parametersReader.GetParameter<string>("sqlScriptPath");
    string demandDataPath = parametersReader.GetParameter<string>("demandDataPath");
    int monthsBack = parametersReader.GetParameter<int>("forecastWindowMonthsBack");
    int monthsForward = parametersReader.GetParameter<int>("forecastWindowMonthsForward");

    const string historicalOrdersTableName = "FcastML.HistoricalOrders";
    const string refreshHistoricalOrderDatesProcName = "FcastETL.spRefreshHistoricalOrderDates";
    const string loadInitialForecastParametersProcName = "FcastETL.spLoadInitialForecastParameters";
    const string getEarliestHistoricalOrderDateProcName = "FcastETL.spGetEarliestHistoricalOrderDate";

    string sqlConnectionString = String.Format(
               "Data Source={0}.database.windows.net;Initial Catalog={1};Persist Security Info=False;User ID={2};Password={3};Connect Timeout=60;Encrypt=True;TrustServerCertificate=False",
               sqlServerName,
               sqlDbName,
               sqlServerUser,
               sqlServerPasswd);

    log.Info($"SQL Connection String: {sqlConnectionString}");

    DateTime nowTime = DateTime.UtcNow; //.ToString("s", CultureInfo.InvariantCulture);
    DateTime currentMonthStart = new DateTime(nowTime.Year, nowTime.Month, 1);
    DateTime startMonth = currentMonthStart.AddMonths(-1 * monthsBack);
    DateTime endMonth = currentMonthStart.AddMonths(monthsForward);

    // Create database objects
    log.Info("Creating database objects...");
    await executeSqlScript(sqlConnectionString, sqlScriptPath);

    // Load demand data to historical orders table
    log.Info("Loading demand data into HistoricalOrders table...");
    await loadDataToTable(sqlConnectionString, demandDataPath, historicalOrdersTableName);

    // Refresh dates in demand data
    log.Info("Refreshing historical demand dates...");
    await refreshHistoricalOrderDates(sqlConnectionString, refreshHistoricalOrderDatesProcName, endMonth.AddMonths(-1));

    // Get earliest date in demand data
    log.Info("Finding earliest date in demand...");
    DateTime earliestOrderHistoryDate = await getEarliestOrderHistoryDate(sqlConnectionString, getEarliestHistoricalOrderDateProcName);
    log.Info($"EarliestOrderHistoryDate: {earliestOrderHistoryDate}");

    // Load initial Forecast Parameters
    log.Info("Loading initial forecast parameters...");
    await loadInitialForecastParameters(sqlConnectionString, loadInitialForecastParametersProcName, earliestOrderHistoryDate,
                                        startMonth, endMonth.AddMonths(-1));

    return new
    {
        forecastWindowStart = startMonth.ToString("s", CultureInfo.InvariantCulture),
        forecastWindowEnd = endMonth.ToString("s", CultureInfo.InvariantCulture)
    };
}

private static async Task<int> executeSqlScript(string sqlConnectionString, string sqlScriptPath)
{
    Uri sqlScriptUri = new Uri(sqlScriptPath);
    int rowCount = 0;
    using (WebClient client = new WebClient())
    {
        string sqlScriptContent = client.DownloadString(sqlScriptUri);
        using (SqlConnection connection = new SqlConnection(sqlConnectionString))
        {
            var server = new Server(new ServerConnection(connection));
            rowCount = server.ConnectionContext.ExecuteNonQuery(sqlScriptContent);
        }
    }

    return (rowCount);
}  

private static async Task<int> loadDataToTable(string sqlConnectionString, string dataPath, string tableName)
{
    DataTable srcData = new DataTable();

    // Read BLOB content and load into the DataTable object
    using (WebClient client = new WebClient())
    {
        using (StreamReader sr = new StreamReader(client.OpenRead(dataPath)))
        {
            string[] columns = sr.ReadLine().Split(',');
            foreach (var col in columns)
            {
                srcData.Columns.Add(col);
            }

            while (!sr.EndOfStream)
            {
                DataRow newRow = srcData.NewRow();
                newRow.ItemArray = sr.ReadLine().Split(',');
                srcData.Rows.Add(newRow);
            }
        }
    }

    using (SqlConnection sqlConnection = new SqlConnection(sqlConnectionString))
    {
        sqlConnection.Open();
        using (SqlBulkCopy bcp = new SqlBulkCopy(sqlConnection))
        {
            bcp.DestinationTableName = tableName;
            bcp.WriteToServer(srcData); 
        }
    }

    return (srcData.Rows.Count);
}

private static async Task<DateTime> getEarliestOrderHistoryDate(string sqlConnectionString, string getEarliestHistoricalOrderDateProcName)
{
    

    using (SqlConnection sqlConnection = new SqlConnection(sqlConnectionString))
    {
        sqlConnection.Open();
        using (SqlCommand sqlCommand = new SqlCommand(getEarliestHistoricalOrderDateProcName, sqlConnection))
        {
            sqlCommand.CommandType = CommandType.StoredProcedure;
            return (DateTime)sqlCommand.ExecuteScalar();
        }
    }
}

private static async Task<int> refreshHistoricalOrderDates(string sqlConnectionString, string storedProcName, DateTime referenceMonth)
{
    int rowCount = 0;
    using (SqlConnection sqlConnection = new SqlConnection(sqlConnectionString))
    {
        sqlConnection.Open();
        using (SqlCommand sqlCommand = new SqlCommand(storedProcName, sqlConnection))
        {
            sqlCommand.CommandType = CommandType.StoredProcedure;
            sqlCommand.Parameters.Add("@ReferenceMonth", SqlDbType.Date).Value = referenceMonth.Date;
            rowCount = sqlCommand.ExecuteNonQuery();
        }
    }

    return (rowCount);
}

private static async Task<int> loadInitialForecastParameters(string sqlConnectionString, string storedProcName,
                                                             DateTime earliestOrderHistoryDate, DateTime startMonth, DateTime endMonth)
{
    int rowCount = 0;

    using (SqlConnection sqlConnection = new SqlConnection(sqlConnectionString))
    {
        sqlConnection.Open();
        using (SqlCommand sqlCommand = new SqlCommand(storedProcName, sqlConnection))
        {
            sqlCommand.CommandType = CommandType.StoredProcedure;
            sqlCommand.Parameters.Add("@EarliestOrderHistoryDate", SqlDbType.Date).Value = earliestOrderHistoryDate.Date;
            sqlCommand.Parameters.Add("@StartMonth", SqlDbType.Date).Value = startMonth.Date;
            sqlCommand.Parameters.Add("@EndMonth", SqlDbType.Date).Value = endMonth.Date;
            rowCount = sqlCommand.ExecuteNonQuery();
        }
    }

    return (rowCount);
}