<#
 
.SYNOPSIS
This script effectively forces a re-run of all demand forecast Data Factory pipelines for all slices in the active period
 
.DESCRIPTION
The script sets the requested slice to 'Waiting' status for a selection of the datasets in the Data Factory.
The script must be provided an active Azure subscription ID, a Resource Group name, 
and the name of the Data Factory. 

Requires Azure Powershell: https://www.microsoft.com/web/handlers/webpi.ashx/getinstaller/WindowsAzurePowershellGet.3f.3f.3fnew.appids 

#>

param(
[Parameter(Mandatory=$true,Position=1)]
[string] $SubscriptionId,

[Parameter(Mandatory=$true,Position=2)]
[string] $ResourceGroupName,

[Parameter(Mandatory=$true,Position=3)]
[string] $DataFactoryName
)

$CopyToSqlPipelineName = "CopyToSql"
$ForecastBlobName="ForecastHistoryBlob"
$ForecastParametersBlob = "ForecastParametersBlob"
$ForecastSqlName = "ForecastHistorySql"

$defaultContext = Get-AzureRmContext
try {
	Write-Host "Trying to set context to requested subscription..."
    Set-AzureRmContext -SubscriptionId $SubscriptionId -ErrorAction Stop
} catch {
	Write-Host "Subscription not found. Let's try logging into your account..."
    $profile = Login-AzureRmAccount
	$defaultContext = Get-AzureRmContext
	Write-Host "Available subscriptions:"
	Get-AzureRmSubscription
	Write-Host "Setting context to requested subscription..."
	Set-AzureRmContext -SubscriptionId $SubscriptionId -ErrorAction Stop
}

Write-Host "Finding Data Factory..."
$df = Get-AzureRmDataFactory -ResourceGroupName $ResourceGroupName -Name $DataFactoryName -ErrorAction Stop

# Get the pipeline active dates
Write-Host "Resetting Slices..."
$pl = Get-AzureRmDataFactoryPipeline $df -Name $CopyToSqlPipelineName
$StartDate = $pl.Properties.Start
$EndDate = $pl.Properties.End

$success = Set-AzureRmDataFactorySliceStatus $df -DatasetName $ForecastParametersBlob -StartDateTime $StartDate -EndDateTime $EndDate -Status Waiting -UpdateType Individual
if($success -ne $true) {
	Write-Host "Set slice status failed for",$ForecastParametersBlob
}

$success = Set-AzureRmDataFactorySliceStatus $df -DatasetName $ForecastSqlName -StartDateTime $StartDate -EndDateTime $EndDate -Status Waiting -UpdateType UpstreamInPipeline
if($success -ne $true) {
	Write-Host "Set slice status failed for",$ForecastSqlName
}

Write-Host ""
Write-Host "Setting context back to default"
Set-AzureRmContext -Context $defaultContext

