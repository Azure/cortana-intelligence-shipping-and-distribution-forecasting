#r "Newtonsoft.Json"
#load "..\CiqsHelpers\All.csx"

using System;
using System.Globalization;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Net.Http;
using System.Net.Http.Headers;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Microsoft.Azure;

public static async Task<object> Run(HttpRequestMessage req, TraceWriter log)
{   
    var parametersReader = await CiqsInputParametersReader.FromHttpRequestMessage(req);

    string subscriptionId = parametersReader.GetParameter<string>("subscriptionId");
    string webServiceName = parametersReader.GetParameter<string>("webServiceName");
    string resourceGroupName = parametersReader.GetParameter<string>("resourceGroupName");
    string authorizationToken = parametersReader.GetParameter<string>("authorizationToken");
    string apiVersion = "2016-05-01-preview";

    string apiLocation = null;
    string primaryKey = null;
    var credentials = new TokenCloudCredentials(subscriptionId, authorizationToken);

    using (var client = new HttpClient())
    {
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", credentials.Token);
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        var getWebServiceKeys =
            string.Format(
                "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.MachineLearning/webServices/{2}/listkeys?api-version={3}",
                subscriptionId, resourceGroupName, webServiceName, apiVersion);

        var getWebServiceInfo =
            string.Format(
                "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.MachineLearning/webServices/{2}?api-version={3}",
                subscriptionId, resourceGroupName, webServiceName, apiVersion);

        try
        {
            log.Info("Getting web service information and API key...");

            var swaggerLocation = await GetWebServiceSwaggerLocation(client, getWebServiceInfo, log);
            log.Info($"Swagger location : {swaggerLocation}");
            if (!string.IsNullOrEmpty(swaggerLocation))
            {
                var prefix =
                    swaggerLocation.Remove(swaggerLocation.LastIndexOf("/swagger.json",
                        StringComparison.OrdinalIgnoreCase));
                prefix = prefix.TrimEnd('/');
                apiLocation = prefix;
            }
            log.Info($"API location: {apiLocation}");

            primaryKey = await GetWebServicePrimaryKey(client, getWebServiceKeys, log);
            log.Info($"Primary key : {primaryKey}");
        }
        catch (Exception ex)
        {
            log.Info($"Error: {ex.Message}");
            throw new Exception("Getting web service info and key failed", ex);
        }
    }

    return new {
        mLEndpointBatchLocation = String.Concat(apiLocation, "/jobs?api-version=2.0"),
        mLEndpointKey = primaryKey
    };        
}

private static async Task<string> GetWebServiceSwaggerLocation(HttpClient client, string getWebServiceInfo, TraceWriter log)
{
    string swaggerLocation = string.Empty;
    log.Info($"Calling get web service info: {getWebServiceInfo}");
    var response = await client.GetAsync(getWebServiceInfo);
    if (response.IsSuccessStatusCode)
    {
        string content = await response.Content.ReadAsStringAsync();
        dynamic jsonObj = JsonConvert.DeserializeObject(content);
        swaggerLocation = (string)jsonObj.properties.swaggerLocation;
    }
    else
    {
        string failureCode = response.StatusCode.ToString();
        string content = await response.Content.ReadAsStringAsync();
        log.Info($"Get ML web service info failed with errorcode: {failureCode}, Message: {content}");
    }
    return swaggerLocation;
}

private static async Task<string> GetWebServicePrimaryKey(HttpClient client, string getWebServiceKeys, TraceWriter log)
{
    string primaryKey = string.Empty;
    log.Info($"Calling get web service key: {getWebServiceKeys}");
    var response = await client.GetAsync(getWebServiceKeys);
    if (response.IsSuccessStatusCode)
    {
        string content = await response.Content.ReadAsStringAsync();
        dynamic jsonObj = JsonConvert.DeserializeObject(content);
        primaryKey = (string)jsonObj.primary;
    }
    else
    {
        string failureCode = response.StatusCode.ToString();
        string content = await response.Content.ReadAsStringAsync();
        log.Info($"Get ML web service key failed with errorcode: {failureCode}, Message: {content}");
    }
    return primaryKey;
}
