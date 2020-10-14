#Script to set threshold values for monitoring components
#region Parameters
Param(
#Resource Group where resources are located - if need to filter to a specifc RG instead of the complete subscription
    [Parameter(Mandatory=$false)]
    $rgazresources,

#Resource type - if need to filter to a specific resource type instead of running for all resource types
    [Parameter(Mandatory=$false)]
    $azrestype,

#Location of CSV and parameter.json files
    [Parameter(Mandatory=$true)]
    $fileslocation,

#Mandatory - Resource Group where the action group is located
    [Parameter(Mandatory=$true)]
    $rgactiongroup,

#Mandatory - Action Group name
    [Parameter(Mandatory=$true)]
    $actiongroupname
)
#endregion Parameters

#Import CSV file list of Azure Monitor and filter to the ones enable for monitoring
#List availble at https://docs.microsoft.com/en-us/azure/azure-monitor/platform/metrics-supported
$csvpath = "$psscriptroot\$fileslocation\azure_monitoring.csv"
$azuremonitor = Import-Csv $csvpath | Where-Object {$_.'Enable for monitoring' -eq 'yes'}

#Define default behavior when error occurs
$erroractionpreference = [System.Management.Automation.ActionPreference]::Stop

#region ActionGroup
#Get action group
Try
{
    $alertgroup = Get-AzActionGroup -ResourceGroupName $rgactiongroup -Name $actiongroupname
    $actiongroupid = $alertgroup.Id
}
Catch
{
    Write-Host "The action group you have defined has not been found" -ForegroundColor Red -BackgroundColor Black
    Throw
}
#endregion Action Group

#region Checks
#Checking if resource types have been enabled for monitoring
If($azuremonitor.count -eq 0)
{
    Write-Host "No resource types have been enabled for monitoring. Please update the CSV file." -ForegroundColor Red -BackgroundColor Black
    Throw
}
#Checking if the resource group defined in parameter is found or if the resouce type defined is enabled for monitoring
If (($rgazresources) -or ($azrestype))
{
    Try
    {
        Get-AzResourceGroup -Name $rgazresources
    }
    Catch
    {
        Write-Host "The resource group you have defined in the parameter is not found" -ForegroundColor Red -BackgroundColor Black
        Throw
    }

    #Checking if the resource type defined in parameter is enabled for monitoring in the CSV
    If ($azuremonitor -match $azrestype)
    {

    }
    Else
    {
        Write-Host "The resource type you have defined in the parameter is not enabled for monitoring" -ForegroundColor Red -BackgroundColor Black
        Throw
    }
}
#endregion Checks

#Create array of Azure resource type to monitor
$azrestypemonitoring = @()
ForEach ($csvrow in $azuremonitor)
{
    $aztype = $csvrow.'Resource Type'
    $azrestypemonitoring = $azrestypemonitoring + $aztype
}
#Get unique resource type
$azrestypemonitoring = $azrestypemonitoring | Select-Object -Unique

#region GetResources
#If no paramaters provided
If ((!$rgazresources) -and (!$azrestype))
{
#If no resource group specified, get all resources accross the subscription
    Write-Host "Setting alert for all resources type enabled for monitoring in the source CSV for the entire subscription" -ForegroundColor Green -BackgroundColor Black
    Try
    {
        $azresources = Get-AzResource | Where {$_.ResourceType -in $azrestypemonitoring} | Select-Object -Property ResourceId,Name,ResourceType,Tags,ResourceGroupName
    }
    Catch
    {
        $_.Exception.Message
    }
}
#if resource type parameter provided, check if the resource type is listed for monitoring
If ($azrestype)
{
    If ($azrestypemonitoring -match $azrestype)
    {
        Write-Host "Resource type" $azrestype "enabled for monitoring"
        $threshold = $azresource.Tags.$aztagname
    }
    Else
    {
        Write-Host "Resource type" $azrestype "not enabled for monitoring. Please change your paramater or CSV file to enable monitoring." -ForegroundColor Red -BackgroundColor Black
        Exit
    }
}
#If both resource group and resoure type parameters provided
If (($rgazresources) -and ($azrestype))
{
    Write-Host "Setting alert for specific resource type $azrestype within a specific resource group $rgazresources" -ForegroundColor Green -BackgroundColor Black
    Try
    {
        $azresources = Get-AzResource -ResourceGroupName $rgazresources -ResourceType $azrestype | Where {$_.ResourceType -in $azrestypemonitoring} | Select-Object -Property ResourceId,Name,ResourceType,Tags,ResourceGroupName
    }
    Catch
    {
        $_.Exception.Message
    }
}
#If only resource type parameter provided
If ($azrestype)
{
    Write-Host "Setting alert for specific resource type for the entire subscription" -ForegroundColor Green -BackgroundColor Black
    Try
    {
        $azresources = Get-AzResource -ResourceType $azrestype | Where {$_.ResourceType -in $azrestypemonitoring} | Select-Object -Property ResourceId,Name,ResourceType,Tags,ResourceGroupName
    }
    Catch
    {
        $_.Exception.Message
    }
}

#If only resource group paramaeter provided
If ($rgazresources)
{
    Write-Host "Setting alert for all  resource type within a specific resource group $rgazresources" -ForegroundColor Green -BackgroundColor Black
    Try
    {
        $azresources = Get-AzResource -ResourceGroupName $rgazresources | Where {$_.ResourceType -in $azrestypemonitoring} | Select-Object -Property ResourceId,Name,ResourceType,Tags,ResourceGroupName
    }
    Catch
    {
        $_.Exception.Message
    }
}
#endregion GetResources

ForEach ($azresource in $azresources)
{
    Write-Host "Creating Metric for" $azresource.ResourceType -ForegroundColor Green -BackgroundColor Black

    $azresourceid = $azresource.ResourceId
    $azresourcename = $azresource.Name
    $azresourcetype = $azresource.ResourceType
    $azresourcetags = $azresource.Tags
    $azresourcetagskeys = $azresource.Tags.Keys
    $azresourcergname = $azresource.ResourceGroupName

#Get monitor settings for the current azure resource type
    $azmonitorscsv = $azuremonitor | Where-Object {$_.'Resource Type' -eq $azresourcetype}

#Lookup for the tag name for monitoring
    ForEach ($azmonitorcsv in $azmonitorscsv)
    {
#If the tag key does not exist set the value to value from CSV
        $aztagname = $azmonitorcsv.'Tag Name'
        If (($azresourcetagskeys -match $aztagname) -and ($aztagname))
        {
           Write-Host "Tag" $aztagname "found for resource" $azresourcename  -ForegroundColor Green -BackgroundColor Black
           $threshold = $azresource.Tags.$aztagname
        }
        Else
        {
            $threshold = $azmonitorcsv.Threshold
        }

#Set alert desciption
        If (!($azmonitorcsv.'Alert Description'))
        {
            $alertdescription = $azmonitorcsv.Description
        }
        Else
        {
            $alertdescription = $azmonitorcsv.'Alert Description'
        }

        $metricname = $azmonitorcsv.Metric
        $alertname = $azresourcename + '-' + $metricname
#Remove / character
        If ($alertname -like '*/*')
        {
            $alertname = $alertname -replace ('/','-')
        }

#Generate parameters files depending of the resource type
#SQL Databases
        If($azresource.ResourceType -eq "Microsoft.Sql/servers/databases")
        {
#JSON template file
            $templatefilepath = "$psscriptroot\sqldb_template.json"
#JSON parameters file
            $parametersfilepath = "$psscriptroot\$fileslocation\parameters_sql.json"
        }
        Else
#Storage account, virtual machines, web apps
        {
#JSON template file
            $templatefilepath = "$psscriptroot\template.json"
#JSON parameters file
            $parametersfilepath = "$psscriptroot\$fileslocation\parameters.json"
        }

#Parameters
            $paramfile = Get-Content $parametersfilepath -Raw | ConvertFrom-Json
            $paramfile.parameters.alertName.value = $alertname
            $paramfile.parameters.alertDescription.value = $alertdescription
            $paramfile.parameters.metricName.value = $metricname
            $paramfile.parameters.metricNamespace.value = ($azmonitorcsv.'Resource Type')
            $paramfile.parameters.resourceId.value = $azresourceid
            $paramfile.parameters.threshold.value = $threshold
            $paramfile.parameters.actionGroupId.value = $actiongroupid
            $paramfile.parameters.timeAggregation.value = $azmonitorcsv.'Aggregation Time'
            $paramfile.parameters.operator.value = $azmonitorcsv.Operator
            $paramfile.parameters.alertSeverity.value = [int]($azmonitorcsv.Severity)
            $paramfile.parameters.evaluationFrequency.value = $azmonitorcsv.'Eval Frequency'
            $paramfile.parameters.windowSize.value = $azmonitorcsv.'Window Size'

#Update parameters file JSON
        $updatedjson = $paramfile | ConvertTo-Json
        $updatedjson > $parametersfilepath

#Deploy monitoring
        $deploymentname = $alertname
#Esnure deployment name is supported
#Remove space
#Remove space
        If ($deploymentname -like '* *')
        {
            $deploymentname = $deploymentname -replace (' ','-')
        }
#Remove / character
        If ($deploymentname -like '*/*')
        {
            $deploymentname = $deploymentname -replace ('/','-')
        }
#Ensure deployment name is shorter than 64 characters
        If ($deploymentname.Length -ge 64)
        {
            $deploymentname = $deploymentname.Substring(0,64) 
        }

        Write-Host "Deploy monitoring alert" $azmonitorcsv.'Metric Display Name' "on resource" $azresourcename "with threshold value set to" $threshold -ForegroundColor Green -BackgroundColor Black
        New-AzResourceGroupDeployment -Name $deploymentname -ResourceGroupName $azresourcergname -TemplateFile $templatefilepath -TemplateParameterFile $parametersfilepath
    }
}

