<#
 
.SYNOPSIS
This script effectively forces a re-run of all demand forecast Data Factory pipelines for all slices in the active period
 
.DESCRIPTION
The script sets the requested slice to 'Waiting' status for a selection of the datasets in the Data Factory.
The script must be provided an active Azure subscription ID, a Resource Group name, 
and the name of the Data Factory. 

#>

param(
[string] $SubscriptionId,
[string] $ResourceGroupName,
[string] $DataFactoryName
)

$CopyToSqlPipelineName = "CopyToSql"
$ForecastBlobName="ForecastHistoryBlob"
$ForecastParametersBlob = "ForecastParametersBlob"
$ForecastSqlName="ForecastHistorySql"

Write-Host "Checking Azure subscription..."
try {
    $subs = Get-AzureRmSubscription | where Id -eq $SubscriptionId
	if(-not $subs) {
		throw "Azure subscription not found."
	}

} catch {
    Login-AzureRmAccount
    $subs = Get-AzureRmSubscription
    if(-not $subs) {
        throw "Error listing subscription"
    }
}

$initialSub = Get-AzureRmContext
$inputSub = $subs | where Id -eq $SubscriptionId
if(-not $inputSub) {
    throw "Unable to find subscription with ID",$SubscriptionId
}
$curSub = $inputSub | Select-AzureRmSubscription
Write-Host "Set context to",$curSub.Subscription.Name

Write-Host "Finding Data Factory..."
$df = Get-AzureRmDataFactory -ResourceGroupName $ResourceGroupName -Name $DataFactoryName
if(-not $df) {
	throw "Could not find Data Factory",$DataFactoryName,"in Resource Group",$ResourceGroupName
}

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

$curSub = $initialSub | Select-AzureRmSubscription
Write-Host "Set context back to",$curSub.Subscription.Name

