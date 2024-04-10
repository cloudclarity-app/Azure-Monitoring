<#
.SYNOPSIS
    Enable Azure monitoring capabilities on resources and metrics available for monitoring.

.DESCRIPTION
    This script will automatically enable Azure monitoring based on CSV input defining which resources and metrics to use for monitoring, including metrics settings
    Threshold values defined in the CSV file define the default value for monitoring while the tagname identifies exception.
    When a resource with the tag name defined is identified, the threshold value defined for the monitoring will be set based on the tag value.
    By default, the monitoring scope is set to the subscription but it can be filtered by defining either a resource group, resource type or both.
    An Azure monitoring action group must be created as a prerequisites (see https://docs.microsoft.com/en-us/azure/azure-monitor/platform/action-groups).

.PARAMETER rgazresources
    Specify the Azure resource group where the resources to be monitoring are located; used only to limit the scope of execution

.PARAMETER azrestype
    Specify the Azure resource type to be monitoring are located; used only to limit the scope of execution

.PARAMETER fileslocation
    Specify the location of the input CSV file use to enable and set monitoring thresholds

.PARAMETER rgactiongroup
    Specify the Azure resource group where the Azure monitoring action group is located

.PARAMETER actiongroupname
    Specify the Azure action group to execute when monitoring threshold is fired

.NOTES
    FileName:    azuremonitoring.ps1
    Author:      Benoit HAMET - cubesys
    Amended By:  David COOK - cubesys
    Contact:     info@tagmanager.app
    Created:     2020-10-01
    Updated:     2023-03-07

    Version history:
    1.0.0 - (2020-10-01) - Script created
    1.0.1 - (2020-10-12) - Fixing issue for Azure SQL Database monitoring; different version of template and schema
    1.0.2 - (2020-11-27) - Code signing
    1.0.3 - (2020-11-30) - Rename template and parameters files matching the schema version instead; update monitoring CSV to pre populate additional values for metrics thresholds
    1.0.4 - (2023-03-07) - Added input for alert name from the csv to distinguish alert names for using multiple alerts for a single metric
    1.0.5 - (2023-03-07) - Code signing
#>

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

# Complete a clean of Azure Alert Rules where there is no valid scope item associated

# Get all alert rules
$alertRules = Get-AzMetricAlertRuleV2

# Iterate through each alert rule
foreach ($rule in $alertRules) {
    $resourceId = $rule.Scopes[0]  # Assuming each alert rule has only one scope
    try {
        # Validate if the monitored resource exists
        $resource = Get-AzResource -ResourceId $resourceId -ErrorAction Stop
        Write-Output "Resource $resourceId exists. Alert rule $($rule.Name) is valid." -ForegroundColor Green -BackgroundColor Black
    }
    catch {
        # If the resource does not exist, delete the alert rule
        Write-Warning "Resource $resourceId does not exist. Deleting alert rule $($rule.Name)..." -ForegroundColor Red -BackgroundColor Black
        Remove-AzMetricAlertRuleV2 -ResourceGroupName $rule.resourceGroup -Name $rule.Name
        Write-Output "Alert rule $($rule.Name) deleted successfully." -ForegroundColor Yellow -BackgroundColor Black
    }
}

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
#Set alert name
        If ($azmonitorcsv.'Alert Name' -eq "")
        {
            $alertname = $azresourcename + '-' + $metricname
        }
        Else
        {
            $alertname = $azresourcename + '-' + $azmonitorcsv.'Alert Name'
        }
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
            $templatefilepath = "$psscriptroot\template_2015-01-01.json"
#JSON parameters file
            $parametersfilepath = "$psscriptroot\$fileslocation\parameters_2015-01-01.json"
        }
        Else
#Storage account, virtual machines, web apps
        {
#JSON template file
            $templatefilepath = "$psscriptroot\template_2019-04-01.json"
#JSON parameters file
            $parametersfilepath = "$psscriptroot\$fileslocation\parameters_2019-04-01.json"
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


# SIG # Begin signature block
# MIIm9gYJKoZIhvcNAQcCoIIm5zCCJuMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA2O4jLLcH0aAqz
# opdhhh7Z3ElTbJzvr7eRipIyUnogFaCCELwwggU6MIIEIqADAgECAhEAwCQYKSXq
# uCizIo6EVaFfXjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJHQjEbMBkGA1UE
# CBMSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHEwdTYWxmb3JkMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxJDAiBgNVBAMTG1NlY3RpZ28gUlNBIENvZGUgU2ln
# bmluZyBDQTAeFw0yMDExMjAwMDAwMDBaFw0yMzExMjAyMzU5NTlaMH4xCzAJBgNV
# BAYTAkFVMQ0wCwYDVQQRDAQyMDAwMQ8wDQYDVQQHDAZTeWRuZXkxGzAZBgNVBAkM
# EkxldmVsIDIvNDQgUGl0dCBTdDEYMBYGA1UECgwPQ1VCRVNZUyBQVFkgTFREMRgw
# FgYDVQQDDA9DVUJFU1lTIFBUWSBMVEQwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
# ggEKAoIBAQCh3pOAc3MZobI7AJ5hhXEiTeAg/YDgMfyLJU1fp/wAaddnlvlKAOdg
# tvjf95gOBIiIOrFE+Bh1fufmrq/EH/itYps1NZJuwgmeRHHsCNLd3V6uoJEA5C9Y
# 6oYveQR2sv992S+UgNno9yrcaKdoJ7q6kLei1JpKiZACo2W3O6a8I3qWnU12a9A6
# PGdy21SdwWZoAE6oWBo7vyL3kgX+GwTPZPIC8zrWp740Sb1KeYXSNOTAZhDb5w1s
# VXvfiu86yjE4nSFcOc0iCOtuPNascCfmaTgbRnzIszmQvr1Y2fzvfQQYF74X4czn
# z08mAOLFZFdIn3sl/8KFBrMKmLDzpd5BAgMBAAGjggGzMIIBrzAfBgNVHSMEGDAW
# gBQO4TqoUzox1Yq+wbutZxoDha00DjAdBgNVHQ4EFgQU5u/gxB0H0dQkB3nwbGco
# xuLCB0wwDgYDVR0PAQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYI
# KwYBBQUHAwMwEQYJYIZIAYb4QgEBBAQDAgQQMEoGA1UdIARDMEEwNQYMKwYBBAGy
# MQECAQMCMCUwIwYIKwYBBQUHAgEWF2h0dHBzOi8vc2VjdGlnby5jb20vQ1BTMAgG
# BmeBDAEEATBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsLnNlY3RpZ28uY29t
# L1NlY3RpZ29SU0FDb2RlU2lnbmluZ0NBLmNybDBzBggrBgEFBQcBAQRnMGUwPgYI
# KwYBBQUHMAKGMmh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1JTQUNvZGVT
# aWduaW5nQ0EuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNv
# bTAhBgNVHREEGjAYgRZzdXBwb3J0QGN1YmVzeXMuY29tLmF1MA0GCSqGSIb3DQEB
# CwUAA4IBAQAmAa7338I1uXFQ5Xd+Tudn7e8mChInn28mVvxmF0FhmZcaJxS6KLpb
# nKj9WUKVeAGTJ0geW9/oeMThIprs19wrXBT0+QfT2FQ5+SFMBhiaxYCUF9LgKU2w
# hNHLvLh+BePlwkOeQHMBzVSQzcYaLaIt9UbF4ADObgExIhzAU2go8DdA6JZlW3vR
# 0/R5CPssuXiUHou0fAZ9twM2rgZXWVj7TiWE8BXiyU3snysOLb4d4rzc/giZppIi
# e6MXj2+Des8jjRL4m70NCk8O2xBtdrjYIXp2YWUnLWk/smHOvBLVIxYE3InjEks9
# WlpXYsfCUhwlALK19jIU7u1rMNAaZN0LMIIFgTCCBGmgAwIBAgIQOXJEOvkit1HX
# 02wQ3TE1lTANBgkqhkiG9w0BAQwFADB7MQswCQYDVQQGEwJHQjEbMBkGA1UECAwS
# R3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHDAdTYWxmb3JkMRowGAYDVQQKDBFD
# b21vZG8gQ0EgTGltaXRlZDEhMB8GA1UEAwwYQUFBIENlcnRpZmljYXRlIFNlcnZp
# Y2VzMB4XDTE5MDMxMjAwMDAwMFoXDTI4MTIzMTIzNTk1OVowgYgxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpOZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEe
# MBwGA1UEChMVVGhlIFVTRVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1
# c3QgUlNBIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MIICIjANBgkqhkiG9w0BAQEF
# AAOCAg8AMIICCgKCAgEAgBJlFzYOw9sIs9CsVw127c0n00ytUINh4qogTQktZAnc
# zomfzD2p7PbPwdzx07HWezcoEStH2jnGvDoZtF+mvX2do2NCtnbyqTsrkfjib9Ds
# FiCQCT7i6HTJGLSR1GJk23+jBvGIGGqQIjy8/hPwhxR79uQfjtTkUcYRZ0YIUcuG
# FFQ/vDP+fmyc/xadGL1RjjWmp2bIcmfbIWax1Jt4A8BQOujM8Ny8nkz+rwWWNR9X
# Wrf/zvk9tyy29lTdyOcSOk2uTIq3XJq0tyA9yn8iNK5+O2hmAUTnAU5GU5szYPeU
# vlM3kHND8zLDU+/bqv50TmnHa4xgk97Exwzf4TKuzJM7UXiVZ4vuPVb+DNBpDxsP
# 8yUmazNt925H+nND5X4OpWaxKXwyhGNVicQNwZNUMBkTrNN9N6frXTpsNVzbQdcS
# 2qlJC9/YgIoJk2KOtWbPJYjNhLixP6Q5D9kCnusSTJV882sFqV4Wg8y4Z+LoE53M
# W4LTTLPtW//e5XOsIzstAL81VXQJSdhJWBp/kjbmUZIO8yZ9HE0XvMnsQybQv0Ff
# QKlERPSZ51eHnlAfV1SoPv10Yy+xUGUJ5lhCLkMaTLTwJUdZ+gQek9QmRkpQgbLe
# vni3/GcV4clXhB4PY9bpYrrWX1Uu6lzGKAgEJTm4Diup8kyXHAc/DVL17e8vgg8C
# AwEAAaOB8jCB7zAfBgNVHSMEGDAWgBSgEQojPpbxB+zirynvgqV/0DCktDAdBgNV
# HQ4EFgQUU3m/WqorSs9UgOHYm8Cd8rIDZsswDgYDVR0PAQH/BAQDAgGGMA8GA1Ud
# EwEB/wQFMAMBAf8wEQYDVR0gBAowCDAGBgRVHSAAMEMGA1UdHwQ8MDowOKA2oDSG
# Mmh0dHA6Ly9jcmwuY29tb2RvY2EuY29tL0FBQUNlcnRpZmljYXRlU2VydmljZXMu
# Y3JsMDQGCCsGAQUFBwEBBCgwJjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuY29t
# b2RvY2EuY29tMA0GCSqGSIb3DQEBDAUAA4IBAQAYh1HcdCE9nIrgJ7cz0C7M7PDm
# y14R3iJvm3WOnnL+5Nb+qh+cli3vA0p+rvSNb3I8QzvAP+u431yqqcau8vzY7qN7
# Q/aGNnwU4M309z/+3ri0ivCRlv79Q2R+/czSAaF9ffgZGclCKxO/WIu6pKJmBHaI
# kU4MiRTOok3JMrO66BQavHHxW/BBC5gACiIDEOUMsfnNkjcZ7Tvx5Dq2+UUTJnWv
# u6rvP3t3O9LEApE9GQDTF1w52z97GA1FzZOFli9d31kWTz9RvdVFGD/tSo7oBmF0
# Ixa1DVBzJ0RHfxBdiSprhTEUxOipakyAvGp4z7h/jnZymQyd/teRCBaho1+VMIIF
# 9TCCA92gAwIBAgIQHaJIMG+bJhjQguCWfTPTajANBgkqhkiG9w0BAQwFADCBiDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNl
# eSBDaXR5MR4wHAYDVQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMT
# JVVTRVJUcnVzdCBSU0EgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTgxMTAy
# MDAwMDAwWhcNMzAxMjMxMjM1OTU5WjB8MQswCQYDVQQGEwJHQjEbMBkGA1UECBMS
# R3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHEwdTYWxmb3JkMRgwFgYDVQQKEw9T
# ZWN0aWdvIExpbWl0ZWQxJDAiBgNVBAMTG1NlY3RpZ28gUlNBIENvZGUgU2lnbmlu
# ZyBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAIYijTKFehifSfCW
# L2MIHi3cfJ8Uz+MmtiVmKUCGVEZ0MWLFEO2yhyemmcuVMMBW9aR1xqkOUGKlUZEQ
# auBLYq798PgYrKf/7i4zIPoMGYmobHutAMNhodxpZW0fbieW15dRhqb0J+V8aouV
# Hltg1X7XFpKcAC9o95ftanK+ODtj3o+/bkxBXRIgCFnoOc2P0tbPBrRXBbZOoT5X
# ax+YvMRi1hsLjcdmG0qfnYHEckC14l/vC0X/o84Xpi1VsLewvFRqnbyNVlPG8Lp5
# UEks9wO5/i9lNfIi6iwHr0bZ+UYc3Ix8cSjz/qfGFN1VkW6KEQ3fBiSVfQ+noXw6
# 2oY1YdMCAwEAAaOCAWQwggFgMB8GA1UdIwQYMBaAFFN5v1qqK0rPVIDh2JvAnfKy
# A2bLMB0GA1UdDgQWBBQO4TqoUzox1Yq+wbutZxoDha00DjAOBgNVHQ8BAf8EBAMC
# AYYwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHSUEFjAUBggrBgEFBQcDAwYIKwYB
# BQUHAwgwEQYDVR0gBAowCDAGBgRVHSAAMFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6
# Ly9jcmwudXNlcnRydXN0LmNvbS9VU0VSVHJ1c3RSU0FDZXJ0aWZpY2F0aW9uQXV0
# aG9yaXR5LmNybDB2BggrBgEFBQcBAQRqMGgwPwYIKwYBBQUHMAKGM2h0dHA6Ly9j
# cnQudXNlcnRydXN0LmNvbS9VU0VSVHJ1c3RSU0FBZGRUcnVzdENBLmNydDAlBggr
# BgEFBQcwAYYZaHR0cDovL29jc3AudXNlcnRydXN0LmNvbTANBgkqhkiG9w0BAQwF
# AAOCAgEATWNQ7Uc0SmGk295qKoyb8QAAHh1iezrXMsL2s+Bjs/thAIiaG20QBwRP
# vrjqiXgi6w9G7PNGXkBGiRL0C3danCpBOvzW9Ovn9xWVM8Ohgyi33i/klPeFM4Mt
# SkBIv5rCT0qxjyT0s4E307dksKYjalloUkJf/wTr4XRleQj1qZPea3FAmZa6ePG5
# yOLDCBaxq2NayBWAbXReSnV+pbjDbLXP30p5h1zHQE1jNfYw08+1Cg4LBH+gS667
# o6XQhACTPlNdNKUANWlsvp8gJRANGftQkGG+OY96jk32nw4e/gdREmaDJhlIlc5K
# ycF/8zoFm/lv34h/wCOe0h5DekUxwZxNqfBZslkZ6GqNKQQCd3xLS81wvjqyVVp4
# Pry7bwMQJXcVNIr5NsxDkuS6T/FikyglVyn7URnHoSVAaoRXxrKdsbwcCtp8Z359
# LukoTBh+xHsxQXGaSynsCz1XUNLK3f2eBVHlRHjdAd6xdZgNVCT98E7j4viDvXK6
# yz067vBeF5Jobchh+abxKgoLpbn0nu6YMgWFnuv5gynTxix9vTp3Los3QqBqgu07
# SqqUEKThDfgXxbZaeTMYkuO1dfih6Y4KJR7kHvGfWocj/5+kUZ77OYARzdu1xKeo
# gG/lU9Tg46LC0lsa+jImLWpXcBw8pFguo/NbSwfcMlnzh6cabVgxghWQMIIVjAIB
# ATCBkTB8MQswCQYDVQQGEwJHQjEbMBkGA1UECBMSR3JlYXRlciBNYW5jaGVzdGVy
# MRAwDgYDVQQHEwdTYWxmb3JkMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxJDAi
# BgNVBAMTG1NlY3RpZ28gUlNBIENvZGUgU2lnbmluZyBDQQIRAMAkGCkl6rgosyKO
# hFWhX14wDQYJYIZIAWUDBAIBBQCgfDAQBgorBgEEAYI3AgEMMQIwADAZBgkqhkiG
# 9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIB
# FTAvBgkqhkiG9w0BCQQxIgQgl/izC/UtB37yU6Uy3gSjwEj8stq5pW7gczps83vN
# 4u0wDQYJKoZIhvcNAQEBBQAEggEAhzgw85NLSY5hxosZf4hH1BBzVJ39V6H+QwGO
# vjuWdIuFbdN0x7i2ECmFvqnFM/SYPKjFWk9b51+umgEGwYWI7zUJWXuq5CoV0cS7
# qlQ796m1SDQjrhWqA3UbtxWARgoXhfjwYtmyEoZUFUceHHH8Ctb9NEvp7Xn6LErR
# huvXVQsmTJGBqotK95AwLegnrstEcuFLXQMvLy7Wc9LMsuhJXqA1wkuiO0zWG/jj
# MKJ8RSxhb0w6KAHpJh1SN3IUNm9ppgERlphE/jHIZBNfn+ODj4Gq6CKuVgpj625w
# PwQxaFAeqW/lGzBS89JVJZZffLXM9bnInrSueXekPGtf9gqDp6GCE1EwghNNBgor
# BgEEAYI3AwMBMYITPTCCEzkGCSqGSIb3DQEHAqCCEyowghMmAgEDMQ8wDQYJYIZI
# AWUDBAICBQAwgfAGCyqGSIb3DQEJEAEEoIHgBIHdMIHaAgEBBgorBgEEAbIxAgEB
# MDEwDQYJYIZIAWUDBAIBBQAEIENImgV64zbNe1krkY+EQEorqJRTnXM8XKHNB6j3
# j9NMAhUAxUe7QB/0CvOqAPy8+H6jhQIVq/QYDzIwMjMwMzA3MDU0MDAxWqBupGww
# ajELMAkGA1UEBhMCR0IxEzARBgNVBAgTCk1hbmNoZXN0ZXIxGDAWBgNVBAoTD1Nl
# Y3RpZ28gTGltaXRlZDEsMCoGA1UEAwwjU2VjdGlnbyBSU0EgVGltZSBTdGFtcGlu
# ZyBTaWduZXIgIzOggg3qMIIG9jCCBN6gAwIBAgIRAJA5f5rSSjoT8r2RXwg4qUMw
# DQYJKoZIhvcNAQEMBQAwfTELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIg
# TWFuY2hlc3RlcjEQMA4GA1UEBxMHU2FsZm9yZDEYMBYGA1UEChMPU2VjdGlnbyBM
# aW1pdGVkMSUwIwYDVQQDExxTZWN0aWdvIFJTQSBUaW1lIFN0YW1waW5nIENBMB4X
# DTIyMDUxMTAwMDAwMFoXDTMzMDgxMDIzNTk1OVowajELMAkGA1UEBhMCR0IxEzAR
# BgNVBAgTCk1hbmNoZXN0ZXIxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEsMCoG
# A1UEAwwjU2VjdGlnbyBSU0EgVGltZSBTdGFtcGluZyBTaWduZXIgIzMwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCQsnE/eeHUuYoXzMOXwpCUcu1aOm8B
# Q39zWiifJHygNUAG+pSvCqGDthPkSxUGXmqKIDRxe7slrT9bCqQfL2x9LmFR0IxZ
# Nz6mXfEeXYC22B9g480Saogfxv4Yy5NDVnrHzgPWAGQoViKxSxnS8JbJRB85XZyw
# lu1aSY1+cuRDa3/JoD9sSq3VAE+9CriDxb2YLAd2AXBF3sPwQmnq/ybMA0QfFijh
# anS2nEX6tjrOlNEfvYxlqv38wzzoDZw4ZtX8fR6bWYyRWkJXVVAWDUt0cu6gKjH8
# JgI0+WQbWf3jOtTouEEpdAE/DeATdysRPPs9zdDn4ZdbVfcqA23VzWLazpwe/Opw
# feZ9S2jOWilh06BcJbOlJ2ijWP31LWvKX2THaygM2qx4Qd6S7w/F7KvfLW8aVFFs
# M7ONWWDn3+gXIqN5QWLP/Hvzktqu4DxPD1rMbt8fvCKvtzgQmjSnC//+HV6k8+4W
# OCs/rHaUQZ1kHfqA/QDh/vg61MNeu2lNcpnl8TItUfphrU3qJo5t/KlImD7yRg1p
# sbdu9AXbQQXGGMBQ5Pit/qxjYUeRvEa1RlNsxfThhieThDlsdeAdDHpZiy7L9GQs
# Qkf0VFiFN+XHaafSJYuWv8at4L2xN/cf30J7qusc6es9Wt340pDVSZo6HYMaV38c
# AcLOHH3M+5YVxQIDAQABo4IBgjCCAX4wHwYDVR0jBBgwFoAUGqH4YRkgD8NBd0Uo
# jtE1XwYSBFUwHQYDVR0OBBYEFCUuaDxrmiskFKkfot8mOs8UpvHgMA4GA1UdDwEB
# /wQEAwIGwDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMEoG
# A1UdIARDMEEwNQYMKwYBBAGyMQECAQMIMCUwIwYIKwYBBQUHAgEWF2h0dHBzOi8v
# c2VjdGlnby5jb20vQ1BTMAgGBmeBDAEEAjBEBgNVHR8EPTA7MDmgN6A1hjNodHRw
# Oi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29SU0FUaW1lU3RhbXBpbmdDQS5jcmww
# dAYIKwYBBQUHAQEEaDBmMD8GCCsGAQUFBzAChjNodHRwOi8vY3J0LnNlY3RpZ28u
# Y29tL1NlY3RpZ29SU0FUaW1lU3RhbXBpbmdDQS5jcnQwIwYIKwYBBQUHMAGGF2h0
# dHA6Ly9vY3NwLnNlY3RpZ28uY29tMA0GCSqGSIb3DQEBDAUAA4ICAQBz2u1ocsvC
# uUChMbu0A6MtFHsk57RbFX2o6f2t0ZINfD02oGnZ85ow2qxp1nRXJD9+DzzZ9cN5
# JWwm6I1ok87xd4k5f6gEBdo0wxTqnwhUq//EfpZsK9OU67Rs4EVNLLL3OztatcH7
# 14l1bZhycvb3Byjz07LQ6xm+FSx4781FoADk+AR2u1fFkL53VJB0ngtPTcSqE4+X
# rwE1K8ubEXjp8vmJBDxO44ISYuu0RAx1QcIPNLiIncgi8RNq2xgvbnitxAW06IQI
# kwf5fYP+aJg05Hflsc6MlGzbA20oBUd+my7wZPvbpAMxEHwa+zwZgNELcLlVX0e+
# OWTOt9ojVDLjRrIy2NIphskVXYCVrwL7tNEunTh8NeAPHO0bR0icImpVgtnyughl
# A+XxKfNIigkBTKZ58qK2GpmU65co4b59G6F87VaApvQiM5DkhFP8KvrAp5eo6rWN
# es7k4EuhM6sLdqDVaRa3jma/X/ofxKh/p6FIFJENgvy9TZntyeZsNv53Q5m4aS18
# YS/to7BJ/lu+aSSR/5P8V2mSS9kFP22GctOi0MBk0jpCwRoD+9DtmiG4P6+mslFU
# 1UzFyh8SjVfGOe1c/+yfJnatZGZn6Kow4NKtt32xakEnbgOKo3TgigmCbr/j9re8
# ngspGGiBoZw/bhZZSxQJCZrmrr9gFd2G9TCCBuwwggTUoAMCAQICEDAPb6zdZph0
# fKlGNqd4LbkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpOZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMVVGhl
# IFVTRVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENlcnRp
# ZmljYXRpb24gQXV0aG9yaXR5MB4XDTE5MDUwMjAwMDAwMFoXDTM4MDExODIzNTk1
# OVowfTELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQ
# MA4GA1UEBxMHU2FsZm9yZDEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSUwIwYD
# VQQDExxTZWN0aWdvIFJTQSBUaW1lIFN0YW1waW5nIENBMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAyBsBr9ksfoiZfQGYPyCQvZyAIVSTuc+gPlPvs1rA
# dtYaBKXOR4O168TMSTTL80VlufmnZBYmCfvVMlJ5LsljwhObtoY/AQWSZm8hq9Vx
# EHmH9EYqzcRaydvXXUlNclYP3MnjU5g6Kh78zlhJ07/zObu5pCNCrNAVw3+eolzX
# OPEWsnDTo8Tfs8VyrC4Kd/wNlFK3/B+VcyQ9ASi8Dw1Ps5EBjm6dJ3VV0Rc7NCF7
# lwGUr3+Az9ERCleEyX9W4L1GnIK+lJ2/tCCwYH64TfUNP9vQ6oWMilZx0S2UTMiM
# PNMUopy9Jv/TUyDHYGmbWApU9AXn/TGs+ciFF8e4KRmkKS9G493bkV+fPzY+DjBn
# K0a3Na+WvtpMYMyou58NFNQYxDCYdIIhz2JWtSFzEh79qsoIWId3pBXrGVX/0DlU
# LSbuRRo6b83XhPDX8CjFT2SDAtT74t7xvAIo9G3aJ4oG0paH3uhrDvBbfel2aZMg
# HEqXLHcZK5OVmJyXnuuOwXhWxkQl3wYSmgYtnwNe/YOiU2fKsfqNoWTJiJJZy6hG
# wMnypv99V9sSdvqKQSTUG/xypRSi1K1DHKRJi0E5FAMeKfobpSKupcNNgtCN2mu3
# 2/cYQFdz8HGj+0p9RTbB942C+rnJDVOAffq2OVgy728YUInXT50zvRq1naHelUF6
# p4MCAwEAAaOCAVowggFWMB8GA1UdIwQYMBaAFFN5v1qqK0rPVIDh2JvAnfKyA2bL
# MB0GA1UdDgQWBBQaofhhGSAPw0F3RSiO0TVfBhIEVTAOBgNVHQ8BAf8EBAMCAYYw
# EgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDCDARBgNVHSAE
# CjAIMAYGBFUdIAAwUAYDVR0fBEkwRzBFoEOgQYY/aHR0cDovL2NybC51c2VydHJ1
# c3QuY29tL1VTRVJUcnVzdFJTQUNlcnRpZmljYXRpb25BdXRob3JpdHkuY3JsMHYG
# CCsGAQUFBwEBBGowaDA/BggrBgEFBQcwAoYzaHR0cDovL2NydC51c2VydHJ1c3Qu
# Y29tL1VTRVJUcnVzdFJTQUFkZFRydXN0Q0EuY3J0MCUGCCsGAQUFBzABhhlodHRw
# Oi8vb2NzcC51c2VydHJ1c3QuY29tMA0GCSqGSIb3DQEBDAUAA4ICAQBtVIGlM10W
# 4bVTgZF13wN6MgstJYQRsrDbKn0qBfW8Oyf0WqC5SVmQKWxhy7VQ2+J9+Z8A70DD
# rdPi5Fb5WEHP8ULlEH3/sHQfj8ZcCfkzXuqgHCZYXPO0EQ/V1cPivNVYeL9IduFE
# Z22PsEMQD43k+ThivxMBxYWjTMXMslMwlaTW9JZWCLjNXH8Blr5yUmo7Qjd8Fng5
# k5OUm7Hcsm1BbWfNyW+QPX9FcsEbI9bCVYRm5LPFZgb289ZLXq2jK0KKIZL+qG9a
# JXBigXNjXqC72NzXStM9r4MGOBIdJIct5PwC1j53BLwENrXnd8ucLo0jGLmjwkcd
# 8F3WoXNXBWiap8k3ZR2+6rzYQoNDBaWLpgn/0aGUpk6qPQn1BWy30mRa2Coiwkud
# 8TleTN5IPZs0lpoJX47997FSkc4/ifYcobWpdR9xv1tDXWU9UIFuq/DQ0/yysx+2
# mZYm9Dx5i1xkzM3uJ5rloMAMcofBbk1a0x7q8ETmMm8c6xdOlMN4ZSA7D0GqH+mh
# QZ3+sbigZSo04N6o+TzmwTC7wKBjLPxcFgCo0MR/6hGdHgbGpm0yXbQ4CStJB6r9
# 7DDa8acvz7f9+tCjhNknnvsBZne5VhDhIG7GrrH5trrINV0zdo7xfCAMKneutaIC
# hrop7rRaALGMq+P5CslUXdS5anSevUiumDGCBC0wggQpAgEBMIGSMH0xCzAJBgNV
# BAYTAkdCMRswGQYDVQQIExJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcTB1Nh
# bGZvcmQxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDElMCMGA1UEAxMcU2VjdGln
# byBSU0EgVGltZSBTdGFtcGluZyBDQQIRAJA5f5rSSjoT8r2RXwg4qUMwDQYJYIZI
# AWUDBAICBQCgggFrMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAcBgkqhkiG
# 9w0BCQUxDxcNMjMwMzA3MDU0MDAxWjA/BgkqhkiG9w0BCQQxMgQwm24841C9jEKX
# farT2tRpjn6/q7O24nhs+wmnM8juB+mlAA+8dEE1N2SQf/wkH4VmMIHtBgsqhkiG
# 9w0BCRACDDGB3TCB2jCB1zAWBBSrNAE6rECXMZ8IGvCzGOGD+A94gTCBvAQUAtZb
# leKDcMFXAJX6iPkj3ZN/rY8wgaMwgY6kgYswgYgxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpOZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMV
# VGhlIFVTRVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENl
# cnRpZmljYXRpb24gQXV0aG9yaXR5AhAwD2+s3WaYdHypRjaneC25MA0GCSqGSIb3
# DQEBAQUABIICABeucFCEIE9usEAhEDOO9sGZd/3AcnvqO8O9bY8v2Il/N07iC3Z3
# 6iQ0+DFjuQuYChXmp2IWH48ZSCHoiQYmlC5mqw/ZsLOOVxcmX3bVQlDb+hS3u6w4
# athsXzqOnf+Aw5RDzvFF5DpH/i1MXacy9hw1p5YKEZxkVEgXkXvkI316Dz+7d5au
# kzTvonWY762Uhzev/1FRCYpOsPpNrsNY2o6mfb+ibjX2KDz3hbOSQmootvO4nW6m
# abjzm1p0beJSXu5ODN03EG1wCg7tGR0Y4PkEoSHdmBw9P9ywd/bUwhT424QwbZxh
# 6oDw5Ke9F2i3oqcFO37ofo+XXnCrR28jJbQSwGUMZqcPmGBk+2hiP2+AP+/qrJ6H
# HPutIGa059i4MsbhDf9OxIeqUWOwaQ9P/kO8Hewdw+SJAQ2yVyxAgsdYtykdcXFO
# gtron1BG8yAdswCzBLsWHH1Ucao9jY9grPhVXpPa0IdIG+q2B1WUJRyMS621taoh
# kVRN+Ye65kAWkLIg+V0qprI5y5kTJFy5N895sozvHd3Rs4sizg9l9coE8PYcghpx
# FbL9ATvhJDODlPSBLIKVFMMoQSV2rIeXS/bdo/MNYv7hk4G8E58suGmf59P4PC7K
# QiBY3INGshUAOAS6Bpno8LV86SV+nxcsctQ+710EtDmEtwSEmsj2kh+D
# SIG # End signature block
