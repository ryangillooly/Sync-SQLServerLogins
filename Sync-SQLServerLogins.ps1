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
        # Used to prevent copying logins twice
        $LoginsCopied = @();

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

        # Loop through the Avaialability Group list and extract login list
        foreach($AG in $AGList)
        {
            if($AG.LocalReplicaRole -eq 'Primary')
            {
                $AGName = $AG.Name
                $AGDatabases = $AG.AvailabilityDatabases | Select Name -Unique

                # Gets AG secondary node by removing the current node (primary) from the array
                $AGDest = $AG.AvailabilityReplicas.Name | ?{$_ -ne $AG.SQLInstance}
                 
                # Create array of logins to pass to Copy-DBALogin
                $LoginsToCopy = @();
                
                # Gets DB User + Server Logins for all DBs in AG. Only where the account has DB access and a relevant Server Login 
                $AGDBLogins = Get-DbaDbUser -SqlInstance $Source -Database $AGDatabases | ?{$_.HasDBAccess -eq $true -and $_.Login -ne ''} | Select Login -Unique

                # Loop the database 
                foreach($Login in $AGDBLogins)
                {
                    if($LoginsCopied -contains $Login)
                    {
                        # Login has already been successfully copied
                        Write-Verbose -Message "Login - $($Login) - has already been copied. Skipping.";
                    }
                    elseif($LoginsToCopy -contains $Login)
                    {
                        # Login is currently in the queue to be copied
                        Write-Verbose -Message "Login - $($Login) - is already in the queue to be copied. Skipping.";
                    }
                    else
                    {
                        # Login hasn't been copied or queued, add to copy queue
                        $LoginsToCopy += $Login;
                    }
                } 

                # Attempt to copy the logins in the $LoginsToCopy queue
                try
                {
                    # Copy the logins from the primary to the secondarys
                    Copy-DbaLogin -Source $Source -Destination $AGDest -Login $LoginsToCopy;

                    # Synchronise the logins between the primary and secondarys
                    Sync-DbaLoginPermission -Source $Source -Destination $AGDest -Login $LoginsToCopy;

                    # Add the logins to the $LoginTracker now they have been synchronised
                    $LoginsCopied += $LoginsToCopy;
                }
                catch
                {
                    Write-Host "Error whilst copying / synchronising the logins from [$($Source)] to [$($AGDest)]" -ForegroundColor Red;
                }
                finally
                {
                    # Clear the LoginsToCopy queue
                    $LoginsToCopy = @();
                }
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
