import requests
import re
import numpy
import pandas
from bs4 import BeautifulSoup
import time

# Author: David COOK - cubesys
# Created: 25th Jan 2023 (25/1/2023)
# Script Last Updated: 10th Feb 2023 (10/2/2023)
# Supprorted Metrics Page Last Updated At Time Of Script Update: 1st Feb 2023 (1/2/2023)

# Requirements:
# - Requests library (https://pypi.org/project/requests/)
# - numpy library (https://numpy.org/)
# - pandas library (https://pandas.pydata.org/)
# - BeautifulSoup library (https://www.crummy.com/software/BeautifulSoup/bs4/doc/)

# Synopsis: Updates the input csv with the currently supported metrics for azure resource types directly from the Microsoft
# supported metrics page (https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/metrics-supported).

# Description: This script will iterate through the current input csv (azure_monitoring.csv) and gather any current settings for metrics present.
# Once gathered, the script will pull html content from the supported metrics page, before removing the html
# along with organising and structuring the data. From here, the script will start building the data in the required
# structure for the input csv, while matching the previous metric settings to those that will be present in the updated csv.
# Additional checks and removal of html relating to hyperlinks also occurs at this stage. Finally, the structured metrics
# data is written to azure_monitoring.csv.


#Start time for run time
start = time.time()

#Reads in the input file with old supported metrics list and current settings
inputFile = pandas.read_csv("azure_monitoring.csv", encoding='cp1252')

#Initialises current settings and current settings count variables to store any currently set parameters for each metric
currentSettings = None
currentSettingsCount = 0

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

    #Iterates through the original file to count how many metrics have settings present
    for index, row in inputFile.iterrows():
        settingsPresent = False

        for setting in range(6, 14):
            if(not pandas.isna(row[setting]) and settingsPresent != True):
                currentSettingsCount += 1
                settingsPresent = True
                break

    #Instatiates currentSettings and rowCount variables
    currentSettings = [0] * currentSettingsCount
    rowCount = 0

    #Iterates through the original file again, this time pulling out any settings found and placing them in currentSettings
    for index, row in inputFile.iterrows():
        settingsPresent = False

        for setting in range(6, 15):
            if(not pandas.isna(row[setting]) and settingsPresent != True):
                currentSettings[rowCount] = [row[0], row[1], NANtoEmpty(row[6]), NANtoEmpty(row[7]), NANtoEmpty(row[8]), NANtoEmpty(row[9]), NANtoEmpty(row[10]), NANtoEmpty(row[11]), NANtoEmpty(row[12]), NANtoEmpty(row[13]), NANtoEmpty(row[14])]
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

#Pulls Html data for h2 and html table elements
def PullHtml():
    #Scrapes content from microsoft azure supported metrics page
    URL = "https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/metrics-supported"
    page = requests.get(URL)
    soup = BeautifulSoup(page.content, "html.parser")

    #Isolates the content section
    content = soup.find("div", class_="content")

    #Gathers all headings and tables
    global results
    results = content.find_all(["h2", "table"])

#Initialises page change check in global scope as trigger for page changes in future run times
excessivePageChange = False

#Checks for changes in the intial headings that have been gathered
def InitialPageCheck():
    for x in range(0, 5):
        #Previous/current known first 5 headers -> Updated changeCheckArray needed when excessive page changes occur
        changeCheckArray = ["In this article", "Exporting platform metrics to other locations", "Guest OS and host OS metrics", "Table formatting", "Microsoft.AAD/DomainServices"]

        #Formats the headers found at run time
        changeCheck = [0] * 5
        changeCheckTemp = str(results[x]).replace("</h2>", "").split(">")
        changeCheck[x] = changeCheckTemp[1]

        #Checks the headers found at run time against the previous/current known headers
        if(changeCheck[x] != changeCheckArray[x]):
            excessivePageChange = True
            print("***Error: Initial headings retrieved don't match***")
            return

#Initialises variable that will hold the bulk of raw h2 and html table elements after inital headings are removed
resultsFiltered = None

#Filters non-table headings into a clean array
def FilterResults():
    global resultsFiltered
    resultsFiltered = [0] * (len(results) - 5)
    count = 0

    #Filteres initial headings -> will need to be adjusted if additional information is added/removed before the
    #supported metrics tables and headings
    for x in range(4, len(results) - 1):
        resultsFiltered[count] = str(results[x])
        count+=1

#Initialise resultsArray and resultsArrayHalfLength for global scope
resultsArray = None
resultsArrayLengthHalf = 0

#Converts the list of headers and html tables to an array format
def ConvertToArray():
    global resultsArray
    resultsArray = numpy.array(resultsFiltered)

    #alert if array not in the expected structure with heading and table pairs
    if(len(resultsArray) % 2 != 0):
        print("***Error in retrieving supported metric tables: odd number of html tables and headings found***")
        excessivePageChange = True
        return

    global resultsArrayLengthHalf
    resultsArrayLengthHalf = len(resultsArray) // 2

#Html table columns needed -> Metric, Metric Display Name, Unit, Aggregation Type, Description
#Html table column index needed -> 0, 2, 3, 4, 5 (5 out of 7 total columns)

#Initialises the count for number of entries in new file
metricsDataSize = 0

#Calculates the number of entries that will be present in updated file
def SizeCalculation():
    global resultsArray
    global metricsDataSize

    for x in range(0, resultsArrayLengthHalf):
        table = resultsArray[(x * 2) + 1].replace("\n", "").replace("<table>", "").replace("</table>", "").replace("<thead>", "").split("</thead>")
        tableRows = table[1].replace("<tbody>", "").replace("</tbody>", "").split("</td></tr><tr><td>")
        metricsDataSize += len(tableRows)

#Initialise structeredMetricsData
structuredMetricsData = None

#Structures and formats the scraped content from headings and html tables
def BuildMetricsData():
    global structuredMetricsData
    global resultsArray
    global currentSettings
    global ResTypeWithSettings
    global OptimisedSettingsListIndexes

    #Length of structuredMetrics Data and rowTracker count incremented my 1 initially to allow for csv headings
    structuredMetricsData = [0] * (metricsDataSize + 1)
    rowTracker = 1

    #Csv headings for updated file
    structuredMetricsData[0] = ["Resource Type", "Metric", "Metric Display Name", "Unit", "Aggregation Type", "Description", "Enable for monitoring", "Tag Name", "Threshold", "Operator", "Eval Frequency", "Window Size", "Aggregation Time", "Alert Description", "Severity"]

    ResTypeCount = 0

    #Runs through iterations half as long as resultsArray as headings and html tables should be in pairs at this stage
    for x in range(0, resultsArrayLengthHalf):
        block = [0] * 3

        #Isolates heading (resource type) for related html table
        heading = resultsArray[x * 2].replace("</h2>", "").split(">")

        # block[0] -> resource type
        block[0] = heading[1]

        #Isolates html for the current resource type's metric table
        table = resultsArray[(x * 2) + 1].replace("\n", "").replace("<table>", "").replace("</table>", "").replace("<thead>", "").split("</thead>")

        #Isolates table headers
        headers = table[0].replace("<tr><th>", "").replace("</th></tr>", "").split("</th><th>")

        # block[1] -> Headers for the current html table
        block[1] = headers

        tableRows = table[1].replace("<tbody>", "").replace("</tbody>", "").split("</td></tr><tr><td>")

        rows = [0] * len(tableRows)

        for i in range(0, len(tableRows)):
            rows[i] = tableRows[i].replace("<tr><td>", "").split("</td><td>")

        # block[2] -> All rows of data from the current html table
        block[2] = rows

        #Expected headers for html tables
        checkTableHeadersArray = ['Metric', 'Exportable via Diagnostic Settings?', 'Metric Display Name', 'Unit', 'Aggregation Type', 'Description', 'Dimensions']

        #Checks that each table's headers are the same as the currently expected headers
        for k in range(0, len(block[1])):
            if(checkTableHeadersArray[k] != block[1][k]):
                print("***Error in table headers: headers have changed and tables may not be uniform or columns have been added/removed***")
                excessivePageChange = True
                return

        #Initialises settingsPresent and OptimisedSettingsList variables within BuildMetricsData() scope
        settingsPresent = False
        OmpitimisedSettingsList = list([])

        #Checks if there are any settings relating to the current resource type present
        if block[0] in ResTypeWithSettings:
            settingsPresent = True

            #Checks for the next resource type with metrics settings present and moves the safety net "ResTypeCount" up to
            #the last found resource type with settings present to skip earlier iterations that have already been checked
            for x in range(ResTypeCount, len(ResTypeWithSettings)):
                if(ResTypeWithSettings[x] == block[0]):
                    ResTypeCount = x
                    break

            #Gathers metric settings present for current resource type and places them in a list
            for x in OptimisedSettingsListIndexes[ResTypeCount]:
                OmpitimisedSettingsList.append(currentSettings[x])

        #Places isolated metrics data into a nested array that will fit the required structure for the updated csv file 
        for n in range(0, len(tableRows)):
            metricSetting = None

            #Removes any remaining html for hyperlinks with a link type "external"
            if "<a data-linktype=\"external\" href=\"" in block[2][n][5]:
                split = block[2][n][5].split("<a data-linktype=\"external\" href=\"")
                partOne = split[0]
                partTwoSplit = split[1].replace("</a>", "").split(">")
                partTwo = partTwoSplit[1]

                block[2][n][5] = partOne + partTwo

            #Removes any remaining html for hyperlinks with a link type "absolute-path"
            if "<a data-linktype=\"absolute-path\" href=\"" in block[2][n][5]:
                split = block[2][n][5].split("<a data-linktype=\"absolute-path\" href=\"")
                partOne = split[0]
                partTwoSplit = split[1].replace("</a>", "").split(">")
                partTwo = partTwoSplit[1]

                block[2][n][5] = partOne + partTwo

            #Checks the first character of the metric description for a " and removes any quote marks present to prevent
            #the metric description unintentionally being split across multiple columns affectings settings inputs
            if("\"" == block[2][n][5][:1]):
                grammarCheck = block[2][n][5].replace("\"", "")
                block[2][n][5] = grammarCheck

            #Assigns any previously set settings for the metric
            if(settingsPresent):
                for i  in range(0, len(OmpitimisedSettingsList)):
                    if(block[2][n][0] == OmpitimisedSettingsList[i][1]):
                        metricSetting = OmpitimisedSettingsList[i]
                        break

            #Builds row for new metric setting in new file
            if(not metricSetting == None):
                structuredMetricsData[rowTracker + n] = [block[0], block[2][n][0], block[2][n][2], block[2][n][3], block[2][n][4], "\"" + block[2][n][5] + "\"", metricSetting[2], metricSetting[3], metricSetting[4], metricSetting[5], metricSetting[6], metricSetting[7], metricSetting[8], metricSetting[9], metricSetting[10]]
            else:
                structuredMetricsData[rowTracker + n] = [block[0], block[2][n][0], block[2][n][2], block[2][n][3], block[2][n][4], "\"" + block[2][n][5] + "\"", "", "", "", "", "", "", "", "", ""]

        rowTracker += len(tableRows)

#Writes supportedMetricsData to csv file
def WriteSupportedMetricsToFile():
    arr = numpy.asarray(structuredMetricsData)

    #Adjust file name as neccessary
    numpy.savetxt('azure_monitoring.csv', arr, fmt = '%s', delimiter=",", encoding="utf-8")

#Run time order in larger function for efficient returns
def runTimeOrder():
    ExtractCurrentSettings()

    PullHtml()
    InitialPageCheck()

    #checkpoint
    if(excessivePageChange):
        print("***Error: Initial page check failed***")
        return

    FilterResults()
    ConvertToArray()

    #checkpoint
    if(excessivePageChange):
        print("***Error: Falied to filter and convert to array***")
        return

    SizeCalculation()
    BuildMetricsData()

    #checkpoint
    if(excessivePageChange):
        print("***Error: Failed to build metrics data***")
        return

    WriteSupportedMetricsToFile()

runTimeOrder()

#End time for run time and prints run time
end = time.time()
print("Runtime: " + str("%.2f" % round(end - start, 2)) + " seconds")