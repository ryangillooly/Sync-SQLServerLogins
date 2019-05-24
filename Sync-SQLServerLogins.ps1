function Sync-SQLServerLogins
{

    [CmdletBinding(SupportsShouldProcess)]
    param 
    (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]   $Source = "",
        [DbaInstanceParameter[]] $Destination = "",
        [string[]]               $IncludeLogins,
        [string[]]               $ExcludeLogins,
        [switch]                 $AlwaysOn,
        [switch]                 $AllAvailabilityGroups,
        [string[]]               $AvailabilityGroups
    )

    # Is the Source and Destination variables provided?
    if($Source -and $Destination)
    {
        # Copy logins from the Source SQL Server to the Destination SQL Server(s). Login removal is not supported.
        Copy-DbaLogin -Source $Source -Destination $Destination -Login $IncludeLogins -ExcludeLogin $ExcludeLogins;
        
        # Synchronise login permissions from the Source SQL Server to the Destination SQL Server(s).
        Sync-DbaLoginPermission -Source $Source -Destination $Destination -Login $IncludeLogins -ExcludeLogin $ExcludeLogins;
    }

    elseif($AlwaysOn)
    {
        # If AlwaysOn is specified, but no Source is given, find the local SQL Instance
        if(!$Source)
        {
            # Find all active SQL Instances on the local machine
            $SQLInstance = Find-DBAInstance -ComputerName LocalHost | ?{$_.Availability -eq 'Available'};

            # If the instance count = 1, set this as the source
            if($SQLInstance.Count -eq 1)
            {
                $Source = $SQLInstance.InstanceName;
            }
            # If the instance count > 1, throw error
            elseif($SQLInstance.Count -gt 1)
            {
                Write-Host 'Please provide a value for $Source as there is multiple SQL Instances on this host.' -ForegroundColor Red;
            }
            # If the instance count = 0, throw error
            elseif($SQLInstance.Count -eq 0)
            {
                Write-Host 'Please provide a value for $Source as no SQL Instances could be found on this host.' -ForegroundColor Red;
            }
        }

        # If AllAGs switch is active, proceed
        if($AllAvailabilityGroups)
        {
            # POpulate AGList with all Availability Groups on Source Instance
            $AGList = Get-DbaAvailabilityGroup -SqlInstance $Source;
        }
        # If specific AGs are specified, proceed
        elseif($AvailabilityGroups)
        {
            # POpulate AGList with all Availability Groups specified
            $AGList = Get-DbaAvailabilityGroup -SqlInstance $Source -AvailabilityGroup $AvailabilityGroups;
        }
        else
        {
            Write-Host '' -ForegroundColor Red;   
        }

        # Initiate Hash Table for the logins we need to copy. This is so we don't duplicate the work
        # As you can have a server level login being mapped to multiple AG databases
        $LoginsToCopy = @{};

        # Loop through the Avaialability Group list and extract login list
        foreach($AG in $AGList)
        {
            if($AG.LocalReplicaRole -eq 'Primary')
            {
                $AGName = $AG.Name
                $AGDatabases = $AG.AvailabilityDatabases.Name

                # Gets DB User + Server Logins for all DBs in AG. Only where the account has DB access and a relevant Server Login 
                $DBLogins = Get-DbaDbUser -SqlInstance $Source -Database $AGDatabases | ?{$_.HasDBAccess -eq $true -and $_.Login -ne ''}

                Get-DBADBUser -SqlInstance $Source -Database

                <#

                    LOOK AT USING PS TO SELECT ALL AG'S WITH ALL DATABASES WHERE REPLICA ROLE IS PRIMARY

                    $ag = get-dbaavailabilitygroup
                    $ag.availabilitydatabases | Seelct Parent, Name etc etc....

                #>
            }
            elseif($AG.LocalReplicaRole -eq 'Secondary')
            {
                Write-Host "The replica role for AG - $($AG.AvailabilityGroup) - is Secondary. Skipped." -ForegroundColor Orange;
                continue;
            }
        }
    }

    # If neither Source/Dest/AlwaysOn provided, throw error
    else
    {
        Write-Host 'Please provide a value for $Source and $Destination, otherwise enable the $AlwaysOn switch' -ForegroundColor Red
    }
}
