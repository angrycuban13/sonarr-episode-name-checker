[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter()]
    [bool]
    $renameSeries = $false
)

#------------- DEFINE VARIABLES -------------#

[string]$sonarrApiKey = ""
[string]$sonarrUrl = ""
[string]$sonarrSeriesStatus = ""


#------------- SCRIPT STARTS -------------#

# Specify location of exclusions file, normally located one directory above the current script.
$seriesExclusionsFile = Join-Path (Get-Item $PSScriptRoot).Parent -ChildPath excludes\name_excludes.txt

# Import the contents of the series exclusion list.
if (Test-Path $seriesExclusionsFile -PathType Leaf){
    $seriesExclusions = Get-Content $seriesExclusionsFile
    Write-Verbose "Exclusions loaded"
}

else {
    throw "Unable to locate exclusions file"
}

# Declare headers that will be passed on each API call.
$webHeaders = @{
    "x-api-key"= "$($sonarrApiKey)"
}

# Retrieve all Sonarr series.
$allSeries = Invoke-RestMethod -Uri "$($sonarrUrl)/api/v3/series" -Headers $webHeaders -StatusCodeVariable apiStatusCode

if ($apiStatusCode -notmatch "2\d\d"){
    throw "Unable to retrieve series from Sonarr"
}

else {
    Write-Verbose "Successfully loaded $($allSeries.count) series from Sonarr"
}

# Filter series with names that match anything in $seriesExclusions and anything that doesn't match the value of sonarrSeriesStatus in the config file.
if ($sonarrSeriesStatus -ne ""){
    $filteredSeries = $allSeries | Where-Object {$_.title -notin $seriesExclusions -and $_.status -eq $($sonarrSeriesStatus)}
}

else {
    $filteredSeries = $allSeries | Where-Object {$_.title -notin $seriesExclusions}
}

Write-Verbose "Series filtering completed, there are now $($filteredSeries.count) series left to process"

# Loop through each $series object in $filteredSeries.
foreach ($series in $filteredSeries){

    # Query API for a list of existing episodes matching the series loaded from $filteredSeries by specifying the series ID.
    $seriesEpisodes = Invoke-RestMethod -Uri "$($sonarrUrl)/api/v3/episodefile?seriesid=$($series.id)" -Headers $webHeaders

    # Filter results from previous command to only include episodes with TBA (case sensitive) or Episode XXXX (case sensitive) in their file path.
    $episodesToRename = $seriesEpisodes | Where-Object {$_.relativepath -cmatch "TBA|Episode [0-9]{1,}"}

    # Grab series ID from episodes filtered and if there are multiple episodes for the same series, only grab the ID once.
    $seriesIdsToRefresh = $episodesToRename | Select-Object -ExpandProperty seriesId -Unique

    # Loop through each $seriesIdToRefresh object in $seriesIdsToRefresh
    foreach ($seriesIdToRefresh in $seriesIdsToRefresh){

        # Grab the series object from $filteredSeries that matches the ID
        $series = $filteredSeries | Where-Object {$_.id -eq $seriesIdToRefresh}

        Write-Verbose "Starting metadata refresh of $($series.Title)"

        # Send command to Sonarr to refresh the series metadata
        $refreshSeries = Invoke-RestMethod -Uri "$($sonarrUrl)/api/v3/command" -Headers $webHeaders -Method Post -ContentType "application/json" -Body "{`"name`":`"RefreshSeries`",`"seriesId`": $($seriesIdToRefresh)}" -StatusCodeVariable apiStatusCode

        if ($apiStatusCode -notmatch "2\d\d"){
            throw "Unable to refresh metadata for $($series.title)"
        }

        Start-Sleep 5

        if ($renameSeries -eq $true){

            Write-Output "Renaming episodes in $($series.title)"

            if ($episodesToRename.seriesid -eq $seriesIdToRefresh){

                $renameCommand = Invoke-RestMethod -Uri "$($sonarrUrl)/api/v3/command" -Headers $webHeaders -Method Post -ContentType "application/json" -Body "{`"name`":`"RenameFiles`",`"seriesId`":$($seriesIdToRefresh),`"files`":[$($episodesToRename.id -join ",")]}" -StatusCodeVariable apiStatusCode

                if ($apiStatusCode -notmatch "2\d\d"){
                    throw "Unable to rename episodes for $($series.title)"
                }
            }
        }
        else {
                Write-Output "$($series.title) has episodes to be renamed"
        }
    }
}
