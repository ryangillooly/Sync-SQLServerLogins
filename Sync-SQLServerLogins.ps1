﻿function Sync-SQLServerLogins
{

    [CmdletBinding(SupportsShouldProcess)]
    param 
    (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]   $Source = "localhost\SQL2019",
        [PSCredential]           $SourceSqlCredential,
        [DbaInstanceParameter[]] $Destination = "localhost\SQLExpress",
        [PSCredential]           $DestinationSqlCredential,
        [string[]]               $IncludeLogins,
        [string[]]               $ExcludeLogins
    )

    $ListOfAOAGs = Get-DbaAvailabilityGroup -SqlInstance $Source | Select AvailabilityGroup;

    foreach($AOAG in $ListOfAOAGs)
    {

        # Copy all the logins from Source to Destination and log results to $SourceLoginList variable
        $SourceLoginList = Copy-DbaLogin -Source $SourceInstance -Destination $DestInstance;

        # Create login array of all the logins we need to re-sync between instances
        $LoginsToSync = $SourceLoginList | ?{$_.Notes  -eq 'Already exists on destination'} | Select Name;

        # List all the logins which were successfully copied to the destination instance
        $LoginsCopied = $SourceLoginList | ?{$_.Status -eq 'Successful'} | Select Name;

        # List all the logins which were skipped/failed
        $LoginsFailed = $SourceLoginList | ?{$_.Status -eq 'Skipped' -and $_.Notes -ne 'Already exists on destination'} | Select Name;

        # Synchronises the logins between source and destination using the login list from $LoginsToSync         # Enable Verbose below for error troubleshooting
        Sync-DbaLoginPermission -Source $Source -Destination $Destination -Login $LoginsToSync.Name     # -Verbose
    }
}

