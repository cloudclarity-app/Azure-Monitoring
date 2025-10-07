param alertName string
param alertDescription string = 'This is a metric alert'

@allowed([0, 1, 2, 3, 4])
param alertSeverity int = 3

param isEnabled bool = true
param resourceId string
param metricName string
param metricNamespace string = 'Microsoft.Web'

@allowed([
  'GreaterOrLessThan'
  'GreaterThan'
  'LessThan'
])
param operator string = 'GreaterThan'

@allowed([
  'Average'
  'Count'
  'Minimum'
  'Maximum'
  'Total'
])
param timeAggregation string = 'Average'
param alertSensitivity string = 'Low'
param windowSize string = 'PT30M'
param evaluationFrequency string = 'PT5M'
param failingPeriods int = 4
param evalPeriods int = 4
param actionGroupId string = ''


resource symbolicname 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  //scope: resourceSymbolicName or scope
  location: 'global'
  name: alertName
  properties: {
    actions: [
      {
        actionGroupId: actionGroupId
      }
    ]
    //autoMitigate: bool
    criteria: {
      allOf: [
        {
          criterionType: 'DynamicThresholdCriterion'
          failingPeriods: {
            minFailingPeriodsToAlert: failingPeriods
            numberOfEvaluationPeriods: evalPeriods
          }
          dimensions: []
          metricName: metricName
          metricNamespace: metricNamespace
          name: '1st criterion'
          alertSensitivity: alertSensitivity
          operator: operator
          //skipMetricValidation: bool
          //threshold: threshold
          timeAggregation: timeAggregation
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
    }
    description: alertDescription
    enabled: isEnabled
    evaluationFrequency: evaluationFrequency
    scopes: [
      resourceId
    ]
    severity: alertSeverity
    // targetResourceRegion: 'string'
    // targetResourceType: 'string'
    windowSize: windowSize
  }
  tags: {}
}
