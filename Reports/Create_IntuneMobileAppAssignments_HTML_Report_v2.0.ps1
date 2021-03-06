# Create HTML Report from all Intune App Assignments
#
# Petri.Paavola@yodamiitti.fi
# Microsoft MVP - Windows and Devices for IT
# 20220329 (updated)
#
# Changelog v2.0:
# - added Application Assignment Filter information to report
#
# version 2.0
#
# https://github.com/petripaavola/Intune
#
# Script downloads AzureADGroup and IntuneApp information from Graph API to local cache   (.\cache)
#
# Created files are:
# .\cache\AllGroups.json
# .\cache\AllApps.json
#
# Downloads also Application icons to local cache to get better looking report.
#
# You can run this once and/or update icons periodically if there were changes in Intune for existing Apps
# New Apps will always get icons downloaded automatically
# .\Create_IntuneMobileAppAssignments_HTML_Report.ps1 -UpdateIconsCache
#
# You can work with cached data without network connection with command
# .\Create_IntuneMobileAppAssignments_HTML_Report.ps1 -UseOfflineCache
#
# You can include images in HTML page in base64 format
# This creates HUGE file sizes so use at your own risk
# .\Create_IntuneMobileAppAssignments_HTML_Report.ps1 -IncludeBase64ImagesInReport
#

Param(
    [Switch]$UseOfflineCache,
    [Switch]$UpdateIconsCache,
    [Switch]$DoNotDownloadAppIcons,
    [Switch]$IncludeIdsInReport,
    [Switch]$IncludeBase64ImagesInReport
)

# Do not download App Icons if we specify to use cached files
if ($UseOfflineCache) {
    $DoNotDownloadAppIcons = $true
}

$ScriptVersion = "ver 2.0"


function Verify-IntuneModuleExistence {

    # Check that we have Intune Powershell Module available
    # either in installed modules or .psd1 file in same directory
    $IntunePowershellModulePath = "$PSScriptRoot/Microsoft.Graph.Intune.psd1"

    # If we don't have Intune module installed
    if (-not (Get-Module -ListAvailable -Name 'Microsoft.Graph.Intune')) {

        # As backup check if we happen to have module as file in our current directory
        if (-Not (Test-Path $IntunePowershellModulePath)) {

            # Intune Powershell module not found!
            Write-Host "Could not find Intune Powershell module (Microsoft.Graph.Intune)"
            Write-Host "You can install Intune module with command: Install-Module -Name Microsoft.Graph.Intune"
            Write-Host "More information: https://github.com/microsoft/Intune-PowerShell-SDK"
            Write-Host "Script will exit..."
            Pause
            Exit 0

        }
        else {
            Import-Module "$IntunePowershellModulePath"
            $Success = $?

            # If import-module import failed
            if (-not ($Success)) {
                # Intune Powershell module import failed!
                Write-Error "Could not load Intune module from file $IntunePowershellModulePath"
                Write-Host "Double check you have Intune Powershell Module installed and try again."
                Write-Host "You can install Intune module with command: Install-Module -Name Microsoft.Graph.Intune"
                Write-Host "More information: https://github.com/microsoft/Intune-PowerShell-SDK"
                Pause
                Exit 0
            }
            else {
                Write-Host "Successfully imported Intune-module from file: $IntunePowershellModulePath"
            }
        }
    }
    else {
        Write-Host "Microsoft.Graph.Intune module found."
        return $true
    }
}

function Convert-Base64ToFile {
    Param(
        [String]$base64,
        $filepath
    )

    $bytes = [Convert]::FromBase64String($base64)
    [IO.File]::WriteAllBytes($filepath, $bytes)
    $Success = $?

    return $Success
}

function Fix-HTMLSyntax {
    Param(
        $html
    )

    $html = $html.Replace('&lt;', '<')
    $html = $html.Replace('&gt;', '>')
    $html = $html.Replace('&quot;', '"')

    return $html
}

function Fix-HTMLColumns {
    Param(
        $html
    )

    # Remove c column and rename column headers
    $html = $html -replace '<th>c</th>',''
    $html = $html -replace '<th>@odata.type</th>','<th>App type</th>'
    $html = $html -replace '<th>displayname</th>','<th>App name</th>'
    $html = $html -replace '<th>assignmentIntent</th>','<th>Assignment Intent</th>'
    $html = $html -replace '<th>assignmentTargetGroupDisplayName</th>','<th>Target Group</th>'
	$html = $html -replace '<th>assignmentFilterDisplayName</th>','<th>Filter name</th>'
	$html = $html -replace '<th>FilterIncludeExclude</th>','<th>Filter Intent</th>'
    $html = $html -replace '<th>publisher</th>','<th>Publisher</th>'
    $html = $html -replace '<th>productVersion</th>','<th>Version</th>'
    $html = $html -replace '<th>filename</th>','<th>Filename</th>'
    $html = $html -replace '<th>createdDateTime</th>','<th>Created</th>'
    $html = $html -replace '<th>lastModifiedDateTime</th>','<th>Modified</th>'

    return $html
}

function Create-GroupingRowColors {
    Param(
        $htmlObject,
        $GroupByAttributeName = 'id'
    )

    $TableRowColor = 'D0E4F5'
    $PreviousRowApplicationID = $null

    Foreach ($App in $htmlObject) {

        $CurrentApplicationID = $App.$GroupByAttributeName

        # Check if current App is with same id than previous
        if (($CurrentApplicationID -eq $PreviousRowApplicationID) -or ($PreviousRowApplicationID -eq $null)) {
            # Same application, no need to change table color (whatever that color is)
            #Write-Verbose "Same, not changing color"
        }
        else {
            # Current row application is different than previous one. We need to change row color.

            # We need to change table color now because application is changing
            if ($TableRowColor -eq 'D0E4F5') {
                $TableRowColor = 'EEEEEE'
            }
            else {
                $TableRowColor = 'D0E4F5'
            }
            #Write-Verbose "Change color to: $TableRowColor"
        }

        # Set attribute c with color information
        # We will use this later with MatchEvaluator regexp
        $App.c = $TableRowColor

        $PreviousRowApplicationID = $CurrentApplicationID
    }

    return $htmlObject
}

function Change-HTMLTableSyntaxWithRegexpForAppsSortedByDisplayName {
    Param(
        $html
    )

    $MatchEvaluatorSortedByAppName = {
        param($match)

        # Change intent cell background color
        $intent = $match.Groups[13].Value

        # Set first letter to capital
        $intent = (Get-Culture).TextInfo.ToTitleCase($intent.tolower())

        # Set Default
        $IntentTD = "<td>$intent</td>"

        if ($intent -like "required*") { $IntentTD = "<td bgcolor=`"lightgreen`"><font color=`"black`">$intent</font></td>" }
        if ($intent -like "uninstall*") { $IntentTD = "<td bgcolor=`"lightSalmon`"><font color=`"black`">$intent</font></td>" }
        if ($intent -like "available*") { $IntentTD = "<td bgcolor=`"lightyellow`">$intent</td>" }
        if ($intent -like "availableWithoutEnrollment*") { $IntentTD = "<td bgcolor=`"lightyellow`">$intent</td>" }
        
        $RowColor = $match.Groups[3].Value
        $AppDisplayName = $match.Groups[10].Value

        # We may want to include AppId for manual debugging if we have several Apps with same names
        # We do not include this by default because last column AppId is so long that it will grow each row height
        # and that doesn't look that good
        if ($IncludeIdsInReport) {
            $id = $match.Groups[17].Value
        }
        else {
            $id = ''
        }

        # This is returned from MatchEvaluator
        
        # Before c column remove
        #"<tr bgcolor=`"$RowColor`"><td></td><td>$($match.Groups[5].Value)</td><td>$($match.Groups[7].Value)</td><td style=`"font-weight:bold`">$AppDisplayName</td>$($IntentTD)$($match.Groups[15].Value)</td><td>$id</td></tr>"

        "<tr bgcolor=`"$RowColor`"><td>$($match.Groups[5].Value)</td><td>$($match.Groups[7].Value)</td><td style=`"font-weight:bold`">$AppDisplayName</td>$($IntentTD)$($match.Groups[15].Value)</td><td>$id</td></tr>"
    }

    # $html1 is now single string object with multiple lines separated by newline
    # We need to convert $html1 to array of String objects so we can do foreach
    # otherwise foreach only sees 1 string and we can't acccess every line individually
    $html = @($html -split '[\r\n]+')

    #<tr><td>D0E4F5</td><td><img src="./cache/37bfa4e6-6c07-42af-847e-7b2ae7d3f4ff.png" height="32" /></td><td>windowsMobileMSI</td><td>7-Zip 16.02 x64</td><td>required</td><td>foobar</td><td>Igor Pavlov</td><td>16.02.00.0</td><td>7z1602-x64.msi</td><td>27.7.2016 16.27.11</td><td>27.7.2016 16.27.11</td><td>37bfa4e6-6c07-42af-847e-7b2ae7d3f4ff</td></tr>
    $regex = '^(<tr>)(<td>)(.*?)(<\/td><td>)(.*?)(<\/td><td>)(.*?)(<\/td>)(<td>)(.*?)(<\/td>)(<td>)(.*?)(<\/td>)(.*)(<td>)([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})(<\/td><\/tr>)$'

    # Do match evaluator regex -> tweak table icon and colors
    # Convert array of string objects back to String with | Out-String
    $html = $html | ForEach-Object { [regex]::Replace($_, $regex, $MatchEvaluatorSortedByAppName) } | Out-String

    return $html
}

function Change-HTMLTableSyntaxWithRegexpForAppsSortedByAssignmentTargetGroupDisplayName {
    Param(
        $html
    )

    # Regexp magic :)
    $MatchEvaluatorSortedByAssignmentTargetGroupDisplayName = {
        param($match)
       
        # Change intent cell background color
        $intent = $match.Groups[13].Value

        # Set first letter to capital
        $intent = (Get-Culture).TextInfo.ToTitleCase($intent.tolower())

        # Set Default
        $IntentTD = "<td>$intent</td>"

        if ($intent -like "required*") { $IntentTD = "<td bgcolor=`"lightgreen`"><font color=`"black`">$intent</font></td>" }
        if ($intent -like "uninstall*") { $IntentTD = "<td bgcolor=`"lightSalmon`"><font color=`"black`">$intent</font></td>" }
        if ($intent -like "available*") { $IntentTD = "<td bgcolor=`"lightyellow`">$intent</td>" }
        if ($intent -like "availableWithoutEnrollment*") { $IntentTD = "<td bgcolor=`"lightyellow`">$intent</td>" }
        
        $RowColor = $match.Groups[3].Value
        $AppDisplayName = $match.Groups[10].Value
        $assignmentTargetGroupDisplayName = $match.Groups[16].Value
        
        # We may want to include AppId for manual debugging
        # We do not include this by default because last column Id is so long that it will grow each row height
        # and that doesn't look that good
        if ($IncludeIdsInReport) {
            $id = $match.Groups[20].Value
        }
        else {
            $id = ''
        }

        # This is returned from MatchEvaluator

        # Before c column remove
        #"<tr bgcolor=`"$RowColor`"><td></td><td>$($match.Groups[5].Value)</td><td>$($match.Groups[7].Value)</td><td>$AppDisplayName</td>$($IntentTD)<td style=`"font-weight:bold`">$assignmentTargetGroupDisplayName</td>$($match.Groups[18].Value)</td><td>$id</td></tr>"

        "<tr bgcolor=`"$RowColor`"><td>$($match.Groups[5].Value)</td><td>$($match.Groups[7].Value)</td><td>$AppDisplayName</td>$($IntentTD)<td style=`"font-weight:bold`">$assignmentTargetGroupDisplayName</td>$($match.Groups[18].Value)</td><td>$id</td></tr>"
    }

    # $html1 is now single string object with multiple lines separated by newline
    # We need to convert $html1 to array of String objects so we can do foreach
    # otherwise foreach only sees 1 string and we can't acccess every line individually
    $html = @($html -split '[\r\n]+')

    $regex = '^(<tr>)(<td>)(.*?)(<\/td><td>)(.*?)(<\/td><td>)(.*?)(<\/td>)(<td>)(.*?)(<\/td>)(<td>)(.*?)(<\/td>)(<td>)(.*?)(<\/td>)(.*)(<td>)([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})(<\/td><\/tr>)$'

    # Do match evaluator regex -> tweak table icon and colors
    # Convert array of string objects back to String with | Out-String
    $html = $html | ForEach-Object { [regex]::Replace($_, $regex, $MatchEvaluatorSortedByAssignmentTargetGroupDisplayName) } | Out-String

    return $html
}

####################################################################################################
# Main starts here

# Really quick and dirty error handling with huge try-catch block
try {

    # Yes we should take true/false return value back here and do messaging and exiting here based on that value
    # But it was so quick to write that staff to function so let's fix that on some later version (like never ?-)
    $return = Verify-IntuneModuleExistence

    # Create cache folder if it does not exist
    if (-not (Test-Path "$PSScriptRoot\cache")) {
        Write-Output "Creating cache directory: $PSScriptRoot\cache"
        New-Item -ItemType Directory "$PSScriptRoot\cache"
        $Success = $?

        if (-not ($Success)) {
            Write-Error "Could not create cache directory ($PSScriptRoot\cache). Check file system rights and try again."
            Write-Output "Script will exit..."
            Pause
            Exit 1
        }
    }

    ###################################################
    # Change schema and get Tenant info

    if (-not ($UseOfflineCache)) {
        try {
            Write-Output "Get tenant information from Graph API and change Graph API schema to beta"

            # We have variables
            # $ConnectMSGraph.UPN
            # $ConnectMSGraph.TenantId

            # Update Graph API schema to beta to get Win32LobApps and possible other new apptypes also
            Update-MSGraphEnvironment -SchemaVersion 'beta'
            $ConnectMSGraph = Connect-MSGraph
            $Success = $?

            if (-not ($Success)) {
                Write-Error "Error connecting to Microsoft Graph API with command Connect-MSGraph."
                Write-Output "Check you have Intune Powershell Cmdlest installed with commmand: Install-Module -Name Microsoft.Graph.Intune"
                Write-Output "Script will exit..."
                Pause
                Exit 1
            }
            else {
                Write-Verbose "Connect-MSGraph succeeded after schema change to beta"
            }

            $TenantDisplayName = Invoke-MSGraphRequest -url "https://graph.microsoft.com/beta/organization/$($ConnectMSGraph.TenantId)?`$select=displayName" | Select-Object -ExpandProperty displayName
            Write-Verbose "Get tenant information with Invoke-MSGraphRequest success: $?"
        }
        catch {
            Write-Error "$($_.Exception.GetType().FullName)"
            Write-Error "$($_.Exception.Message)"
            Write-Error "Error trying to connect to MSGraph."
            Write-Output "Script will exit..."
            Pause
            Exit 1
        }
    }
    else {
        $TenantDisplayName = "(offline)"
    }


    ###################################################
    # Get Intune filters

	try {
		Write-Output "Downloading Intune filters information"
		$url = 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters'
		$MSGraphRequest = Invoke-MSGraphRequest -Url $url -HttpMethod 'GET'
		$Success = $?

		if (-not ($Success)) {
			Write-Error "Error downloading Intune filters information"
			Write-Output "Script will exit..."
			Pause
			Exit 1
		}

		$AllIntuneFilters = Get-MSGraphAllPages -SearchResult $MSGraphRequest
		
		Write-Output "Found $($AllIntuneFilters.Count) Intune filters"

    } catch {
        Write-Error "$($_.Exception.GetType().FullName)"
        Write-Error "$($_.Exception.Message)"
        Write-Error "Error trying to download Intune filters information"
        Write-Output "Script will exit..."
        Pause
        Exit 1
    }

    ###################################################
    # Get AzureADGroups. This should be more efficient than getting AzureADGroup for every assignment one by one

    # Test if we have AllGroups.json file
    if (-not (Test-Path "$PSScriptRoot\cache\AllGroups.json")) {
        Write-Output "Did NOT find AllGroups.json file. We have to get AzureAD Group information from Graph API"
        if ($UseOfflineCache) {
            Write-Host "Run script without option -UseOfflineCache to download necessary AllGroups information`n" -ForegroundColor "Yellow"
            Exit 0
        }
    }

    try {
        if (-not ($UseOfflineCache)) {
            Write-Output "Downloading all AzureAD Security Groups from Graph API (this might take a while)..."
            Write-Verbose "Downloading all AzureAD Security Groups from Graph API"

            # Notice we probably get only part of groups because GraphAPI returns limited number of groups
            $groups = Get-AADGroup -Filter 'securityEnabled eq true'
            $Success = $?

            if (-not ($Success)) {
                Write-Error "Error downloading AzureAD Security Groups"
                Write-Output "Script will exit..."
                Pause
                Exit 1
            }

            # Check if we have value starting https:// in attribute @odate.nextLink
            # If we have nextLink then we get all groups
            if ($groups.'@odata.nextLink' -like "https://*") {
                # Get all groups because we got paged result
                $AllGroups = Get-MSGraphAllPages -SearchResult $groups
                $Success = $?
                if (-not ($Success)) {
                    Write-Error "Error downloading all AzureAD Security Groups with command Get-MSGraphAllPages"
                    Write-Output "Script will exit..."
                    Pause
                    Exit 1
                }
            }
            else {
                $AllGroups = $groups
            }
            Write-Output "AzureAD Group information downloaded."

            # Save to local cache -Depth 2 is default value
            $AllGroups | ConvertTo-Json -Depth 2 | Out-File "$PSScriptRoot\cache\AllGroups.json" -Force
        }
        else {
            Write-Output "Using cached AzureAD Group information from file "$PSScriptRoot\cache\AllGroups.json""
        }

        # Get Group information from cached file always
        $AllGroups = Get-Content "$PSScriptRoot\cache\AllGroups.json" | ConvertFrom-Json

    }
    catch {
        Write-Error "$($_.Exception.GetType().FullName)"
        Write-Error "$($_.Exception.Message)"
        Write-Error "Error trying to download AzureAD Group information"
        Write-Output "Script will exit..."
        Pause
        Exit 1
    }

    ###################################################
    # Test if we have AllGroups.json file
    if (-not (Test-Path "$PSScriptRoot\cache\AllApps.json")) {
        Write-Output "Could NOT find AllApps.json file. We have to get Apps information from Graph API"
        if ($UseOfflineCache) {
            Write-Host "Run script without option -UseOfflineCache to download necessary AllApps information`n" -ForegroundColor "Yellow"
            Exit 0
        }
    }

    try {
        # Get App information from Graph API
        if (-not ($UseOfflineCache)) {
            # Get App information from Graph API
            Write-Output "Downloading Intune App information from Graph API (this might take a while)..."

            # We need assignments info so -Expand assignment option is needed here
            $Apps = Get-DeviceAppManagement_MobileApps -Expand assignments
            $Success = $?

            if (-not ($Success)) {
                Write-Error "Error downloading Intune Applications information"
                Write-Output "Script will exit..."
                Pause
                Exit 1
            }

            # Check if we have value starting https:// in attribute @odate.nextLink
            # If we have nextLink then we get all Apps
            if ($Apps.'@odata.nextLink' -like "https://*") {
                # Get all Apps because we got paged result
                $AllApps = Get-MSGraphAllPages -SearchResult $Apps
                $Success = $?
                if (-not ($Success)) {
                    Write-Error "Error downloading Intune Applications information with command Get-MSGraphAllPages"
                    Write-Output "Script will exit..."
                    Pause
                    Exit 1
                }
            }
            else {
                $AllApps = $Apps
            }
            Write-Output "Intune Application information downloaded"

            # Save to local cache
            # Really important parameter!!! Specify -Depth 4 because Application assignment data will be nested down 4 levels
            $AllApps | ConvertTo-Json -Depth 4 | Out-File "$PSScriptRoot\cache\AllApps.json" -Force

        }
        else {
            Write-Output "Using cached Intune App information from file "$PSScriptRoot\cache\AllApps.json""
        }

        # Get App information from cached file always
        $AllApps = Get-Content "$PSScriptRoot\cache\AllApps.json" | ConvertFrom-Json

    }
    catch {
        Write-Error "$($_.Exception.GetType().FullName)"
        Write-Error "$($_.Exception.Message)"
        Write-Error "Error trying to download Intune Application information"
        Write-Output "Script will exit..."
        Pause
        Exit 1
    }

    ###################################################
    # Find apps which have assignments
    # Check data syntax from GraphAPI with request: https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps?$expand=assignments
    # or convert $Apps to json to get more human readable format: $Apps | ConvertTo-JSON
    # $AppsWithAssignments = $AllApps | Where-Object { $_.assignments.target.groupid -like "*" }

    # Create custom object array and gather necessary app and assignment information.
    $AppsWithAssignmentInformation = @()

    try {
        Write-Output "Creating Application custom object array"

        # Go through each app and save necessary information to custom object
        Foreach ($App in $AllApps) {
            Foreach ($Assignment in $App.Assignments) {
            
                $assignmentId = $Assignment.id
                $assignmentIntent = $Assignment.intent
                $assignmentTargetGroupId = $Assignment.target.groupid
                $assignmentTargetGroupDisplayName = $AllGroups | Where-Object { $_.id -eq $assignmentTargetGroupId } | Select-Object -ExpandProperty displayName
                
				$assignmentFilterId = $Assignment.target.deviceAndAppManagementAssignmentFilterId
				$assignmentFilterDisplayName = $AllIntuneFilters | Where-Object { $_.id -eq $assignmentFilterId } | Select-Object -ExpandProperty displayName
				
				$FilterIncludeExclude = $Assignment.target.deviceAndAppManagementAssignmentFilterType
				if($FilterIncludeExclude -eq 'None') {
					$FilterIncludeExclude = $null
				}
				
                # Special case for All Users
                if ($Assignment.target.'@odata.type' -eq '#microsoft.graph.allLicensedUsersAssignmentTarget') {
                    $assignmentTargetGroupDisplayName = 'All Users'
                }

                # Special case for All Devices
                if ($Assignment.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget') {
                    $assignmentTargetGroupDisplayName = 'All Devices'
                }

                if ($App.licenseType -eq 'offline') {
                    $displayName = "$($App.displayname) (offline)"
                }
                else {
                    $displayName = "$($App.displayname)"
                }

				# Add Application information as tooltip
				# Possible future feature
				# <a href="#" data-toggle="tooltip" title="Another one here too">whatever keytar</a>
				#$displayName = "<a href=`"#`" title=`"Foobar`">$displayName</a>"
				#$displayName = "<a href=`"#`" title='$($App | ConvertTo-Json -Depth 5)'>$displayName</a>"
				#$displayName = "<a href=`"#`" title='$($App | Out-String)'>$displayName</a>"

                # Set included/excluded attribute
                $AppIncludeExclude = ''
                if ($Assignment.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget') {
                    $AppIncludeExclude = 'Included'
                }
                if ($Assignment.target.'@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget') {
                    $AppIncludeExclude = 'Excluded'
                }

                # Remove #microsoft.graph. from @odata.type
                $odatatype = $App.'@odata.type'.Replace('#microsoft.graph.', '')

                $properties = @{
                    '@odata.type'                    = $odatatype
                    displayname                      = $displayName
                    productVersion                   = $App.productVersion
                    publisher                        = $App.publisher
                    filename                         = $App.filename
                    createdDateTime                  = $App.createdDateTime
                    lastModifiedDateTime             = $App.lastModifiedDateTime
                    id                               = $App.id
                    licenseType                      = $App.licenseType
                    assignmentId                     = $assignmentId
                    assignmentIntent                 = "$assignmentIntent $AppIncludeExclude"
                    assignmentTargetGroupId          = $assignmentTargetGroupId
                    assignmentTargetGroupDisplayName = $assignmentTargetGroupDisplayName
                    AppIncludeExclude                = $AppIncludeExclude
					assignmentFilterId				 = $assignmentFilterId
					assignmentFilterDisplayName      = $assignmentFilterDisplayName
					FilterIncludeExclude             = $FilterIncludeExclude
                    icon                             = ""
                    c                                = "D0E4F5"
                }

                # Create new custom object every time inside foreach-loop
                # This is really important step to do inside foreach-loop!
                # If you create custom object outside of foreach then you would edit same custom object on every foreach cycle resulting only 1 app in custom object array
                $CustomObject = New-Object -TypeName PSObject -Prop $properties

                # Add custom object to our custom object array.
                $AppsWithAssignmentInformation += $CustomObject
            }
        }
    }
    catch {
        Write-Error "$($_.Exception.GetType().FullName)"
        Write-Error "$($_.Exception.Message)"
        Write-Error "Error creating Application custom object"
        Write-Output "Script will exit..."
        Pause
        Exit 1
    }

    ###################################################
    # Get App Icons information from cache

    # Left option to NOT to download App Icons
    # Why would anyone would not to have good looking report ?-)
    if ((-not ($DoNotDownloadAppIcons))) {

        $CacheIconFiles = $false
        $CacheIconFiles = Get-ChildItem -File -Path "$PSScriptRoot\cache" -Include '*.jpg', '*.jpeg', '*.png' -Recurse | Select-Object -Property Name, FullName, BaseName, Extension, Length

        # Create array of objects which have App.DisplayName and App.id
        # Sort array and get unique to download icon only once per application (id)
        $AppIconDownloadList = $AppsWithAssignmentInformation | Select-Object -Property id, displayName | Sort-Object id -Unique

        Write-Host "Checking if we need to download App Icons..."
        foreach ($ManagedApp in $AppIconDownloadList) {

            #Write-Verbose "Processing App: $($ManagedApp.displayName)"

            # Initialize variable
            $LargeIconFullPathAndFileName = $null

            #Write-Output "Downloading App icon files to local cache from Graph API for App $($ManagedApp.displayName)"
            
            # Check if we have application icon already in cache folder
            # Use existing icon if found
            $IconFileObject = $null
            $IconFileObject = $CacheIconFiles | Where-Object { $_.BaseName -eq $ManagedApp.id }
            if ($IconFileObject -and (-not ($UpdateIconsCache))) {
                $LargeIconFullPathAndFileName = $IconFileObject.FullName
                #Write-Verbose "Found icon file ($LargeIconFullPathAndFileName) for Application id $($ManagedApp.id)"
                #Write-Output "Found cached App icon for App $($ManagedApp.displayName)"
            }
            else {
                try {
                    # Try to download largeIcon-attribute from application and save file to cache folder
                    Write-Output "Downloading icon for Application $($ManagedApp.displayName) (id:$($ManagedApp.id)"

                    # Get application largeIcon attribute
                    $AppId = $ManagedApp.id
                    $url = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($AppId)?`$select=largeIcon"

                    $appLargeIcon = Invoke-MSGraphRequest -Url $url -HttpMethod GET

                    #Write-Output "Invoke-MSGraphRequest succeeded: $?"

                    #largeIcon      : @{type=image/png; value=iVBORw0KGg
                    #$appLargeIcon.largeIcon.type

                    if (($appLargeIcon.largeIcon.type -ne $null) -and ($appLargeIcon.largeIcon.value -ne $null)) {
                        $filetype = ($appLargeIcon.largeIcon.type).Split('/')[1]
                        $largeIconBase64 = $appLargeIcon.largeIcon.value
                    }
                    else {
                        # There is no largeIcon attribute so we create empty file
                        # We create empty file so we know next time that there was no icon in Graph API
                        # This is workaround not to try find non-existing icons over and over again
                        # To check if icon has been added to Intune requires manual deletion of all zero sized "icon" files and running this script
                        # Or specify option -UpdateIconsCache
                        $filetype = "png"
                        $largeIconBase64 = ''
                    }
        
                    $LargeIconFilename = "$($AppId).$($filetype)"
                    $LargeIconFullPathAndFileName = "$PSScriptRoot\cache\$LargeIconFilename"
                    
                    try {
                        $return = Convert-Base64ToFile $largeIconBase64 $LargeIconFullPathAndFileName
                        Write-Verbose "Convert-Base64ToFile ApplicationId:$AppId $LargeIconFullPathAndFileName success: $return"
                    }
                    catch {
                        Write-Host "Error converting Base64 to file. Continuing to next app..." -ForegroundColor "Red"
                    }
                }
                catch {
                    Write-Host "Error downloading icon for app: $($ManagedApp.displayName). Continuing to next application..." -ForegroundColor "Red"
                }
            }
        }
    } else {
        Write-Host "Skipping App Icon downloads..."
    }
    $AppIconDownloadList = $null

    ########################################################################################################################
    # Create HTML report

    $head = @'
    <style>
    body {
        background-color: #FFFFFF;
    }
    table#TopTable {
        border: 2px solid #1C6EA4;
        background-color: #f7f7f4;
        #width: 100%;
        text-align: left;
        border-collapse: separate;
    }
    table {
    border: 2px solid #1C6EA4;
    background-color: #EEEEEE;
    #width: 100%;
    text-align: left;
    border-collapse: collapse;
    #table-layout: fixed;
    }
    table td {
    border: 2px solid #AAAAAA;
    padding: 5px;
    max-width: 100;
    white-space:nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    #word-wrap:break-word;
    }
    table th {
    border: 2px solid #AAAAAA;
    padding: 5px;
    }
    table#TopTable td, table#TopTable th {
        vertical-align: top;
        text-align: center;
        bgcolor: f7f7f4;
        border: 2px solid #AAAAAA;
        padding: 5px;
        border-collapse: border;
    }
    table tbody td {
    font-size: 15px;
    }
    table thead {
    background: #1C6EA4;
    background: -moz-linear-gradient(top, #5592bb 0%, #327cad 66%, #1C6EA4 100%);
    background: -webkit-linear-gradient(top, #5592bb 0%, #327cad 66%, #1C6EA4 100%);
    background: linear-gradient(to bottom, #5592bb 0%, #327cad 66%, #1C6EA4 100%);
    border-bottom: 2px solid #444444;
    }
    table thead th {
    font-size: 18px;
    font-weight: bold;
    color: #FFFFFF;
    border-left: 2px solid #D0E4F5;
    }
    table#TopTable thead th {
        font-size: 18px;
        font-weight: bold;
        color: #FFFFFF;
        border-left: 2px solid #D0E4F5;
    }
    table thead th:first-child {
    border-left: none;
    }
    table tfoot {
    font-size: 16px;
    font-weight: bold;
    color: #FFFFFF;
    background: #D0E4F5;
    background: -moz-linear-gradient(top, #dcebf7 0%, #d4e6f6 66%, #D0E4F5 100%);
    background: -webkit-linear-gradient(top, #dcebf7 0%, #d4e6f6 66%, #D0E4F5 100%);
    background: linear-gradient(to bottom, #dcebf7 0%, #d4e6f6 66%, #D0E4F5 100%);
    border-top: 2px solid #444444;
    }
    table tfoot td {
    font-size: 16px;
    }
    table tfoot .links {
    text-align: right;
    }
    table tfoot .links a{
    display: inline-block;
    background: #1C6EA4;
    color: #FFFFFF;
    padding: 2px 8px;
    border-radius: 5px;
    }
    .author .img-top {
        display: none;
		position: relative;
        top: 0;
        left: 0;
        z-index: 99;
    }
    .author:hover .img-top {
        display: inline;
		position: relative;
        top: 0;
        left: 0;
        z-index: 99;
    }
	.author:hover .img-back {
        display: none;
		position: relative;
        top: 0;
        left: 0;
        z-index: 99;
    }
    .author .img-back {
        display: inline;
		position: relative;
        top: 0;
        left: 0;
        z-index: 99;
    }
    </style>
'@

    ############################################################
    # Application Summary
    # Create Application summary object for Apps which have assignments
    $ApplicationSummary = $AllApps | Where-object { $_.Assignments } | Select-Object -Property '@odata.type' | Sort-Object -Property '@odata.type' | Group-Object '@odata.type' | Select-Object -Property name, count

    # Remove #microsoft.graph.
    $ApplicationSummary | ForEach-Object { $_.Name = ($_.Name).Replace('#microsoft.graph.', '') }

    $ApplicationSummaryHTML = $ApplicationSummary | ConvertTo-Html -Fragment -PreContent "<h2 id=`"AppAssignmentSummary`">Apps Assignments Summary</h2>" | Out-String

    #### Set icon file path to every app ####
    Foreach ($App in $AppsWithAssignmentInformation) {
        $IconFileName = $App.id

        # Check if icon file exist and it is not zero size
        $IconFile = $null
        $IconFile = Get-ChildItem "$PSScriptRoot\cache\$($IconFileName)*"

        if (($IconFile) -and ($IconFile.Length -gt 0)) {

            $ImageFilePath = $IconFile.FullName
            $ImageType = ($IconFile.Extension).Replace('.', '')

            if ($IncludeBase64ImagesInReport) {
                # Include base64 encoded image in HTML report
                # Creates huge HTML files!!!
                $IconBase64 = [convert]::ToBase64String((Get-Content $ImageFilePath -encoding byte))
                $App.icon = "<img src=`"data:image/$ImageType;base64,$IconBase64`" height=`"25`" />"
            }
            else {
                # Add icon relative path from cache folder
                $App.icon = "<img src=`"./cache/$($IconFile.Name)`" height=`"25`" />"
            }            
        }
        else {
            # There is no icon file so we leave value empty
            $App.icon = 'no_icon'
        }
    }

    ######################
    Write-Output "Create OS specific Application Assignment information HTML fragments."

    try {

        # WindowsAppsSortedByDisplayName

        # Create object with specified attributes and sorting
        $WindowsAppsByDisplayName = $AppsWithAssignmentInformation | Where-object { ($_.'@odata.type' -eq 'microsoftStoreForBusinessApp') -or ($_.'@odata.type' -eq 'officeSuiteApp') -or ($_.'@odata.type' -eq 'win32LobApp') -or ($_.'@odata.type' -eq 'windowsMicrosoftEdgeApp') -or ($_.'@odata.type' -eq 'windowsMobileMSI') -or ($_.'@odata.type' -eq 'windowsUniversalAppX') } | Select-Object -Property c, icon, '@odata.type', displayName, assignmentIntent, assignmentTargetGroupDisplayName, assignmentFilterDisplayName, FilterIncludeExclude, publisher, productVersion, filename, createdDateTime, lastModifiedDateTime, id | Sort-Object displayName, id, assignmentIntent

        # Create grouping colors by id attribute
        $WindowsAppsByDisplayName = Create-GroupingRowColors $WindowsAppsByDisplayName 'id'

        $PreContent = "<h2 id=`"WindowsAppsSortedByAppdisplayName`">Windows Apps Assignments by AppName</h2>"
        $WindowsAppsByDisplayNameHTML = $WindowsAppsByDisplayName | ConvertTo-Html -Fragment -PreContent $PreContent | Out-String

        # Fix &lt; &quot; etc...
        $WindowsAppsByDisplayNameHTML = Fix-HTMLSyntax $WindowsAppsByDisplayNameHTML

        # Change HTML Table TD values with regexp
        # We bold DisplayName, set Intent TD backgroundcolor and set grouped row coloring
        $WindowsAppsByDisplayNameHTML = Change-HTMLTableSyntaxWithRegexpForAppsSortedByDisplayName $WindowsAppsByDisplayNameHTML

        # Fix column names and remove c column
        $WindowsAppsByDisplayNameHTML = Fix-HTMLColumns $WindowsAppsByDisplayNameHTML

        # Debug- save $html1 to file
        #$WindowsAppsByDisplayNameHTML | Out-File "$PSScriptRoot\WindowsAppsByDisplayNameHTML.html"

        ######################
        # AndroidAppsSortedByDisplayName

        # Create object with specified attributes and sorting
        $AndroidAppsByDisplayName = $AppsWithAssignmentInformation | Where-object { ($_.'@odata.type' -eq 'androidManagedStoreApp') -or ($_.'@odata.type' -eq 'managedAndroidStoreApp') -or ($_.'@odata.type' -eq 'managedAndroidLobApp') -or ($_.'@odata.type' -eq 'androidManagedStoreWebApp') } | Select-Object -Property c, icon, '@odata.type', displayName, assignmentIntent, assignmentTargetGroupDisplayName, assignmentFilterDisplayName, FilterIncludeExclude, publisher, productVersion, filename, createdDateTime, lastModifiedDateTime, id | Sort-Object displayName, id, assignmentIntent

        # Create grouping colors by id attribute
        $AndroidAppsByDisplayName = Create-GroupingRowColors $AndroidAppsByDisplayName 'id'

        $PreContent = "<h2 id=`"AndroidAppsSortedByAppdisplayName`">Android Apps Assignments by AppName</h2>"
        $AndroidAppsByDisplayNameHTML = $AndroidAppsByDisplayName | ConvertTo-Html -Fragment -PreContent $PreContent | Out-String

        # Fix &lt; &quot; etc...
        $AndroidAppsByDisplayNameHTML = Fix-HTMLSyntax $AndroidAppsByDisplayNameHTML

        # Change HTML Table TD values with regexp
        # We bold DisplayName, set Intent TD backgroundcolor and set grouped row coloring
        $AndroidAppsByDisplayNameHTML = Change-HTMLTableSyntaxWithRegexpForAppsSortedByDisplayName $AndroidAppsByDisplayNameHTML

        # Fix column names and remove c column
        $AndroidAppsByDisplayNameHTML = Fix-HTMLColumns $AndroidAppsByDisplayNameHTML

        # Debug- save $html1 to file
        #$AndroidAppsByDisplayNameHTML | Out-File "$PSScriptRoot\AndroidAppsByDisplayNameHTML.html"

        ######################
        # iOSAppsSortedByDisplayName

        # Create object with specified attributes and sorting
        $iOSAppsByDisplayName = $AppsWithAssignmentInformation | Where-object { ($_.'@odata.type' -eq 'iosStoreApp') -or ($_.'@odata.type' -eq 'iosVppApp') -or ($_.'@odata.type' -eq 'managedIOSLobApp' -or ($_.'@odata.type' -eq 'managedIOSStoreApp')) } | Select-Object -Property c, icon, '@odata.type', displayName, assignmentIntent, assignmentTargetGroupDisplayName, assignmentFilterDisplayName, FilterIncludeExclude, publisher, productVersion, filename, createdDateTime, lastModifiedDateTime, id | Sort-Object displayName, id, assignmentIntent

        # Create grouping colors by id attribute
        $iOSAppsByDisplayName = Create-GroupingRowColors $iOSAppsByDisplayName 'id'

        $PreContent = "<h2 id=`"iOSAppsSortedByAppdisplayName`">iOS Apps Assignments by AppName</h2>"
        $iOSAppsByDisplayNameHTML = $iOSAppsByDisplayName | ConvertTo-Html -Fragment -PreContent $PreContent | Out-String

        # Fix &lt; &quot; etc...
        $iOSAppsByDisplayNameHTML = Fix-HTMLSyntax $iOSAppsByDisplayNameHTML

        # Change HTML Table TD values with regexp
        # We bold DisplayName, set Intent TD backgroundcolor and set grouped row coloring
        $iOSAppsByDisplayNameHTML = Change-HTMLTableSyntaxWithRegexpForAppsSortedByDisplayName $iOSAppsByDisplayNameHTML

        # Fix column names and remove c column
        $iOSAppsByDisplayNameHTML = Fix-HTMLColumns $iOSAppsByDisplayNameHTML

        # Debug- save $html1 to file
        #$iOSAppsByDisplayNameHTML | Out-File "$PSScriptRoot\iOSAppsByDisplayNameHTML.html"

        ######################
        # macOSAppsSortedByDisplayName

        # Create object with specified attributes and sorting
        $macOSAppsByDisplayName = $AppsWithAssignmentInformation | Where-object { ($_.'@odata.type' -eq 'macOSOfficeSuiteApp') -or ($_.'@odata.type' -eq 'macOSLobApp') -or ($_.'@odata.type' -eq 'macOSMicrosoftEdgeApp') -or ($_.'@odata.type' -eq 'macOsVppApp') } | Select-Object -Property c, icon, '@odata.type', displayName, assignmentIntent, assignmentTargetGroupDisplayName, assignmentFilterDisplayName, FilterIncludeExclude, publisher, productVersion, filename, createdDateTime, lastModifiedDateTime, id | Sort-Object displayName, id, assignmentIntent

        # Create grouping colors by id attribute
        $macOSAppsByDisplayName = Create-GroupingRowColors $macOSAppsByDisplayName 'id'

        $PreContent = "<h2 id=`"macOSAppsSortedByAppdisplayName`">macOS Apps Assignments by AppName</h2>"
        $macOSAppsByDisplayNameHTML = $macOSAppsByDisplayName | ConvertTo-Html -Fragment -PreContent $PreContent | Out-String

        # Fix &lt; &quot; etc...
        $macOSAppsByDisplayNameHTML = Fix-HTMLSyntax $macOSAppsByDisplayNameHTML

        # Change HTML Table TD values with regexp
        # We bold DisplayName, set Intent TD backgroundcolor and set grouped row coloring
        $macOSAppsByDisplayNameHTML = Change-HTMLTableSyntaxWithRegexpForAppsSortedByDisplayName $macOSAppsByDisplayNameHTML

        # Fix column names and remove c column
        $macOSAppsByDisplayNameHTML = Fix-HTMLColumns $macOSAppsByDisplayNameHTML

        # Debug- save $html1 to file
        #$macOSAppsByDisplayNameHTML | Out-File "$PSScriptRoot\macOSAppsByDisplayNameHTML.html"

        ######################
        # WebAppsSortedByDisplayName

        # Create object with specified attributes and sorting
        $WebAppsByDisplayName = $AppsWithAssignmentInformation | Where-object { ($_.'@odata.type' -eq 'webApp') } | Select-Object -Property c, icon, '@odata.type', displayName, assignmentIntent, assignmentTargetGroupDisplayName, assignmentFilterDisplayName, FilterIncludeExclude, publisher, productVersion, filename, createdDateTime, lastModifiedDateTime, id | Sort-Object displayName, id, assignmentIntent

        # Create grouping colors by id attribute
        $WebAppsByDisplayName = Create-GroupingRowColors $WebAppsByDisplayName 'id'

        $PreContent = "<h2 id=`"WebAppsSortedByAppdisplayName`">Web Apps Assignments by AppName</h2>"
        $WebAppsByDisplayNameHTML = $WebAppsByDisplayName | ConvertTo-Html -Fragment -PreContent $PreContent | Out-String

        # Fix &lt; &quot; etc...
        $WebAppsByDisplayNameHTML = Fix-HTMLSyntax $WebAppsByDisplayNameHTML

        # Change HTML Table TD values with regexp
        # We bold DisplayName, set Intent TD backgroundcolor and set grouped row coloring
        $WebAppsByDisplayNameHTML = Change-HTMLTableSyntaxWithRegexpForAppsSortedByDisplayName $WebAppsByDisplayNameHTML

        # Fix column names and remove c column
        $WebAppsByDisplayNameHTML = Fix-HTMLColumns $WebAppsByDisplayNameHTML

        # Debug- save $html1 to file
        #$WebAppsByDisplayNameHTML | Out-File "$PSScriptRoot\WebAppsByDisplayNameHTML.html"

        ######################
        # Other apps
        # If there are @odata.types that weren't specified earlier
        # This makes sure to catch all app types which might be released in the future

        # Create object with specified attributes and sorting
        $OtherAppsByDisplayName = $AppsWithAssignmentInformation | Where-object {`
            ($_.'@odata.type' -ne 'androidManagedStoreApp') -and `
			($_.'@odata.type' -ne 'androidManagedStoreWebApp') -and `
            ($_.'@odata.type' -ne 'managedAndroidStoreApp') -and `
            ($_.'@odata.type' -ne 'managedAndroidLobApp') -and `
            ($_.'@odata.type' -ne 'iosStoreApp') -and `
            ($_.'@odata.type' -ne 'iosVppApp') -and `
            ($_.'@odata.type' -ne 'managedIOSLobApp') -and `
            ($_.'@odata.type' -ne 'managedIOSStoreApp') -and `
            ($_.'@odata.type' -ne 'microsoftStoreForBusinessApp') -and `
            ($_.'@odata.type' -ne 'officeSuiteApp') -and `
            ($_.'@odata.type' -ne 'webApp') -and `
            ($_.'@odata.type' -ne 'win32LobApp') -and `
            ($_.'@odata.type' -ne 'windowsMicrosoftEdgeApp') -and `
            ($_.'@odata.type' -ne 'windowsMobileMSI') -and `
            ($_.'@odata.type' -ne 'windowsUniversalAppX') -and `
            ($_.'@odata.type' -ne 'macOSOfficeSuiteApp') -and `
            ($_.'@odata.type' -ne 'macOSLobApp') -and `
            ($_.'@odata.type' -ne 'macOSMicrosoftEdgeApp') -and `
            ($_.'@odata.type' -ne 'macOsVppApp') }`
        | Select-Object -Property c, icon, '@odata.type', displayName, assignmentIntent, assignmentTargetGroupDisplayName, assignmentFilterDisplayName, FilterIncludeExclude, publisher, productVersion, filename, createdDateTime, lastModifiedDateTime, id | Sort-Object displayName, id, assignmentIntent
            
        # Create grouping colors by id attribute
        $OtherAppsByDisplayName = Create-GroupingRowColors $OtherAppsByDisplayName 'id'

        $PreContent = "<h2 id=`"OtherAppsSortedByAppdisplayName`">Other Apps Assignments by AppName</h2>"
        $OtherAppsByDisplayNameHTML = $OtherAppsByDisplayName | ConvertTo-Html -Fragment -PreContent $PreContent | Out-String

        # Fix &lt; &quot; etc...
        $OtherAppsByDisplayNameHTML = Fix-HTMLSyntax $OtherAppsByDisplayNameHTML

        # Change HTML Table TD values with regexp
        # We bold DisplayName, set Intent TD backgroundcolor and set grouped row coloring
        $OtherAppsByDisplayNameHTML = Change-HTMLTableSyntaxWithRegexpForAppsSortedByDisplayName $OtherAppsByDisplayNameHTML

        # Fix column names and remove c column
        $OtherAppsByDisplayNameHTML = Fix-HTMLColumns $OtherAppsByDisplayNameHTML

        # Debug- save $html1 to file
        #$OtherAppsByDisplayNameHTML | Out-File "$PSScriptRoot\OtherAppsByDisplayNameHTML.html"

        ######################
        # All Apps sorted by assignmentTargetGroupDisplayName

        $htmlObjectAllAppsSortedByAssignmentTargetGroupDisplayName = $AppsWithAssignmentInformation | Select-Object -Property c, icon, '@odata.type', displayName, assignmentIntent, assignmentTargetGroupDisplayName, assignmentFilterDisplayName, FilterIncludeExclude, publisher, productVersion, filename, createdDateTime, lastModifiedDateTime, id | Sort-Object assignmentTargetGroupDisplayName, assignmentIntent, displayName, id

        # Create grouping colors by assignmentTargetGroupDisplayName attribute
        $htmlObjectAllAppsSortedByAssignmentTargetGroupDisplayName = Create-GroupingRowColors $htmlObjectAllAppsSortedByAssignmentTargetGroupDisplayName 'assignmentTargetGroupDisplayName'

        # Working
        $htmlAllAppsSortedByAssignmentTargetGroupDisplayName = $htmlObjectAllAppsSortedByAssignmentTargetGroupDisplayName | ConvertTo-Html -Fragment -PreContent "<h2 id=`"AllAppsSortedByAssignmentTargetGroupDisplayName`">Apps Assignments by target group</h2>" | Out-String

        # Fix html syntax
        $htmlAllAppsSortedByAssignmentTargetGroupDisplayName = Fix-HTMLSyntax $htmlAllAppsSortedByAssignmentTargetGroupDisplayName

        # Change HTML Table TD values with regexp
        # We bold AssignmentTargetGroupDisplayName, set Intent TD backgroundcolor and set grouped row coloring
        $htmlAllAppsSortedByAssignmentTargetGroupDisplayName = Change-HTMLTableSyntaxWithRegexpForAppsSortedByAssignmentTargetGroupDisplayName $htmlAllAppsSortedByAssignmentTargetGroupDisplayName

        # Fix column names and remove c column
        $htmlAllAppsSortedByAssignmentTargetGroupDisplayName = Fix-HTMLColumns $htmlAllAppsSortedByAssignmentTargetGroupDisplayName

        # Debug- save $htmlAllAppsSortedByAssignmentTargetGroupDisplayName to file
        #$htmlAllAppsSortedByAssignmentTargetGroupDisplayName | Out-File "$PSScriptRoot\htmlAllAppsSortedByAssignmentTargetGroupDisplayName.html"

    }
    catch {
        Write-Error "$($_.Exception.GetType().FullName)"
        Write-Error "$($_.Exception.Message)"
        Write-Error "Error creating OS specific HTML fragment information"
        Write-Output "Script will exit..."
        Pause
        Exit 1        
    }
    #############################
    # Create html
    Write-Output "Creating HTML report..."

    try {

        $ReportRunDateTime = (Get-Date).ToString("yyyyMMddHHmm")
        $ReportRunDateTimeHumanReadable = (Get-Date).ToString("yyyy-MM-dd HH:mm")
        $ReportRunDateFileName = (Get-Date).ToString("yyyyMMddHHmm")

        $ReportSavePath = $PSScriptRoot
        $HTMLFileName = "$($ReportRunDateFileName)_Intune_Application_Assignments_report.html"

        #$PreContent = "<table id=`"TopTable`"><tr align=`"center`"><td valign=`"top`" bgcolor=`"f7f7f4`" border=`"5`">`
        $PreContent = "<table id=`"TopTable`"><tr><td>`
        <h1>Intune Application<br>`
        Assignments Report ver 2.0</h1>`
        <p align=`"left`">`
        &nbsp;&nbsp;&nbsp;<strong>Report run:</strong> $ReportRunDateTimeHumanReadable<br>`
        &nbsp;&nbsp;&nbsp;<strong>By:</strong> $($ConnectMSGraph.UPN)<br>`
        &nbsp;&nbsp;&nbsp;<strong>Tenant name:</strong> $TenantDisplayName<br>`
        &nbsp;&nbsp;&nbsp;<strong>Tenant id:</strong> $($ConnectMSGraph.TenantId)`
        </p>`
        <!-- <a href=`"#AppAssignmentSummary`">Application assignment summary</a><br><br> -->`
        <h3>Apps sorted by displayName</h3>`
        <string>`
        <a href=`"#WindowsAppsSortedByAppdisplayName`">Windows Apps</a><br>`
        <a href=`"#AndroidAppsSortedByAppdisplayName`">Android Apps</a><br>`
        <a href=`"#iOSAppsSortedByAppdisplayName`">iOS Apps</a><br>`
        <a href=`"#macOSAppsSortedByAppdisplayName`">macOS Apps</a><br>`
        <a href=`"#WebAppsSortedByAppdisplayName`">Web Apps</a><br>`
        <a href=`"#OtherAppsSortedByAppdisplayName`">Other Apps</a><br>`
        </string>`
        <!-- <h3>Apps sorted by Assignment Group DisplayName</h3> -->`
        <br><h3><a href=`"#AllAppsSortedByAssignmentTargetGroupDisplayName`">All Apps Sorted By Assignment Group Name</a></h3></td>`
        <!-- <td bgcolor=`"f7f7f4`" valign=`"top`" align=`"center`" border=`"5`">$ApplicationSummaryHTML</td> -->`
        <!-- <td bgcolor=`"f7f7f4`" valign=`"top`" border=`"5`"> -->`
        <td>$ApplicationSummaryHTML</td>`
        <td>`
        <h2>Author:</h2>`
        <p><strong>`
        Get more Intune reports and tools from<br>`
        <a href=`"https://github.com/petripaavola/Intune`" target=`"_blank`">https://github.com/petripaavola/Intune</a>`
        <br><br><br><br><br><br>`
        <div class=`"author`">`
            <img src=`"data:image/png;base64,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`" class=`"img-top`" alt=`"Petri Paavola`">`
            <img src=`"data:image/png;base64,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`" class=`"img-back`" alt=`"Petri Paavola`">`
        </div>`
        Petri.Paavola@yodamiitti.fi<br><br>`
        Microsoft MVP<br>`
        Windows and Devices for IT<br><br>`
        <img src=`"data:image/png;base64,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`" alt=`"Microsoft MVP`"><br>`
        </strong></p>`
        </td>`
        </tr></table>"

        $Title = "Intune Application Assignment report"
        ConvertTo-HTML -head $head -PostContent $WindowsAppsByDisplayNameHTML, $AndroidAppsByDisplayNameHTML, $iOSAppsByDisplayNameHTML, $macOSAppsByDisplayNameHTML, $webAppsByDisplayNameHTML, $otherAppsByDisplayNameHTML, $htmlAllAppsSortedByAssignmentTargetGroupDisplayName -PreContent $PreContent -Title $Title | Out-File "$ReportSavePath\$HTMLFileName"
        $Success = $?

        if (-not ($Success)) {
            Write-Error "Error creating HTML file."
            Write-Output "Script will exit..."
            Pause
            Exit 1
        }
        else {
            Write-Output "Intune Application Assignment report HTML file created`n($ReportSavePath\$HTMLFileName)`n"
        }
    }
    catch {
        Write-Error "$($_.Exception.GetType().FullName)"
        Write-Error "$($_.Exception.Message)"
        Write-Error "Error creating HTML report: $ReportSavePath\$HTMLFileName"
        Write-Output "Script will exit..."
        Pause
        Exit 1
    }

    ############################################################

    # Open html file

    # Check file exists and is bigger than 0
    # File should exist already but years ago slow computer/disk caused some problems
    # so this is hopefully not needed workaround
    # Wait max. of 20 seconds

    $i = 0
    $filesize = 0
    do {
        Write-Output "Double check HTML file creation is really done (round $i)"
        $filesize = 0
        Start-Sleep -Seconds 2
        try {
            $HTMLFile = Get-ChildItem "$ReportSavePath\$HTMLFileName"
            $filesize = $HTMLFile.Length
        }
        catch {
            # Something went wrong, waiting for next round.
            Write-Output "Trouble getting file size, waiting 2 seconds and trying again..."
        }
        if ($filesize -eq 0) { Write-Output "Filesize is 0kB so waiting for a while for file creation to finish" }

        $i += 1
    } while (($i -lt 10) -and ($filesize -eq 0))

    Write-Output "Opening created file:`n$ReportSavePath\$HTMLFileName`n"
    try {
        Invoke-Item "$ReportSavePath\$HTMLFileName"
    }
    catch {
        Write-Output "Error opening file automatically to browser. Open file manually:`n$ReportSavePath\$HTMLFileName`n"
    }

}
catch {
    Write-Error "Uups! Something happened and we failed. Try again..."

    Write-Error "$($_.Exception.GetType().FullName)"
    Write-Error "$($_.Exception.Message)"
}

