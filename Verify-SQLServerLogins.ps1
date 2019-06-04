function Verify-SQLServerLogins
{
    [CmdletBinding(SupportsShouldProcess)]
    param 
    (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter] $Source,
        [DbaInstanceParameter] $Destination,
        
        [Alias("Logins")]
        [parameter()]
        [string[]] $LoginList
    )

    <#############################################################################################################################

       Validate the input parameters

    ##############################################################################################################################>
    
        if(!$Source)     { Write-Host "Please provide a value for the Source parameter"      -ForegroundColor Red; break;}
        if(!$Destination){ Write-Host "Please provide a value for the Destination parameter" -ForegroundColor Red; break; }
        if(!$LoginList)  { Write-Verbose "No logins specified, verifying all" }

    <#############################################################################################################################

       Create the data table which will store the login details (e.g. src, dest, hash, sid etc)

    ##############################################################################################################################>
   
        $LoginTable = New-Object System.Data.DataTable;
        [void]$LoginTable.Columns.Add("Login")
        [void]$LoginTable.Columns.Add("Type")
        [void]$LoginTable.Columns.Add("Source")
        [void]$LoginTable.Columns.Add("SourceLoginHash")
        [void]$LoginTable.Columns.Add("SourceLoginSID")
        [void]$LoginTable.Columns.Add("Destination")
        [void]$LoginTable.Columns.Add("DestLoginHash")
        [void]$LoginTable.Columns.Add("DestLoginSID")
        [void]$LoginTable.Columns.Add("Password")
        [void]$LoginTable.Columns.Add("SID")

        # Get the SQL Login script for the source and destination so it can be parsed
        $Src_SQLLoginScript  = (Export-DbaLogin -SqlInstance $Source      -Login $LoginList -ExcludeGoBatchSeparator -WarningAction SilentlyContinue) -split "`r`n"
        $Dest_SQLLoginScript = (Export-DbaLogin -SqlInstance $Destination -Login $LoginList -ExcludeGoBatchSeparator -WarningAction SilentlyContinue) -split "`r`n"

    <#############################################################################################################################

       Loop the source login script to parse the Login, Hashed Pass & SID

    ##############################################################################################################################>
    
        foreach($Line in $Src_SQLLoginScript)
        {
            if($Line -like 'IF NOT EXISTS*')
            {
                # Check whether login is Windows or SQL Authenticated
                if($Line -like '*FROM WINDOWS*')
                {
                    # The square brackets are pre-fixed with a backslash as an escape character
                    $Login = (($Line -split 'CREATE LOGIN \[')[1] -split '\] FROM WINDOWS')[0];
                    $Type  = 'Windows';
                    $SourceHashedPass = "N/A"
                    $SourceSID = "N/A"

                    # Add a new row to the LoginTabe with the values for LoginName, SourceInstance, HashedPass & SID
                    $LoginTable.Rows.Add($Login, $Type, $Source, $SourceHashedPass, $SourceSID, $null, 'N/A', 'N/A', 'N/A', 'N/A') > $null;
                }
                else
                {
                    # The square brackets are pre-fixed with a backslash as an escape character
                    $Login = (($Line -split 'CREATE LOGIN \[')[1] -split '\] WITH PASSWORD')[0];
                    $type  = 'SQL';
                    $SourceHashedPass = (($Line -split 'PASSWORD = '    )[1] -split ' HASHED'         )[0]
                    $SourceSID        = (($Line -split 'SID = '         )[1] -split ', DEFAULT'       )[0]
               
                    # Add a new row to the LoginTabe with the values for LoginName, SourceInstance, HashedPass & SID
                    $LoginTable.Rows.Add($Login, $Type, $Source, $SourceHashedPass, $SourceSID) > $null;
                }
            }
        }

    <#############################################################################################################################

       Loop the destination login script to parse the Login, Hashed Pass & SID

    ##############################################################################################################################>

        foreach($Line in $Dest_SQLLoginScript)
        {
            if($Line -like 'IF NOT EXISTS*')
            {   
                # Check whether login is Windows or SQL Authenticated
                if($Line -like '*FROM WINDOWS*')
                {
                    # The square brackets are pre-fixed with a backslash as an escape character
                    $Login = (($Line -split 'CREATE LOGIN \[')[1] -split '\] FROM WINDOWS')[0];
                }
                else
                {
                    # The square brackets are pre-fixed with a backslash as an escape character
                    $Login = (($Line -split 'CREATE LOGIN \[')[1] -split '\] WITH PASSWORD')[0];
                }
  
                $DestHashedPass = (($Line -split 'PASSWORD = '    )[1] -split ' HASHED'         )[0]
                $DestSID        = (($Line -split 'SID = '         )[1] -split ', DEFAULT'       )[0]

                # Get the row in the LoginTable which contains the current login
                $LoginTableRow = ($LoginTable.Select("Login = '$($Login)'"))[0]

                # Update the LoginTable row with new values for the DestinationInstance, HashedPass & SID
                $LoginTableRow["Destination"]   = $Destination
                
                if($LoginTableRow.Type -eq 'SQL')
                {                
                    $LoginTablerow["DestLoginHash"] = $DestHashedPass
                    $LoginTableRow["DestLoginSID"]  = $DestSID
                }
            }
        }
        
    <#############################################################################################################################

      Update logins which don't exist on the destination

    ##############################################################################################################################>

        $LoginsNotOnDest = $LoginTable.Select("Destination IS NULL")

        foreach($LoginRow in $LoginsNotOnDest)
        { 
            $LoginRow["Destination"] = "Login Not On Dest"; 
        
            if($LoginRow.Type -eq 'SQL')
            {
                 $LoginRow["DestLoginHash"] = 'N/A'
                 $LoginRow["DestLoginSID"]  = 'N/A'
                 $LoginRow["Password"]      = 'N/A'
                 $LoginRow["SID"]           = 'N/A'
            }
        }

    <#############################################################################################################################

       Loop the given logins and perform a comparison on the hashed pass & SID between the source and dest instances

    ##############################################################################################################################>
               
        $Logins = $LoginTable.Login | Select -Unique

        foreach($Login in $Logins)
        {
            # Get the row in the LoginTable which contains the current login
            $LoginTableRow = ($LoginTable.Select("Login = '$($Login)'"))[0]

            if(($LoginTableRow.Type -eq 'SQL') -and ($LoginTableRow.Destination -eq $Destination))
            {
                #*************************************************************************#

                # Check if the source password hash matches the destination password hash
                if($LoginTableRow.SourceLoginHash -eq $LoginTableRow.DestLoginHash)
                {
                    $LoginTableRow["Password"] = 'Synced';
                    Write-Verbose "Password for - $($Login) - Synchronised"
                }
                else
                {
                    $LoginTableRow["Password"] = 'Not-Synced';
                    Write-Verbose "Password for - $($Login) - Out of Sync"
                }

                #*************************************************************************#

                # Check if the source login SID matches the destination login SID
                if($LoginTableRow.SourceLoginSID -eq $LoginTableRow.DestLoginSID)
                {
                    $LoginTableRow["SID"] = 'Synced';
                    Write-Verbose "SID for - $($Login) - Synchronised"
                }
                else
                {
                    $LoginTableRow["SID"] = 'Not-Synced';
                    Write-Verbose "SID for - $($Login) - Out of Sync"
                }

                #*************************************************************************#
            }
        }

    ##############################################################################################################################>

        $LoginTable | Out-GridView 

        # Return the Login Table to the user
        return $LoginTable | Select Login, Type, Source, Destination, Password, SID | FT -AutoSize 

    ##############################################################################################################################>
} 

