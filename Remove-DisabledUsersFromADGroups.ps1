<#
.SYNOPSIS
Remove-DisabledUsersFromADGroups.ps1 - The script will remove disabled users for groups in ActiveDirectory except for the Domain Users group.

.DESCRIPTION 
The script will remove disabled users for all the groups in ActiveDirectory except for the Domain Users group.

.COMPONENT
The script requires the ActiveDirectory PowerShell module.

.PARAMETER LogFilePath
(Optional)
The path, if specified will be used for the log file and the CSV export files.
If not specified the current folder is used.

.PARAMETER ExportMembers
(Optional)
If this switch is specified the group membership is exported for each group before and after the script has made changes.

.EXAMPLE
.\Remove-DisabledUsersFromADGroups.ps1
Will use the current folder for the log file.
Will not export group memberships to CSV files.

.EXAMPLE
.\Remove-DisabledUsersFromADGroups.ps1 -LogFilePath C:\Temp
Will use the C:\Temp folder for the log file.
Will not export group memberships to CSV files.

.EXAMPLE
.\Remove-DisabledUsersFromADGroups.ps1 -LogFilePath C:\Temp -ExportMembers
Will use the C:\Temp folder for the log file.
Will export group memberships to CSV files.

.NOTES
Written By: Johann van Schalkwyk
Email: johann.vanschalkwyk@cloudessentials.com

Change Log
V1.0, 02/11/2022 - Initial version
V2.1, 07/11/2022 - Updated Error logging for Removal failures
#>

#...................................
# Parameters
#...................................
param
(
    [Parameter(Mandatory=$false,HelpMessage="Define a directory for the log path and membership exports files.")]
    [string]
    $LogFilePath
    ,
    [Parameter(Mandatory=$false,HelpMessage="If specified group membership before and after the script is exported to CSV")]
    [switch]
    $ExportMembers
)

#...................................
# Variables
#...................................

$date = (Get-Date).ToString("ddMMyyyy_HHmmss")

#...................................
# Functions
#...................................

function WriteLog
    {
    Param ([string]$LogString)
    $logdate = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
    $LogMessage = "$Logdate $LogString"
    Add-content $LogFile -value $LogMessage
    }

#...................................
# Script
#...................................
#$ErrorActionPreference = 'SilentlyContinue'
#Check if ActiveDirectory PowerShell module is installed
if (Get-Module -ListAvailable -Name ActiveDirectory)
    {
        Import-Module ActiveDirectory
        Write-Host "Active Directory PowerShell Module imported." -ForegroundColor Green
    }
    else 
        {
            Write-Host "Active Directory PowerShell Module is not instlled" -ForegroundColor Red
            break
        }

#Determine log file and membership export path
if (!$logfilepath)
    {
        $logpath= [System.Environment]::CurrentDirectory
        $LogFile = $logpath+"\Log_RemoveDisabledUsers_"+$date+".txt"

        $exportpath = $logpath + "\GroupMemberExportLists"

        if(!(Test-Path $exportpath))
            {
            WriteLog "Creating Export Folder for member lists."
            New-Item -ItemType Directory -Force -Path $exportpath
            }
            else
                {
                WriteLog "Member export folder already exists."
                }
    }
    else 
        {
            if(Test-Path $logfilepath)
                {
                    $logpath = $logfilepath
                    $LogFile = $logfilepath+"\Log_RemoveDisabledUsers_"+$date+".txt"

                    $exportpath = $logpath + "\GroupMemberExportLists"

                    if(!(Test-Path $exportpath))
                        {
                        WriteLog "Creating Export Folder for member lists."
                        New-Item -ItemType Directory -Force -Path $exportpath
                        }
                        else
                            {
                            WriteLog "Member export folder already exists."
                            }
                }
                else 
                    {
                        Write-Host "Valid log path not specified." -ForegroundColor Red
                        break                    
                    }
        }

#Main section
WriteLog "Prereqs validated, scipt is starting."

#Get list of all disabled users in the Active Directory domain.
WriteLog "Collecting list of disabled AD accounts."
#Write-host "Collecting list of disabled AD accounts." -ForegroundColor Green
$DisabledAccounts = Get-ADUser -Filter * -Property Enabled | Where-Object {$_.Enabled -like "False"} | Select-Object -ExpandProperty SamAccountName

$listfile = $logpath + "\DisabledUserList_" + $date + ".txt"
$DisabledAccounts | Out-File  $listfile
WriteLog "Exporting list of disabled accounts complete."

#Get list of AD Groups to process
WriteLog "Collecting list of AD groups."
#Write-Host "Collecting list of AD groups." -ForegroundColor Green
$ADGroups = Get-ADGroup -SearchBase (Get-ADDomain | Select-Object DistinguishedName).DistinguishedName -SearchScope Subtree -Filter {Name -ne "Domain Users"}
$ADGroupCount = $ADGroups.count
WriteLog "Exported list of AD groups - found $ADGroupCount groups."

#Process AD groups
$i = 0
foreach ($ADGroup in $ADGroups)
    {
        $i++
        $gn = $ADGroup.Name
        WriteLog "Processing Group $i of $ADGroupCount - $gn"
        if ($ADGroupCount -eq 0) {$gpercent = 100} else {$gpercent = $i/$ADGroupCount*100}
        Write-Progress -Activity "Processing Group - $gn" -Status "$i of $ADGroupCount groups" -PercentComplete $gpercent -Id 1
        
        $groupmembers = Get-ADGroupMember -Identity $ADGroup.DistinguishedName | Select-Object SamAccountName
        $groupmembercount = ($groupmembers.name).count

        #Export group members before changes
        if($ExportMembers)
        {
            $memberlistfile = $exportpath + "\" + $gn + "_OriginalGroupMembers_" + $date + ".CSV"
            $groupmembers | Out-File $memberlistfile
            WriteLog "Exported group members - $memberlistfile"
        }
    
        #Remove disabled users from group
        $j = 0
        foreach ($groupmember in $groupmembers)
        {
        $j++
        $mn = $groupmember.SamAccountName
        WriteLog "Processing Groupmember $j of $groupmembercount - $mn"
        if ($groupmembercount -ne 0) {$mpercent = $j/$groupmembercount*100} else {$mpercent = 100}
        Write-Progress -ParentId 1 -Activity "Processing Group Members - $mn" -Status "$j of $groupmembercount group members" -PercentComplete $mpercent
            if ($DisabledAccounts -contains $groupmember.SamAccountName)
                {
                    try {
                        Remove-ADGroupMember -Identity $ADGroup.DistinguishedName -Member $groupmember.SamAccountName -Confirm:$false #-WhatIf
                        WriteLog "Removed User $mn from group."
                    }
                    catch {
                        WriteLog "Failed to remove user $mn from group - Error Message: $_"
                        Write-Host "Failed to remove user $mn from group - Error Message: $_" -ForegroundColor Red
                    }
                }
                else {
                    WriteLog "Skipped User $mn."
                    #Write-Host $groupmember.SamAccountName"is not in the Disabled user list." -ForegroundColor Yellow
                }
        }

        #Export group members after changes
        if($ExportMembers)
            {
                $updatedgroupmembers = Get-ADGroupMember -Identity $ADGroup.DistinguishedName | Select-Object SamAccountName
                $updatedlistfile = $exportpath + "\" + $gn + "_UpdatedGroupMembers_" + $date + ".CSV"
                $updatedgroupmembers | Out-File $updatedlistfile
                WriteLog "Exported updated group members - $updatedlistfile"
            }

    }

WriteLog "Processing of groups has completed"
WriteLog "Script completed"
Write-Host "Log file saved to $logpath"
