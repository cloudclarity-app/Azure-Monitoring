using '../Dynamic-Alert.bicep'

param alertName = ''
param alertDescription = 'The percentage of allocated compute units that are currently in use by the Virtual Machine(s)'
param alertSeverity = 1
param isEnabled = true
param resourceId = ''
param metricName = 'Percentage CPU'
param metricNamespace = 'Microsoft.Compute/virtualMachines'
param operator = 'GreaterOrLessThan'
param alertSensitivity = 'Low'
param timeAggregation = 'Average'
param windowSize = 'PT1H'
param evaluationFrequency = 'PT1H'
param failingPeriods = 4
param evalPeriods = 4
param actionGroupId = ''
