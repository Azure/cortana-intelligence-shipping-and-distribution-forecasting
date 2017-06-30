#load "..\CiqsHelpers\All.csx"

using System.IO;
using System.Threading;
using System;
using System.Net;
using System.Configuration;
using Microsoft.Azure;
using Microsoft.Azure.Management.DataFactories.Common.Models;
using Microsoft.Azure.Management.DataFactories.Core;

public static async Task<object> Run(HttpRequestMessage req, TraceWriter log)
{   
    var parametersReader = await CiqsInputParametersReader.FromHttpRequestMessage(req);

    string[] pipelineNames = { "ReadSliceForecastParameters", "GenerateForecasts", "CopyToSql" };

    const string ResourceManagerEndpoint = "https://management.azure.com/";
    string subscriptionId = parametersReader.GetParameter<string>("subscriptionId");
    string dataFactoryName = parametersReader.GetParameter<string>("dataFactoryName");
    string resourceGroupName =parametersReader.GetParameter<string>("resourceGroupName");
    string authorizationToken =parametersReader.GetParameter<string>("authorizationToken");
    string pipelineStartDate = parametersReader.GetParameter<string>("pipelineStartDate");
    string pipelineEndDate = parametersReader.GetParameter<string>("pipelineEndDate");

    var dfClient = new DataFactoryManagementClient(new TokenCloudCredentials(subscriptionId, authorizationToken),
                                                   new Uri(ResourceManagerEndpoint));
    log.Info($"dfClient: {dfClient.ToString()}");

    foreach (string pname in pipelineNames)
    {
        // Activate the pipeline
        dfClient.Pipelines.SetActivePeriod(resourceGroupName,
                                           dataFactoryName,
                                           pname,
                                           new PipelineSetActivePeriodParameters(pipelineStartDate, pipelineEndDate));

        dfClient.Pipelines.Resume(resourceGroupName,
                                  dataFactoryName,
                                  pname);
    }

    return new {
        started = true
    };        
}
