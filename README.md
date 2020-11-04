# Azure-Monitoring
**Automated Azure Monitoring**

You can use this script to automatically set monitoring threshold on Azure resources.
By default, the script applies to all metrics enabled for monitoring accross the entire subscription.
You can restrict the scope by defining either a specific resource group, using the rgazresources variable, and/or a specific resource type, using the azrestype variable.

**Folder Structure**

The script must be located at the root while the CSV file must be located within a subfolder named like your Azure subscription.
* The 2 JSON files co-located with the script are the metric templates. Different templates are used depending of the resource type.
* The 2 JSON files co-located with the CSV file - in the subfolder - are the parameters files to use with the corresponding templates.


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
4. Edit the CSV file to define which the following paramters:
   - 4.1 Enable for monitoring: Set to Yes for any metric you wish to monitor
   - 4.2 Tag Name: Tag's are used for exceptions, if your resource that you have enabled for monitoring needs an alternate threshold from the default in the csv file you set the tag here 
   - 4.3 Threshold: Define the threshold associate with the metric (refer to the "Unit" to ensure your Threshold is relevant to the Unit type)
   - 4.4 Operator: Define the operator for the threshold
   - 4.5 Eval Frequency: This is the defined evlaution period based on resource type
   - 4.6 Windows Size: This is the size of metric window to inspect
   - 4.7 Aggregation Time: Is defined by type of resource some count and others can have min/max or average
   - 4.8 Alert Description: Describe your alert
   - 4.9 Severity: This is a scale of 0-4 
		- Sev 0 = Critical
		- Sev 1 = Error
		- Sev 2 = Warning
		- Sev 3 = Informational
		- Sev 4 = Verbose
5. Execute the PowerShell script by providing the following parameters:
   - 5.1 rgactiongroup: mandatory. Defines the resource group where the action group has been saved
   - 5.2 actiongroupname: mandatory. Defines the action group name to use when setting up the metrics
   - 5.3 fileslocation: mandatory. Defines the location of the CSV file
   - 5.4 azrestype: optional. Define the Azure resource type you want to enable monitoring. This will exclude all other resource type enabled in the CSV
   - 5.5 rgazresources: optional. Define the resource group you want to enable the metrics. This reduce the scope of the script from subscription to resource group level.
