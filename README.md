# Azure-Monitoring
**Automated Azure Monitoring**

- You can use this script to automatically set monitoring threshold on Azure resources.
- By default, the script applies to all metrics enabled for monitoring accross the entire subscription. It will complete a review of all existing rules and any with no valid scope will be deleted.
- You can restrict the scope by defining either a specific resource group, using the rgazresources variable, and/or a specific resource type, using the azrestype variable. Additionally, you can exclude resource resource groups from alerts by using the excludedRgs variable.


**Folder Structure**

The script must be located at the root while the CSV file must be located within a subfolder named like your Azure subscription.
* The 2 JSON files co-located with the script are the metric templates. Different templates are used depending of the resource type.
* The 2 JSON files co-located with the CSV file - in the subfolder - are the parameters files to use with the corresponding templates.
* A Bicep file co-located with the script is the dynamic alert template.
* A Bicepparam file co-located with the CSV file - in the subfolder - is the Bicep parameters file to be used with the corresponding Bicep template.
* UpdateMetricsCSV.py co-located with the CSV file - in the subfolder - to successfully update the azure_monitoring.csv.

NOTE: this script has been tested and validated with the following Azure resource types - if you are experiencing an issue with another resource type please log an issue
* Virtual Machine
* Storage Account (ARM)
* App Services Plan
* App Services
* Application Gateway
* Azure SQL Database


**How to use**
1. Download the artifacts

2. Rename the *subscriptionname* folder with the name of your Azure subscription

3. In Azure, create at least one action group (see https://docs.microsoft.com/en-us/azure/azure-monitor/platform/action-groups)

4. (Optional) Run UpdateMetricsCSV.py to gather all new supported metrics and removed unsupported metrics from azure_monitoring.csv. It will keep any 
   current settings for metrics that are still supported at the time of updating. For this python script to run successfully, it requires Python 3 (The recommended and tested version is 3.10) and the following external libraries: Requests, Numpy, Pandas and BeautifulSoup. Links to these external libraries are listed at the head of the python file.

5. Edit the CSV file to define which the following paramters:
   - 5.1 Enable for monitoring: Set to Yes for any metric you wish to monitor.

   - 5.2 Alert Type: Used to determine whether alert should be static or dynamic. By default if the alert is enabled, but no value is provided for alert type, the alert will be set to static. For example:
      - *no value* -> Static
      - Static -> Static
      - Dynamic -> Dynamic

   - 5.3 Tag Name: Tag's are used for exceptions, if your resource that you have enabled for monitoring needs an alternate threshold from the default in the csv file you set the tag here.

   - 5.4 Threshold (Static Alerting): Define the threshold associated with the metric (refer to the "Unit" to ensure your Threshold is relevant to the Unit type). Requires an integer input.

   - 5.5 Threshold Sensitivity (Dynamic Alerting): Used to set the sensitivity for dynamic alerts. The following values can be used:
      - High
      - Medium
      - Low

   - 5.6 Operator: Define the operator for the threshold. The following values can be used:
      For Static Alerts:
         - Equals
         - GreaterThan
         - GreaterThanOrEqual
         - LessThan
         - LessThanOrEqual

      For Dynamic Alerts:
         - GreaterThan
         - GreaterOrLessThan
         - LessThan

   - 5.7 Eval Frequency: This is the defined evaluation period based on resource type. Requires an input that uses the ISO 8601 duration format.

   - 5.8 Windows Size: This is the size of metric window to inspect. Requires an input that uses the ISO 8601 duration format.

   - 5.9 Failing Periods (Dynamic Alerting): The number of failing evaluations before triggering an alert. Requires an integer input.

   - 5.10 Evaluation Periods (Dynamic Alerting): Used to determine the sample size for which the number of failing evaluations is judged against. For example: 4 failing periods and 6 evaluation periods corresponds to 4 failed evaluations within a time frame equivalent to the evaluation frequency multiplied by the evaluation periods. In this scenario, if 4 or more failed evaluations occur during this time an alert will be triggered.

   - 5.11 Aggregation Time: Dependent on resource type. Possible values that can be used are: 
      - Average
      - Minimum
      - Maximum
      - Count
      - Total

   - 5.12 Alert Name: Set a custom alert name (Required if using multiple alerts for a single metric to prevent Azure overwriting previously set alerts).

   - 5.13 Alert Description: Describe your alert.

   - 5.14 Severity: This is a scale of 0-4. The values and their corresponding severity are listed below:
		- 0 = Critical
		- 1 = Error
		- 2 = Warning
		- 3 = Informational
		- 4 = Verbose

6. Execute the PowerShell script by providing the following parameters:
   - 6.1 rgactiongroup: mandatory. Defines the resource group where the action group has been saved.

   - 6.2 actiongroupname: mandatory. Defines the action group name to use when setting up the metrics.

   - 6.3 fileslocation: mandatory. Defines the location of the CSV file.

   - 6.4 azrestype: optional. Define the Azure resource type you want to enable monitoring. This will exclude all other resource type enabled in the CSV.

   - 6.5 rgazresources: optional. Define the resource group you want to enable the metrics. This reduce the scope of the script from subscription to resource group level.

   - 6.6 excludedRgs: optional. Defined as a list of resource groups. This will exclude any resource groups listed here from having alerts deployed to them.
