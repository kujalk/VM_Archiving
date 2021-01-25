$global:VMDataStore =
$global:VMFolder =
$CurrentPath = Get-Location -EA Stop
$Global:Logfile ="{0}\ScriptOutput.log" -f $CurrentPath
$Global:VMMigrationList = @{}

function Write-Log
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Validateset("INFO","ERR","WARN")]
        [string]$Type="INFO"
    )

    $DateTime = Get-Date -Format "MM-dd-yyyy HH:mm:ss"
    $FinalMessage = "[{0}]::[{1}]::[{2}]" -f $DateTime,$Type,$Message

    $FinalMessage | Out-File -FilePath $LogFile -Append
    
    if($Type -eq "ERR")
	{
		Write-Host $FinalMessage -ForegroundColor Red
	}
	else 
	{
		Write-Host $FinalMessage
	}
}

function Migrate-VM
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$VMName,
        [Parameter(Mandatory=$true)]
        [string]$Storage
    )

    try
    {
        Write-Log "Working on VM - $VMName"
        $MigrationTask = Move-VM -VM $VMName -Datastore $Storage -RunAsync -EA Stop
        return ($MigrationTask.Id)
    }
    catch 
    {
        Write-Log "$_" -Type ERR
        return $null
    }
}

#Set annotation
#Move folder
function FinalVM-Setting
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$VMName,
        [Parameter(Mandatory=$true)]
        [string]$Folder
    )

    try
    {
        $MigratedDate = get-date (get-date).AddYears(2) -Format "yyyy-MM-dd"

        Write-Log "Going to set annotation on the VM $VMName"
        Get-VM $VMName -EA Stop | Set-Annotation -CustomAttribute "DateToBeDeleted" -Value $MigratedDate -EA Stop
        Write-Log "Successfully set the annotation to the VM $VMName"
        
        Write-Log "Going to move the VM $VMName to archive folder"
        Move-VM -VM $VMName -Destination $Folder -EA Stop
        Write-Log "Successfully moved the VM $VMName to archive folder "

    }
    catch 
    {
        Write-Log "$_" -Type ERR
    }
}

function Continuos-MigrationCheck
{
    foreach($MigratedVM in $VMMigrationList.Keys)
    {
        try
        {
            $MigrationState = (Get-Task -ID $VMMigrationList.$MigratedVM -EA Stop).State

            if($MigrationState -eq "Error")
            {
                throw "Migration of VM $MigratedVM has failed"
            }
            elseif(($MigrationState -eq "") -or ($MigrationState -eq $null))
            {
                $FinalStore = (Get-VM $MigratedVM -EA Stop | Get-DataStore -EA Stop).Name
                
                #Success, but the task has disappeared. Determined success based on Final Data store
                if($FinalStore -eq $VMDataStore)
                {
                    Write-Log "Job ID is null, but vm $MigratedVM marked success based on final datastore"
                    $VMMigrationList.Remove($MigratedVM)
                    FinalVM-Setting -VMName $MigratedVM -Folder $VMFolder -EA Stop
                }
                else 
                {
                    throw "Job ID found to be null"    
                }
            }

            elseif($MigrationState -eq "Success")
            {
                Write-Log "Job successfully finished on vm $MigratedVM"
                $VMMigrationList.Remove($MigratedVM)
                FinalVM-Setting -VMName $MigratedVM -Folder $VMFolder -EA Stop
                
            }
            #Running state -> No need any action, continously wait
        }
        catch
        {
            Write-Log "Error while checking status of VM $MigratedVM - $_" -Type ERR
            $VMMigrationList.Remove($MigratedVM)
        }        
    }
}

#Main function
try
{  
    
    $vCenter= Read-Host -Prompt "Please enter the Vcenter you want to connect `n" 
    $vCenterUser= Read-Host -Prompt "Enter user name `n"
    $vCenterUserPassword= Read-Host -Prompt "Password `n" -assecurestring
    $credential = New-Object System.Management.Automation.PSCredential($vCenterUser,$vCenterUserPassword)

    Connect-VIServer -Server $vCenter -Credential $credential -EA Stop

    #To avoid timeout
    Set-PowerCLIConfiguration -WebOperationTimeoutSeconds -1 -confirm:$false

	$AllVMs=Get-Folder $VFolder -EA Stop| Get-VM

	foreach($VM in $AllVMs)
	{
        try
        {
            Write-Log "Working on $($VM.Name)"

            #Migrate VM and wait
            $TaskID = Migrate-VM -VMName $VM.Name -Storage $VMDataStore

            if(-not $TaskID)
            {
                throw "Task ID is null. Therefore migration error"
            }

            $VMMigrationList.Add($VM.Name,$TaskID)

            while($VMMigrationList.count -eq 2)
            {
                Start-sleep 90
                Continuos-MigrationCheck -EA Stop
                
            }
        }
        catch
        {
            Write-Log "Migration Failed - $_" -Type ERR
        }      
    }

    #That means, still some migration tasks are running in background
    while($VMMigrationList.count -ne 0)
    {
        Start-sleep 90
        Continuos-MigrationCheck -EA Stop
    }
}
catch
{
    Write-Log "$_" -Type ERR
}