# yes
# 
# File      RemoveApps.ps1
# 
# Version   1.3 
# 
# Author    Michael Niehaus 
#
# Purpose   Removes some or all of the in-box apps on Windows 8, Windows 8.1,
#            or Windows 10 systems.  The script supports both offline and
#            online removal.  By default it will remove all apps, but you can
#            provide a separate RemoveApps.xml file with a list of apps that
#            you want to instead remove.  If this file doesn't exist, the
#            script will recreate one in the log or temp folder, so you can
#            run the script once, grab the file, make whatever changes you
#            want, then put the file alongside the script and it will remove
#            only the apps you specified.
#
# Usage     This script can be added into any MDT or ConfigMgr task sequences.
#            It has a few dependencies
#              1.  For offline use in Windows PE, the .NET Framework, 
#                  PowerShell, DISM Cmdlets, and Storage cmdlets must be 
#                  included in the boot image.
#              2.  Script execution must be enabled, e.g. Set-ExecutionPolicy
#                  Bypass.  This can be done via a separate task sequence 
#                  step if needed, see httpblogs.technet.commniehaus for
#                  more information.
#
# ------------- DISCLAIMER -------------------------------------------------
# This script code is provided as is with no guarantee or warranty concerning
# the usability or impact on systems and may be used, distributed, and
# modified in any way provided the parties agree and acknowledge the 
# Microsoft or Microsoft Partners have neither accountabilty or 
# responsibility for results produced by use of this script.
#
# Microsoft will not provide any support through any means.
# ------------- DISCLAIMER -------------------------------------------------
#
# 

# Updated 08.06.2018 - Added logic to remove apps from created profiles 
# (Get-AppxPackage -AllUsers)


# ---------------------------------------------------------------------------
# Get-LogDir  Return the location for logs and output files
# ---------------------------------------------------------------------------

function Get-LogDir
{
  try
  {
    $ts = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
    if ($ts.Value("LogPath") -ne"")
    {
      $logDir = $ts.Value("LogPath")
    }
    else
    {
      $logDir = $ts.Value("_SMSTSLogPath")
    }
  }
  catch
  {
    $logDir = $env:TEMP
  }
  return $logDir
}

# ---------------------------------------------------------------------------
# Get-AppList  Return the list of apps to be removed
# ---------------------------------------------------------------------------

function Get-AppList
{
  begin
  {
    # Look for a config file.
    $configFile = "$PSScriptRoot\RemoveApps.xml"
    if (Test-Path -Path $configFile)
    {
      # Read the list
      Write-Verbose "Reading list of apps from $configFile"
      $list = Get-Content $configFile
    }
    else
    {
      # No list? Build one with all apps.
      Write-Verbose "Building list of provisioned apps"
      $list = @()
      if ($script:Offline)
      {
        Get-AppxProvisionedPackage -Path $script:OfflinePath | % { $list += $_.DisplayName }
      }
      else
      {
        Get-AppxProvisionedPackage -Online | % { $list += $_.DisplayName }
      }

      # Write the list to the log path
      $logDir = Get-LogDir
      $configFile = "$logDir\RemoveApps.xml"
      $list | Set-Content $configFile
      Write-Information "Wrote list of apps to $logDir\RemoveApps.xml, edit and place in the same folder as the script to use that list for future script executions"
    }

    Write-Information "Apps selected for removal $list.Count"
  }

  process
  {
    $list
  }

}

# ---------------------------------------------------------------------------
# Remove-App  Remove the specified app (online or offline)
# ---------------------------------------------------------------------------

function Remove-App
{
  [CmdletBinding()]
  param (
        [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string] $appName
  )

  begin
  {
    # Determine offline or online
    if ($script:Offline)
    {
      $script:Provisioned = Get-AppxProvisionedPackage -Path $script:OfflinePath
    }
    else
    {
      $script:Provisioned = Get-AppxProvisionedPackage -Online
      $script:AppxPackages = Get-AppxPackage
      $script:AppxPackagesAU = Get-AppxPackage -AllUsers
    }
  }

  process
  {
    $app = $_

    # Remove the provisioned package
    Write-Information "Removing provisioned package $_"
    $current = $script:Provisioned | ? { $_.DisplayName -eq $app }
    if ($current)
    {
      if ($script:Offline)
      {
        $a = Remove-AppxProvisionedPackage -Path $script:OfflinePath -PackageName $current.PackageName
      }
      else
      {
        $a = Remove-AppxProvisionedPackage -Online -PackageName $current.PackageName
      }
    }
    else
    {
      Write-Warning "Unable to find provisioned package $_"
    }

    # If online, remove installed apps too
    if (-not $script:Offline)
    {
      Write-Information "Removing installed package $_"
      $current = $script:AppxPackages | ? {$_.Name -eq $app }
      $currentAU = $script:AppxPackagesAU | ? {$_.Name -eq $app }
      if ($current)
      {
        $current | Remove-AppxPackage
      }
      elseif ($currentAU)
      {
        $currentAU | Remove-AppxPackage
      }
      {
        Write-Warning "Unable to find installed app $_"
      }
    }

  }
}

function Get-OnlineCapabilities
{

#New PSObject Template
$DismObjT = New-Object –TypeName PSObject -Property @{
    "Name" = ""
    "State" = ""
    }

#Creating Blank array for holding the result
$objResult = @()

#Read current values
$dismoutput = Dism /online /Get-Capabilities /limitaccess

#Counter for getting alternate values
$i = 1

#Parsing the data

$DismOutput | Select-String -pattern "Capability Identity :", "State :" |  
    ForEach-Object{


        if($i%2)
        {

            #Creating new object\Resetting for every item using template
            $TempObj = $DismObjT | Select-Object *

            #Assigning Value1
            $TempObj.Name = ([string]$_).split(":")[1].trim() ;$i=0
        }
        else
        {
            #Assigning Value2
            $TempObj.State = ([string]$_).split(":")[1].trim() ;$i=1
            
            #Incrementing the object once both values filled
            $objResult+=$TempObj
        } 

    }

    Return $objResult
}


function Get-CapabilityList
{
  begin
  {
    # Look for a config file.
    $configFile = "$PSScript\RootRemoveCapabilities.xml"
    if (Test-Path -Path $configFile)
    {
      # Read the list
      write-verbose "Reading list of Capabilities from $configFile"
      $list = Get-Content $configFile
    }
    else
    {
      # No list Build one with all Capabilities.
      write-verbose "Building list of Installed Capabilities"
      $list = @()
      if ($script:Offline)
      {
        Get-WindowsCapability -Path $script:OfflinePath | % { If ($_.Name -like '*App*') { $list += $_.Name } }
      }
      else
      {
        Get-OnlineCapabilities | % { If ($_.Name -like '*App*') { $list += $_.Name } }
      }

      # Write the list to the log path
      $logDir = Get-LogDir
      $configFile = "$logDir\RemoveCapabilities.xml"
      $list | Set-Content $configFile
      write-information "Wrote list of Apps in Windows Capabilities to $logDir\RemoveCapabilities.xml, edit and place in the same folder as the script to use that list for future script executions"
    }

    write-information "Capability Apps selected for removal: $list.Count"
  }

  process
  {
    $list
  }

}

function Remove-Capability
{
  [CmdletBinding()]
  param (
        [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string] $CapabilityName
  )

  begin
  {
    # Determine offline or online
    if ($script:Offline)
    {
      $script:Capability = Get-WindowsCapability -Path $script:OfflinePath
    }
    else
    {
      $script:Capability = Get-OnlineCapabilities
    }
  }

  process
  {
    $Windows:Capability = $_

    # Remove the provisioned package
    write-information "Removing Windows Capability $_"
    $current = $script:Capability | ? { $_.Name -eq $WindowsCapability -and $_.State -eq 'Installed' }
    if ($current)
    {
      if ($script:Offline)
      {
        $a = Remove-WindowsCapability -Path $script:OfflinePath -Name $current.Name
      }
      else
      {
        $a = Remove-WindowsCapability -Online -Name $current.Name
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------

$logDir = Get-LogDir
Start-Transcript "$logDir\RemoveApps.log"

if ($env:SYSTEMDRIVE -eq "X:")
{
  $script:Offline = $true
  Write-Output "Script running in WinPE. Now searching for Offline Windows Drive."

  # Find Windows
  $drives = get-volume | ? {-not [String]::IsNullOrWhiteSpace($_.DriveLetter) } | ? {$_.DriveType -eq 'Fixed'} | ? {$_.DriveLetter -ne 'X'}
  $drives | ? { Test-Path "$($_.DriveLetter):\Windows\System32"} | % { $script:OfflinePath = "$($_.DriveLetter):\" }
  Write-output "Eligible offline drive found: $script:OfflinePath"
  $dismout = dism /image:$script:offlinepath /get-currentedition
  $version = ($dismout | % { If ($_ -Like 'Image Version:*') {$_}}).Split(" ")[2]
  [int]$Build = $version.Split(".")[2] -as [int]
  Write-output "Offline Image Build = $Build"
}
else
{
  Write-Verbose "Running in the full OS."
  $script:Offline = $false
  [int]$Build = [System.Environment]::OSVersion.Version.Build
  Write-verbose "Online OS build = $Build"
}

Get-AppList | Remove-App

If ($Build -ge 14393)
{
    Get-CapabilityList | Remove-Capability
}
Else
{
    write-verbose "Removing `"ContactSupport, WindowsFeedback, and InsiderHub`" Apps by renaming there provisioning package files by pre-pending `Backup-`."
    If ($script:Offline)
    {
        $Drive = $script:OfflinePath
    }
    Else
    {
        $Drive = $env:SYSTEMDRIVE
    }
    $Path = "$Drive\Windows\SystemApps"
    Get-ChildItem -Path $Path -Filter ContactSupport* | % { Rename-Item $_ Backup-$_ }
	Get-ChildItem -Path $Path -Filter WindowsFeedback* | % { Rename-Item $_ Backup-$_ }
	Get-ChildItem -Path $Path -Filter InsiderHub* | % { Rename-Item $_ Backup-$_ }
}

Stop-Transcript
