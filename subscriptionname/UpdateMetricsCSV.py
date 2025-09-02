# Author: David COOK - cubesys
# Created: 25th Jan 2023 (25/1/2023)
# Script Last Updated: 8th October 2024 (8/10/2024)
# Supprorted Metrics Page Last Updated At Time Of Script Update: 30th September 2024 (30/9/2024)
# Confirmed working using Python versions: 3.10.11

# Requirements:
# - Requests library (https://pypi.org/project/requests/)
# - numpy library (https://numpy.org/)
# - pandas library (https://pandas.pydata.org/)
# - BeautifulSoup library (https://www.crummy.com/software/BeautifulSoup/bs4/doc/)

# Synopsis: Updates the input csv with the currently supported metrics for azure resource types directly from the Microsoft
# supported metrics page (https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/metrics-supported).

# Description: This script will iterate through the current input csv (subscriptionname/azure_monitoring.csv) and gather any current settings for metrics present.
# Once gathered, the script will pull the html content from the supported metrics page, before removing the html
# along with organising and structuring the data. From here, the script will start building the data in the required
# structure for the input csv, while matching the previous metric settings to those that will be present in the updated csv.
# Additional checks and removal of html relating to hyperlinks also occurs at this stage. Finally, the structured metrics
# data is written to ./azure_monitoring.csv.

import requests
import numpy
import pandas
from bs4 import BeautifulSoup
import time

#Start time for run time
start = time.time()

#Reads in the input file with old supported metrics list and current settings
inputFile = pandas.read_csv("./azure_monitoring.csv", encoding='cp1252') #utf-8 cp1252

#Initialises current settings and current settings count variables to store any currently set parameters for each metric
currentSettings = None
currentSettingsCount = 0

#Initialises alertNameColumnPresent variable to check if the azure_monitoring.csv is aligned with the newer input csv format
alertNameColumnPresent = False
csvColumnIssue = False
additionalRows = 0

#Removes NaN inputs from the inputs of the original metrics file
def NANtoEmpty(setting):
    if(pandas.isna(setting)):
        return ""
    else:
        return setting

#Instantiates ResTypeWithSettings and OptimisedSettingsListIndexes variables globally
ResTypeWithSettings = list([])
OptimisedSettingsListIndexes = None

#Finds and extracts metrics with any current/non-empty settings in the existing csv
def ExtractCurrentSettings():
    global inputFile
    global currentSettings
    global currentSettingsCount
    global ResTypeWithSettings
    global alertNameColumnPresent
    global csvColumnIssue
    global additionalRows

    lastColumnIndex = 14

    if("Alert Name" in inputFile.columns):
        alertNameColumnPresent = True
        lastColumnIndex = 15

        if(not inputFile.columns[13] == "Alert Name"):
            csvColumnIssue = True
            print("Error: Misplaced Alert Name column. Must be the 13th column (3rd last) between the Aggregation Time and Alert Description columns")
            return

    #Iterates through the original file to count how many metrics have settings present
    for index, row in inputFile.iterrows():
        settingsPresent = False

        for setting in range(6, lastColumnIndex):
            if(not pandas.isna(row[setting]) and settingsPresent != True):
                currentSettingsCount += 1
                settingsPresent = True
                break

    #Instatiates currentSettings and rowCount variables
    currentSettings = [0] * currentSettingsCount
    rowCount = 0
    previousMetric = None

    #Iterates through the original file again, this time pulling out any settings found and placing them in currentSettings
    for index, row in inputFile.iterrows():
        settingsPresent = False

        for setting in range(6, lastColumnIndex):
            if(not pandas.isna(row[setting]) and settingsPresent != True):
                if(lastColumnIndex == 14):
                    currentSettings[rowCount] = [row[0], row[1], NANtoEmpty(row[6]), NANtoEmpty(row[7]), NANtoEmpty(row[8]), NANtoEmpty(row[9]), NANtoEmpty(row[10]), NANtoEmpty(row[11]), NANtoEmpty(row[12]), "", NANtoEmpty(row[13]), NANtoEmpty(row[14])]
                else:
                    currentSettings[rowCount] = [row[0], row[1], NANtoEmpty(row[6]), NANtoEmpty(row[7]), NANtoEmpty(row[8]), NANtoEmpty(row[9]), NANtoEmpty(row[10]), NANtoEmpty(row[11]), NANtoEmpty(row[12]), NANtoEmpty(row[13]), NANtoEmpty(row[14]), NANtoEmpty(row[15])]
                
                if(previousMetric != None and previousMetric[0] == row[0] and previousMetric[1] == row[1]):
                    additionalRows += 1

                previousMetric = [row[0], row[1]]

                rowCount += 1
                settingsPresent = True
                break

    #Finds unique resource types with settings
    for x in range(0, len(currentSettings)):
        if currentSettings[x][0] not in ResTypeWithSettings:
            ResTypeWithSettings.append(currentSettings[x][0])

    global OptimisedSettingsListIndexes
    OptimisedSettingsListIndexes = [0] * len(ResTypeWithSettings)

    #Instatiates an empty list for each unique resource type with settings
    for x in range(0, len(ResTypeWithSettings)):
        OptimisedSettingsListIndexes[x] = list([])

    #Instantiates Optimised Settings Indexes List Count (OSLIcount)
    OSLIcount = 0

    #Organises indexes of currentSettings in lists grouped by unique resource types with settings present
    for k in range(0, len(currentSettings)):
        if(currentSettings[k][0] == ResTypeWithSettings[OSLIcount]):
            OptimisedSettingsListIndexes[OSLIcount].append(k)
        else:
            OSLIcount+=1
            OptimisedSettingsListIndexes[OSLIcount].append(k)

#Instantiate html results variable for global scope
results = 0

#Pulls Html data for for main supported metrics page and all resource type pages with supported metrics
def PullHtml():
    global excessivePageChange
    global metricsDataSize

    #Scrapes content from microsoft azure supported metrics page
    URL = "https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-metrics/metrics-index"
    page = requests.get(URL)
    soup = BeautifulSoup(page.content, "html.parser")

    ListOfMetricLinks = list([])
    ResultData = list([])

    #Isolates the table body section to build list of links to each resource type's metrics page
    content = soup.find_all("tbody")

    #Splits table into rows and interates through to gather links to individual supported metrics pages
    contentTable = str(content[0]).split("</tr>\n<tr>")
    for row in contentTable:
        cleanedRow = str(row).split("</td>\n<td>")

        #If multiple resource type links are in a single row
        if "</a><a" in cleanedRow[1].replace("<br/>", ""):
            for entry in cleanedRow[1].replace("<br/>", "").split("</a><a"):
                ListOfMetricLinks.append(entry.replace("<a", "").replace(" data-linktype=\"relative-path\" href=\"", "").split("\">")[0])

        elif cleanedRow[1].replace("<br/>", "") != "N/A":
            ListOfMetricLinks.append(cleanedRow[1].replace("<br/>", "").replace("<a", "").replace(" data-linktype=\"relative-path\" href=\"", "").split("\">")[0])

    #Scrape individual metrics pages for each supported resource type
    for link in ListOfMetricLinks:
        metricsURL = "https://learn.microsoft.com/en-us/azure/azure-monitor/reference/" + link
        metricsPage = requests.get(metricsURL)
        metricsSoup = BeautifulSoup(metricsPage.content, "html.parser")

        #List for each resource type with supported metrics -> first element is the resource type, second element is 2 dimensional array of the relevant supperted metrics data
        MetricsData = list([])
        MetricsDataContainer = list([])

        #Isolates resource type from metrics page header
        resourceType = str(str(metricsSoup.find_all("h1")[0]).split("Supported metrics for ")[1]).replace("</h1>", "")
        MetricsData.append(resourceType)

        #Isolates the metrics table body and splits the table into its table rows
        metricsContent = str(metricsSoup.find_all("tbody")[0]).replace("<tbody>\n<tr>", "").replace("</tr>\n</tbody>", "").split("</tr>\n<tr>")

        #Isolates the headers in the metrics table
        metricsHeaders = str(str(metricsSoup.find_all("thead")[0]).replace("<thead>\n<tr>\n<th>", "")).replace("</th>\n</tr>\n</thead>", "").split("</th>\n<th>")

        if numpy.array_equal(metricsHeaders, ['Metric', 'Name in REST API', 'Unit', 'Aggregation', 'Dimensions', 'Time Grains', 'DS Export']):
            for metricRow in metricsContent:
                MetricsDataRow = [0] * 6
                MetricsDataRow[0] = resourceType

                for index, metric in enumerate(metricRow.split("</td>\n<td>")):
                    if index > 3:
                        break

                    if "<br/><br/>" in metric and index == 0:
                        MetricsDataRow[2] = metric.split("<br/><br/>")[0].replace("\n<td>", "").replace("<strong>", "").replace("</strong>", "")
                        MetricsDataRow[5] = CleanDescription(metric.split("<br/><br/>")[1])

                    else:
                        match index:
                            case 0:
                                MetricsDataRow[2] = metric.split("<br/><br/>")[0].replace("\n<td>", "").replace("<strong>", "").replace("</strong>", "").replace("<code>", "").replace("</code>", "")
                            case 1:
                                MetricsDataRow[1] = metric.replace("<td>", "").replace("</td>", "").replace("<code>", "").replace("</code>", "")
                            case 2:
                                MetricsDataRow[3] = metric.replace("<td>", "").replace("</td>", "").replace("<code>", "").replace("</code>", "")
                            case 3:
                                MetricsDataRow[4] = metric.replace("<td>", "").replace("</td>", "").replace("<code>", "").replace("</code>", "")
                
                MetricsDataContainer.append(MetricsDataRow)
                metricsDataSize += 1


        elif numpy.array_equal(metricsHeaders, ['Category', 'Metric', 'Name in REST API', 'Unit', 'Aggregation', 'Dimensions', 'Time Grains', 'DS Export']):
            for metricRow in metricsContent:
                MetricsDataRow = [0] * 6
                MetricsDataRow[0] = resourceType

                for index, metric in enumerate(metricRow.split("</td>\n<td>")):
                    if index > 4:
                        break

                    if "<br/><br/>" in metric and index == 1:
                        MetricsDataRow[2] = metric.split("<br/><br/>")[0].replace("\n<td>", "").replace("<strong>", "").replace("</strong>", "")
                        MetricsDataRow[5] = CleanDescription(metric.split("<br/><br/>")[1])

                    else:
                        match index:
                            case 1:
                                MetricsDataRow[2] = metric.split("<br/><br/>")[0].replace("\n<td>", "").replace("<strong>", "").replace("</strong>", "").replace("<code>", "").replace("</code>", "")
                            case 2:
                                MetricsDataRow[1] = metric.replace("<td>", "").replace("</td>", "").replace("<code>", "").replace("</code>", "")
                            case 3:
                                MetricsDataRow[3] = metric.replace("<td>", "").replace("</td>", "").replace("<code>", "").replace("</code>", "")
                            case 4:
                                MetricsDataRow[4] = metric.replace("<td>", "").replace("</td>", "").replace("<code>", "").replace("</code>", "")

                MetricsDataContainer.append(MetricsDataRow)
                metricsDataSize += 1

        else:
            print("***Error in table headers: headers have changed and tables may not be uniform or columns have been added/removed***")
            excessivePageChange = True
            return
        
        MetricsData.append(MetricsDataContainer)
        ResultData.append(MetricsData)

    #Gathers all headings and tables
    global results
    results = ResultData

#Initialises page change check in global scope as trigger for page changes in future run times
excessivePageChange = False

#Initialises variable that will hold the bulk of raw h2 and html table elements after inital headings are removed
resultsFiltered = None

#Initialises the count for number of entries in new file
metricsDataSize = 0

#Initialise structeredMetricsData
structuredMetricsData = None

#Removes any remaining html in description resulting from links along with comma removal to prevent issues when writing data to csv
def CleanDescription(description):
    if "<a data-linktype=\"external\" href=\"" in description:
        startSegment = str(description).split("<a data-linktype=\"external\" href=\"")[0]
        link = str(description).split("<a data-linktype=\"external\" href=\"")[1].split("</a>")[0].split(">")[0]
        endSegment = str(description).split("<a data-linktype=\"external\" href=\"")[1].split("</a>")[1]

        return (startSegment + link + endSegment).replace(",", "")
    else:
        return str(description).replace(",", "")

def PrepareDataForWriteToFile():
    global structuredMetricsData
    structuredMetricsData = list([])

    #Csv headings for updated file
    structuredMetricsData.append(["Resource Type", "Metric", "Metric Display Name", "Unit", "Aggregation Type", "Description", "Enable for monitoring", "Tag Name", "Threshold", "Operator", "Eval Frequency", "Window Size", "Aggregation Time", "Alert Name", "Alert Description", "Severity"])

    for resourceData in results:
        resTypeIndex = None
        if resourceData[0] in ResTypeWithSettings:
            for index, resType in enumerate(ResTypeWithSettings):
                if resourceData[0] == resType:
                    resTypeIndex = index
            
            for metric in resourceData[1]:
                currentDataForMetricCheck = False

                for resTypeArrayId in OptimisedSettingsListIndexes[resTypeIndex]:
                    if str(metric[1]) == currentSettings[resTypeArrayId][1]:
                        structuredMetricsData.append([str(metric[0]), str(metric[1]), str(metric[2]), "\"" + str(metric[3]) + "\"", "\"" + str(metric[4]) + "\"", "\"" + str(metric[5]) + "\"", currentSettings[resTypeArrayId][2], currentSettings[resTypeArrayId][3], currentSettings[resTypeArrayId][4], currentSettings[resTypeArrayId][5], currentSettings[resTypeArrayId][6], currentSettings[resTypeArrayId][7], currentSettings[resTypeArrayId][8], currentSettings[resTypeArrayId][9], currentSettings[resTypeArrayId][10], currentSettings[resTypeArrayId][11]])
                        currentDataForMetricCheck = True
                
                if(currentDataForMetricCheck == False):
                    structuredMetricsData.append([str(metric[0]), str(metric[1]), str(metric[2]), "\"" + str(metric[3]) + "\"", "\"" + str(metric[4]) + "\"", "\"" + str(metric[5]) + "\"", "", "", "", "", "", "", "", "", "", ""])

        else:
            for metric in resourceData[1]:
                structuredMetricsData.append([str(metric[0]), str(metric[1]), str(metric[2]), "\"" + str(metric[3]) + "\"", "\"" + str(metric[4]) + "\"", "\"" + str(metric[5]) + "\"", "", "", "", "", "", "", "", "", "", ""])

#Writes supportedMetricsData to csv file -> test
def WriteSupportedMetricsToFile():
    global structuredMetricsData
    arr = numpy.asarray(structuredMetricsData)

    #Adjust file name as neccessary
    numpy.savetxt('./azure_monitoring.csv', arr, fmt = '%s', delimiter=',', encoding="utf-8")

#Run time order in larger function for efficient returns
def runTimeOrder():
    ExtractCurrentSettings()

    #checkpoint
    if(csvColumnIssue):
        print("***Error: Format issue in csv file present***")

    PullHtml()

    #checkpoint
    if(excessivePageChange):
        print("***Error: Initial page check failed***")
        return

    PrepareDataForWriteToFile()
    WriteSupportedMetricsToFile()

runTimeOrder()

#End time for run time and prints run time
end = time.time()
print("Runtime: " + str("%.2f" % round(end - start, 2)) + " seconds")