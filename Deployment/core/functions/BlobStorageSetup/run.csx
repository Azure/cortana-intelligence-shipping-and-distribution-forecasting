#load "..\CiqsHelpers\All.csx"

using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using Microsoft.WindowsAzure.Storage;
using Microsoft.WindowsAzure.Storage.Auth;
using Microsoft.WindowsAzure.Storage.Blob;

public static async Task<object> Run(HttpRequestMessage req, TraceWriter log)
{   
    var parametersReader = await CiqsInputParametersReader.FromHttpRequestMessage(req);

    string storageAccountName = parametersReader.GetParameter<string>("storageAccountName");
    string storageAccountKey = parametersReader.GetParameter<string>("storageAccountKey");
    string amlModulePath = parametersReader.GetParameter<string>("amlModulePath"); 
    string amlModuleContainerName = parametersReader.GetParameter<string>("amlModuleContainerName");
    string adfContainerName = parametersReader.GetParameter<string>("adfContainerName");

    var storageCredentials = new StorageCredentials(storageAccountName, storageAccountKey);
    var storageAccount = new CloudStorageAccount(storageCredentials, true);
    var storageClient = storageAccount.CreateCloudBlobClient();

    // Create container for ADF intermediate storage
    var adfContainer = storageClient.GetContainerReference(adfContainerName);
    adfContainer.CreateIfNotExists(BlobContainerPublicAccessType.Off);
    log.Info($"Created ADF container {adfContainerName}");

    // Create container for AML Module Storage
    var amlModuleContainer = storageClient.GetContainerReference(amlModuleContainerName);
    amlModuleContainer.CreateIfNotExists(BlobContainerPublicAccessType.Off);
    log.Info($"Created module container {amlModuleContainerName}");

    // Copy module file to blob container
    Uri amlModuleSrcUri = new Uri(amlModulePath);        
    string blobName = Path.GetFileName(amlModuleSrcUri.LocalPath);

    log.Info($"Copying {amlModulePath} as {blobName}");
    CloudBlockBlob target = amlModuleContainer.GetBlockBlobReference(blobName);
    target.StartCopy(amlModuleSrcUri);

    while (target.CopyState.Status == CopyStatus.Pending)
    {
        target.FetchAttributes();
        Thread.Sleep(500);
    }

    if (target.CopyState.Status == CopyStatus.Success) 
    {
        log.Info($"Done copying {amlModulePath} as {blobName}");
    }
    else
    {            
        throw new Exception($"Error copying {amlModulePath} as {blobName}");
    }

    return new {
        amlModuleContainerName = amlModuleContainerName,
        adfContainerName = adfContainerName,
        amlModuleUri = target.Uri.ToString()
    };        
}
