$Vfolder = ""

CurrentPath = Get-Location -EA Stop
$Global:Logfile ="{0}\ScriptOutput.log" -f $CurrentPath

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

try 
{
	clear
	
	Write-Host "
	Warning - This is a deletion script. Be careful of what you are doing
	" -ForegroundColor Yellow

	$vCenter= Read-Host -Prompt "Please enter the Vcenter you want to connect `n" 
    	$vCenterUser= Read-Host -Prompt "Enter user name `n"
   	$vCenterUserPassword= Read-Host -Prompt "Password `n" -assecurestring
    	$credential = New-Object System.Management.Automation.PSCredential($vCenterUser,$vCenterUserPassword)

	Connect-VIServer -Server $vCenter -Credential $credential -EA Stop

	#To avoid timeout
	Set-PowerCLIConfiguration -WebOperationTimeoutSeconds -1 -confirm:$false
	
	$AllVMs=Get-Folder $VFolder -EA Stop | Get-VM

	foreach($VM in $AllVMs)
	{
		try
		{
			Write-Log "Working on VM $($VM.Name)"

			$DateObject=Get-Annotation -Entity $VM -EA Stop| where-object{$_.Name -eq "DateToBeDeleted"}

			if($DateObject.value)
			{
				if((Get-Date $DateObject.value) -lt (Get-Date))
				{
					Write-Log "VM is expired and Will delete the VM $($VM.Name)"
					Write-Log "VM DataToBeDeleted value is $($DateObject.value)"
					Remove-VM -VM $VM.Name -DeletePermanently -Confirm:$false -EA Stop
					Write-Log "Successfully deleted the VM"
				}
				else 
				{
					Write-Log "VM $($VM.Name) is not expired. Data Tag value is Write-Log $($DateObject.value)"	
				}
			}
			else 
			{
				Write-Log "No any Tag value found for VM $($VM.Name)"	
			}
		}
		catch
		{
			Write-Log "Error occured - $_" -Type ERR
			continue
		}
		
	}

	Write-Log "Done with this script"
}
catch 
{
	Write-Log "Script exit with error - $_" -Type ERR
}
