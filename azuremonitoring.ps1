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
    Contact:     info@tagmanager.app
    Created:     2020-10-01
    Updated:     2020-11-27

    Version history:
    1.0.0 - (2020-10-01) - Script created
    1.0.1 - (2020-10-12) - Fixing issue for Azure SQL Database monitoring; different version of template and schema
    1.0.2 - (2020-11-27) - Code signing
    1.0.3 - (2020-11-30) - Rename template and parameters files matching the schema version instead; update monitoring CSV to pre populate additional values for metrics thresholds
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
            $templatefilepath = "$psscriptroot\parameters_2015-01-01.json"
#JSON parameters file
            $parametersfilepath = "$psscriptroot\$fileslocation\template_2015-01-01.json"
        }
        Else
#Storage account, virtual machines, web apps
        {
#JSON template file
            $templatefilepath = "$psscriptroot\parameters_2019-04-01.json"
#JSON parameters file
            $parametersfilepath = "$psscriptroot\$fileslocation\template_2019-04-01.json"
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
# MIIThQYJKoZIhvcNAQcCoIITdjCCE3ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUWGS62Z4c+837qE3bUaJe0TQ9
# fUygghC8MIIFOjCCBCKgAwIBAgIRAMAkGCkl6rgosyKOhFWhX14wDQYJKoZIhvcN
# AQELBQAwfDELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3Rl
# cjEQMA4GA1UEBxMHU2FsZm9yZDEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSQw
# IgYDVQQDExtTZWN0aWdvIFJTQSBDb2RlIFNpZ25pbmcgQ0EwHhcNMjAxMTIwMDAw
# MDAwWhcNMjMxMTIwMjM1OTU5WjB+MQswCQYDVQQGEwJBVTENMAsGA1UEEQwEMjAw
# MDEPMA0GA1UEBwwGU3lkbmV5MRswGQYDVQQJDBJMZXZlbCAyLzQ0IFBpdHQgU3Qx
# GDAWBgNVBAoMD0NVQkVTWVMgUFRZIExURDEYMBYGA1UEAwwPQ1VCRVNZUyBQVFkg
# TFREMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAod6TgHNzGaGyOwCe
# YYVxIk3gIP2A4DH8iyVNX6f8AGnXZ5b5SgDnYLb43/eYDgSIiDqxRPgYdX7n5q6v
# xB/4rWKbNTWSbsIJnkRx7AjS3d1erqCRAOQvWOqGL3kEdrL/fdkvlIDZ6Pcq3Gin
# aCe6upC3otSaSomQAqNltzumvCN6lp1NdmvQOjxncttUncFmaABOqFgaO78i95IF
# /hsEz2TyAvM61qe+NEm9SnmF0jTkwGYQ2+cNbFV734rvOsoxOJ0hXDnNIgjrbjzW
# rHAn5mk4G0Z8yLM5kL69WNn8730EGBe+F+HM589PJgDixWRXSJ97Jf/ChQazCpiw
# 86XeQQIDAQABo4IBszCCAa8wHwYDVR0jBBgwFoAUDuE6qFM6MdWKvsG7rWcaA4Wt
# NA4wHQYDVR0OBBYEFObv4MQdB9HUJAd58GxnKMbiwgdMMA4GA1UdDwEB/wQEAwIH
# gDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMBEGCWCGSAGG+EIB
# AQQEAwIEEDBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgEDAjAlMCMGCCsGAQUFBwIB
# FhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwBBAEwQwYDVR0fBDwwOjA4
# oDagNIYyaHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUlNBQ29kZVNpZ25p
# bmdDQS5jcmwwcwYIKwYBBQUHAQEEZzBlMD4GCCsGAQUFBzAChjJodHRwOi8vY3J0
# LnNlY3RpZ28uY29tL1NlY3RpZ29SU0FDb2RlU2lnbmluZ0NBLmNydDAjBggrBgEF
# BQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20wIQYDVR0RBBowGIEWc3VwcG9y
# dEBjdWJlc3lzLmNvbS5hdTANBgkqhkiG9w0BAQsFAAOCAQEAJgGu99/CNblxUOV3
# fk7nZ+3vJgoSJ59vJlb8ZhdBYZmXGicUuii6W5yo/VlClXgBkydIHlvf6HjE4SKa
# 7NfcK1wU9PkH09hUOfkhTAYYmsWAlBfS4ClNsITRy7y4fgXj5cJDnkBzAc1UkM3G
# Gi2iLfVGxeAAzm4BMSIcwFNoKPA3QOiWZVt70dP0eQj7LLl4lB6LtHwGfbcDNq4G
# V1lY+04lhPAV4slN7J8rDi2+HeK83P4ImaaSInujF49vg3rPI40S+Ju9DQpPDtsQ
# bXa42CF6dmFlJy1pP7JhzrwS1SMWBNyJ4xJLPVpaV2LHwlIcJQCytfYyFO7tazDQ
# GmTdCzCCBYEwggRpoAMCAQICEDlyRDr5IrdR19NsEN0xNZUwDQYJKoZIhvcNAQEM
# BQAwezELMAkGA1UEBhMCR0IxGzAZBgNVBAgMEkdyZWF0ZXIgTWFuY2hlc3RlcjEQ
# MA4GA1UEBwwHU2FsZm9yZDEaMBgGA1UECgwRQ29tb2RvIENBIExpbWl0ZWQxITAf
# BgNVBAMMGEFBQSBDZXJ0aWZpY2F0ZSBTZXJ2aWNlczAeFw0xOTAzMTIwMDAwMDBa
# Fw0yODEyMzEyMzU5NTlaMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKTmV3IEpl
# cnNleTEUMBIGA1UEBxMLSmVyc2V5IENpdHkxHjAcBgNVBAoTFVRoZSBVU0VSVFJV
# U1QgTmV0d29yazEuMCwGA1UEAxMlVVNFUlRydXN0IFJTQSBDZXJ0aWZpY2F0aW9u
# IEF1dGhvcml0eTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAIASZRc2
# DsPbCLPQrFcNdu3NJ9NMrVCDYeKqIE0JLWQJ3M6Jn8w9qez2z8Hc8dOx1ns3KBEr
# R9o5xrw6GbRfpr19naNjQrZ28qk7K5H44m/Q7BYgkAk+4uh0yRi0kdRiZNt/owbx
# iBhqkCI8vP4T8IcUe/bkH47U5FHGEWdGCFHLhhRUP7wz/n5snP8WnRi9UY41pqdm
# yHJn2yFmsdSbeAPAUDrozPDcvJ5M/q8FljUfV1q3/875PbcstvZU3cjnEjpNrkyK
# t1yatLcgPcp/IjSufjtoZgFE5wFORlObM2D3lL5TN5BzQ/Myw1Pv26r+dE5px2uM
# YJPexMcM3+EyrsyTO1F4lWeL7j1W/gzQaQ8bD/MlJmszbfduR/pzQ+V+DqVmsSl8
# MoRjVYnEDcGTVDAZE6zTfTen6106bDVc20HXEtqpSQvf2ICKCZNijrVmzyWIzYS4
# sT+kOQ/ZAp7rEkyVfPNrBaleFoPMuGfi6BOdzFuC00yz7Vv/3uVzrCM7LQC/NVV0
# CUnYSVgaf5I25lGSDvMmfRxNF7zJ7EMm0L9BX0CpRET0medXh55QH1dUqD79dGMv
# sVBlCeZYQi5DGky08CVHWfoEHpPUJkZKUIGy3r54t/xnFeHJV4QeD2PW6WK61l9V
# LupcxigIBCU5uA4rqfJMlxwHPw1S9e3vL4IPAgMBAAGjgfIwge8wHwYDVR0jBBgw
# FoAUoBEKIz6W8Qfs4q8p74Klf9AwpLQwHQYDVR0OBBYEFFN5v1qqK0rPVIDh2JvA
# nfKyA2bLMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MBEGA1UdIAQK
# MAgwBgYEVR0gADBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsLmNvbW9kb2Nh
# LmNvbS9BQUFDZXJ0aWZpY2F0ZVNlcnZpY2VzLmNybDA0BggrBgEFBQcBAQQoMCYw
# JAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmNvbW9kb2NhLmNvbTANBgkqhkiG9w0B
# AQwFAAOCAQEAGIdR3HQhPZyK4Ce3M9AuzOzw5steEd4ib5t1jp5y/uTW/qofnJYt
# 7wNKfq70jW9yPEM7wD/ruN9cqqnGrvL82O6je0P2hjZ8FODN9Pc//t64tIrwkZb+
# /UNkfv3M0gGhfX34GRnJQisTv1iLuqSiZgR2iJFODIkUzqJNyTKzuugUGrxx8Vvw
# QQuYAAoiAxDlDLH5zZI3Ge078eQ6tvlFEyZ1r7uq7z97dzvSxAKRPRkA0xdcOds/
# exgNRc2ThZYvXd9ZFk8/Ub3VRRg/7UqO6AZhdCMWtQ1QcydER38QXYkqa4UxFMTo
# qWpMgLxqeM+4f452cpkMnf7XkQgWoaNflTCCBfUwggPdoAMCAQICEB2iSDBvmyYY
# 0ILgln0z02owDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpOZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMVVGhl
# IFVTRVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENlcnRp
# ZmljYXRpb24gQXV0aG9yaXR5MB4XDTE4MTEwMjAwMDAwMFoXDTMwMTIzMTIzNTk1
# OVowfDELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQ
# MA4GA1UEBxMHU2FsZm9yZDEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSQwIgYD
# VQQDExtTZWN0aWdvIFJTQSBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQCGIo0yhXoYn0nwli9jCB4t3HyfFM/jJrYlZilAhlRG
# dDFixRDtsocnppnLlTDAVvWkdcapDlBipVGREGrgS2Ku/fD4GKyn/+4uMyD6DBmJ
# qGx7rQDDYaHcaWVtH24nlteXUYam9CflfGqLlR5bYNV+1xaSnAAvaPeX7Wpyvjg7
# Y96Pv25MQV0SIAhZ6DnNj9LWzwa0VwW2TqE+V2sfmLzEYtYbC43HZhtKn52BxHJA
# teJf7wtF/6POF6YtVbC3sLxUap28jVZTxvC6eVBJLPcDuf4vZTXyIuosB69G2flG
# HNyMfHEo8/6nxhTdVZFuihEN3wYklX0Pp6F8OtqGNWHTAgMBAAGjggFkMIIBYDAf
# BgNVHSMEGDAWgBRTeb9aqitKz1SA4dibwJ3ysgNmyzAdBgNVHQ4EFgQUDuE6qFM6
# MdWKvsG7rWcaA4WtNA4wDgYDVR0PAQH/BAQDAgGGMBIGA1UdEwEB/wQIMAYBAf8C
# AQAwHQYDVR0lBBYwFAYIKwYBBQUHAwMGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYE
# VR0gADBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLnVzZXJ0cnVzdC5jb20v
# VVNFUlRydXN0UlNBQ2VydGlmaWNhdGlvbkF1dGhvcml0eS5jcmwwdgYIKwYBBQUH
# AQEEajBoMD8GCCsGAQUFBzAChjNodHRwOi8vY3J0LnVzZXJ0cnVzdC5jb20vVVNF
# UlRydXN0UlNBQWRkVHJ1c3RDQS5jcnQwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3Nw
# LnVzZXJ0cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIBAE1jUO1HNEphpNveaiqM
# m/EAAB4dYns61zLC9rPgY7P7YQCImhttEAcET7646ol4IusPRuzzRl5ARokS9At3
# WpwqQTr81vTr5/cVlTPDoYMot94v5JT3hTODLUpASL+awk9KsY8k9LOBN9O3ZLCm
# I2pZaFJCX/8E6+F0ZXkI9amT3mtxQJmWunjxucjiwwgWsatjWsgVgG10Xkp1fqW4
# w2y1z99KeYdcx0BNYzX2MNPPtQoOCwR/oEuuu6Ol0IQAkz5TXTSlADVpbL6fICUQ
# DRn7UJBhvjmPeo5N9p8OHv4HURJmgyYZSJXOSsnBf/M6BZv5b9+If8AjntIeQ3pF
# McGcTanwWbJZGehqjSkEAnd8S0vNcL46slVaeD68u28DECV3FTSK+TbMQ5Lkuk/x
# YpMoJVcp+1EZx6ElQGqEV8aynbG8HArafGd+fS7pKEwYfsR7MUFxmksp7As9V1DS
# yt39ngVR5UR43QHesXWYDVQk/fBO4+L4g71yuss9Ou7wXheSaG3IYfmm8SoKC6W5
# 9J7umDIFhZ7r+YMp08Ysfb06dy6LN0KgaoLtO0qqlBCk4Q34F8W2WnkzGJLjtXX4
# oemOCiUe5B7xn1qHI/+fpFGe+zmAEc3btcSnqIBv5VPU4OOiwtJbGvoyJi1qV3Ac
# PKRYLqPzW0sH3DJZ84enGm1YMYICMzCCAi8CAQEwgZEwfDELMAkGA1UEBhMCR0Ix
# GzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBxMHU2FsZm9yZDEY
# MBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSQwIgYDVQQDExtTZWN0aWdvIFJTQSBD
# b2RlIFNpZ25pbmcgQ0ECEQDAJBgpJeq4KLMijoRVoV9eMAkGBSsOAwIaBQCgeDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEW
# BBSN43/0pwd7F6hk4V1AcCdB/q3zZTANBgkqhkiG9w0BAQEFAASCAQBYwInJAImy
# nFydyaPyn6bA/CbsrS+4QeXTTnDHO6m3RsFCw/BiBkfs31457l+H9T6/3xRRwlSt
# O+Pha0zlR++AagHCe+g/38cZtjMpsFLxLvlYsIwJ/83XH3sByC89KXKlIFJ2JOO0
# ZGddWcjPSG5TrKjwGcwuQCud73+RQ7WBvXio76fuHcd6PN7YLxCzeqm62IOPFkU9
# nLqrB3/ju9OKu4aVN2zeyx93Ul56lgk8hKI8QtYN3uY4PYElehLuvxDgfhXto1St
# BEn/AIMQ9OD4k5yayOTNcG1jtiU094avZyOCt2Feb+siaqwVp04BrDp45JF1FVxb
# u6OSFPqPrumg
# SIG # End signature block
