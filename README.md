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

**How to use**
1. Download the artifacts
2. Rename the *subscriptionname* folder with the name of your Azure subscription
3. In Azure, create at least one action group (see https://docs.microsoft.com/en-us/azure/azure-monitor/platform/action-groups)
4. Edit the CSV file to define which metric(s) must be enabled, the threshold value as well as the corresponding settings for evaluation (samples are included for storage account and virtual machine)
5. Execute the PowerShell script by providing the following parameters:
   - 5.1. rgactiongroup: mandatory. Defines the resource group where the action group has been saved
   - 5.2 actiongroupname: mandatory. Defines the action group name to use when setting up the metrics
   - 5.3 fileslocation: mandatory. Defines the location of the CSV file
   - 5.4 azrestype: optional. Define the Azure resource type you want to enable monitoring. This will exclude all other resource type enabled in the CSV
   - 5.5 rgazresources: optional. Define the resource group you want to enable the metrics. This reduce the scope of the script from subscription to resource group level.
