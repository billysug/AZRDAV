<#  
.SYNOPSIS  
    powershell script to connect to quick start rds deployments after deployment

.DESCRIPTION  
    ** REQUIRES AT LEAST WMF 5.0 AND AZURERM SDK **
    script authenticates to azure rm 
    queries all resource groups for public ip name
    gives list of resource groups
    enumerates public ip of specified resource group
    downloads certificate from RDWeb
    adds cert to local machine trusted root store
    tries to resolve subject name in dns
    if not the same as public loadbalancer ip address it is added to hosts file
 
.NOTES  
   File Name  : art-rds-post-deploy.ps1
   Version    : 161106 made generic for azure rm
   History    : original

.EXAMPLE  
    .\art-rds-post-deploy.ps1
    query azure rm for all resource groups with ip name containing 'GWPIP' by default.
 
.PARAMETER azureResourceManagerGroup
    optional parameter to specify Resource Group Name

.PARAMETER publicIpAddressName
    optional parameter to override ip resource name 'GWPIP'
#>  
 

param(
    [Parameter(Mandatory=$false)]
    [string]$azureResourceManagerGroup,
    [Parameter(Mandatory=$false)]
    [string]$publicIpAddressName = ".",
    [Parameter(Mandatory=$false)]
    [switch]$noretry#,
    #[Parameter(Mandatory=$false)]
    #[string]$clean
)

# to remove certs from all stores Get-ChildItem -Recurse -Path cert:\ -DnsName *<%subject%>* | Remove-Item
# to remove certs from all stores Get-ChildItem -Recurse -Path cert:\ -DnsName *rdsart* | Remove-Item
# Get-AzureRmResourceGroup | Get-AzureRmResourceGroupDeployment | Get-AzureRmResourceGroupDeploymentOperation

$hostsTag = "added by azure script"
$hostsFile = "$($env:windir)\system32\drivers\etc\hosts"
$global:resourceList = {}

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    cls
    $error.Clear()
    $global:resourceList = @{}
    $subList = @{}
    $rg = $null
    $subject = $null
    $certInfo = $null

    # make sure at least wmf 5.0 installed
    if($PSVersionTable.PSVersion -lt [version]5.0.0.0)
    {
        write-host "update version of powershell to at least wmf 5.0. returning" -ForegroundColor Yellow
        start-process "https://www.microsoft.com/en-us/download/details.aspx?id=50395"

        return
    }

    runas-admin

    # authenticate
    try
    {
        Get-AzureRmResourceGroup | Out-Null
    }
    catch
    {
        try
        {
            Add-AzureRmAccount
        }
        catch
        {
            write-host "installing azurerm sdk"
            
            install-module azurerm
            import-module azurerm

            Add-AzureRmAccount
        }
    }

    foreach($sub in get-subscriptions)
    {
        if(![string]::IsNullOrEmpty($sub.SubscriptionId))
        {
            
            Set-AzureSubscription -SubscriptionId $sub.SubscriptionId
            
            write-host "enumerating subscription $($sub.SubscriptionName) $($sub.SubscriptionId)"

            [int]$id = get-resourcegroup
            
            $resourceGroup = $global:resourceList[$id].Values
            $ip = $global:resourceList[$id].Keys
        
            # enumerate resource group
            write-host "provision state: $($resourceGroup.ProvisioningState)"

            if(![string]::IsNullOrEmpty($ip.IpAddress))
            {
                write-host "public loadbalancer ip address: $($ip.IpAddress)"
                $gatewayUrl = "https://$($ip.IpAddress)/RDWeb"
            }

            # get certificate from RDWeb site
            $certFile = [IO.Path]::GetFullPath("$($resourceGroup.ResourceGroupName).cer")
            $cert = get-cert -url $gatewayUrl -fileName $certFile
            if($cert -eq $false -or [string]::IsNullOrEmpty($cert))
            {
                write-host "error:no cert"
                return
            }

            $subject = $cert.Subject.Replace("CN=","")   
        
            if(![string]::IsNullOrEmpty($subject))
            {
                import-cert -certFile $certFile -subject $subject    

                add-hostsEntry -ipAddress $ip -subject $subject
                
                # launch RDWeb site
                Start-Process "https://$($subject)/RDWeb"
            }

        }
    }

    write-host "finished"
}

# ----------------------------------------------------------------------------------------------------------------
function add-hostsentry($ipAddress, $subject)
{
    # see if it needs to be added to hosts file
    $dnsresolve = (Resolve-DnsName -Name $subject).IPAddress
    if($ip.IpAddress -ne $dnsresolve)
    {
        write-host "$($ip.IpAddress) not same as $($dnsresolve), checking hosts file"
        # check hosts file
        [string]$hostFileInfo = [IO.File]::ReadAllText($hostsFile)

        if($hostFileInfo -imatch $subject)
        {
            # remove from hosts file
            [IO.FileStream]$rStream = [IO.File]::OpenText($hostsFile)
            $newhostFileInfo = New-Object Text.StringBuilder
            while($line = $rStream.Readline() -ne $null)
            {
                if(![regex]::IsMatch($line, "(\S+:\S+|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\s+?$($subject)"))
                {
                    $newhostFileInfo.AppendLine($line)
                }
                else
                {
                    write-host "removing $($line) from $($hostsFile)"
                }

            }

            $rStream.Close()
            [IO.File]::WriteAllText($hostsFile, $newhostFileInfo.ToString())
        }

        # add to hosts file
        $newEntry = "$($ip.IpAddress)`t$($subject)`t# $($hostsTag) $([IO.Path]::GetFileName($MyInvocation.ScriptName)) $([DateTime]::Now.ToShortDateString())`r`n"
        write-host "adding new entry:$($newEntry)"
                
        [IO.File]::AppendAllText($hostsFile,$newEntry)
        type $hostsFile

    }
    else
    {
        write-host "dns resolution for $($subject) same as loadbalancer ip:$($ip.IpAddress)"
    }

}

# ----------------------------------------------------------------------------------------------------------------
function get-gatewayUrl($resourceGroup)
{
    write-verbose "get-gatewayUrl $($resourceGroup)"

    $gatewayUrl = [string]::Empty
    # enumerate resource group
    write-host "provision state: $($resourceGroup.ProvisioningState)"
    
    # find public ip from loadbalancer
    $ip = query-publicIp -resourceName $resourceGroup.ResourceGroupName -ipName $publicIpAddressName

    if(![string]::IsNullOrEmpty($ip.IpAddress))
    {
        write-host "public loadbalancer ip address: $($ip.IpAddress)"
        $gatewayUrl = "https://$($ip.IpAddress)/RDWeb"
    }
    
    write-verbose "get-gatewayUrl returning:$($gatewayUrl)"
    return $gatewayUrl
}


# ----------------------------------------------------------------------------------------------------------------
function get-cert([string] $url,[string] $fileName)
{
    
    write-verbose "get-cert:$($url) $($fileName)"

    $webRequest = [Net.WebRequest]::Create($url)
    $webRequest.Timeout = 1000 #ms

    try
    { 
        $webRequest.GetResponse() 
        return $true
    }
    catch { }

    try
    {
        $webRequest = [Net.WebRequest]::Create($url)
        $cert = $webRequest.ServicePoint.Certificate
        $bytes = $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)

        if($bytes.Length -gt 0)
        {
            if([string]::IsNullOrEmpty($filename))
            {
                return $true
            }

            $fileName = [IO.Path]::GetFullPath($fileName)

            if([IO.File]::Exists($fileName))
            {
                [IO.File]::Delete($fileName)
            }

            set-content -value $bytes -encoding byte -path $fileName
            $crt = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $crt.Import($fileName)

            return $crt
        }
        else
        {
            return $false
        }
    }
    catch
    {
        write-verbose "get-cert:error: $($error)"
        $error.Clear()
        return $false
    }
}


# ----------------------------------------------------------------------------------------------------------------
function get-resourcegroup()
{
    write-verbose "get-resourcegroup"
    $resourceGroup = $null
    $id = 0

    # find resource group
    if([string]::IsNullOrEmpty($azureResourceManagerGroup))
    {
        write-host "Azure RM resource groups with public IP addresses. Green indicates RDWeb site:"
        $resourceGroups = Get-AzureRmResourceGroup
        $count = 1
        foreach($resourceGroup in $resourceGroups)
        {
            foreach($pubIp in (query-publicIp -resourceName $resourceGroup.ResourceGroupName -ipName $publicIpAddressName))
            {
                if($pubIp.IpAddress.Length -le 1)
                {
                    continue
                }

                $message = "$($count). $($resourceGroup.ResourceGroupName) $($pubIp.Name) $($pubIp.IpAddress)"

                if((get-cert -url "https://$($pubIp.IpAddress)/RDWeb") -eq $true)
                {
                    write-host $message -ForegroundColor Green
                }
                else
                {
                    write-host $message
                }

                
                write-verbose "`t $($pubIp.Id)"
                
                $global:resourceList.Add($count,@{$pubIp = $resourceGroup})
                $count++
            }

        }

        [int]$id = Read-Host ("Enter number for resource group / ip address to connect to")
        $resourceGroup = Get-AzureRmResourceGroup -Name $global:resourceList[$id].Values.ResourceGroupName

        write-host $resourceGroup.ResourceGroupName
    }
    else
    {
        $resourceGroup = Get-AzureRmResourceGroup -Name $azureResourceManagerGroup
    }


    write-verbose "get-resourcegroup returning:$($resourceGroup | fl | out-string)"

    return $id
}

# ----------------------------------------------------------------------------------------------------------------
function get-subscriptions()
{
    write-verbose "get-subscriptions"
    $subs = Get-AzureSubscription

    if($subs.Count -gt 1)
    {
        $count = 1
        foreach($sub in $subs)
        {
            $message = "$($count). $($sub.SubscriptionName) $($sub.SubscriptionId)"
            $subList.Add($count,$sub.SubscriptionId)
        }

        $count++
        [int]$id = Read-Host ("Enter number for subscription to enumerate or 0 to query all:")
        Set-AzureSubscription -SubscriptionId $subList[$id]

        if($id -ne 0)
        {
            $subs = Get-AzureSubscription -SubscriptionId $subList[$id]
        }
    }

    write-verbose "get-resourcegroup returning:$($subs | fl | out-string)"
    return $subs
}

# ----------------------------------------------------------------------------------------------------------------
function import-cert($certFile, $subject)
{
    write-verbose "import-cert $($certFile) $($subject)"

    # see if cert needs to be imported
    if((Get-ChildItem -Recurse -Path cert:\ -DnsName "$($subject)").Count -lt 1)
    {
        write-host "importing certificate:$($subject) into localmachine root"
        $certFile = [IO.Path]::GetFullPath("$($resourceGroup.ResourceGroupName).cer")
        $certInfo = Import-Certificate -FilePath $certFile -CertStoreLocation Cert:\LocalMachine\Root
    }
    else
    {
        write-host "certificate already installed $($subject)"
    }

}

# ----------------------------------------------------------------------------------------------------------------
function query-publicIp([string] $resourceName, [string] $ipName)
{
    write-verbose "query-publicIp $($resourceName) $($ipName)"

    $count = 0
    $returnList = New-Object Collections.ArrayList
    $ips = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceName
    $ipList = new-object Collections.ArrayList

    foreach($ip in $ips)
    {
        if([string]::IsNullOrEmpty($ip.IpAddress) -or $ip.IpAddress -eq "Not Assigned")
        {
            continue
        }

        if($ip.Name -imatch $ipName -and !$ipList.Contains($ip))
        {
            $ipList.Add($ip)
        }
                
    }

    write-verbose "get-publicIp returning: $($ipList | fl | out-string)"
    return $ipList
}

# ----------------------------------------------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
{
    write-host "Running process $processName $arguments"
    $exitVal = 0
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = $true
    $process.StartInfo.RedirectStandardOutput = $false
    $process.StartInfo.RedirectStandardError = $false
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $false
    $process.StartInfo.WorkingDirectory = get-location
    $process.StartInfo.Verb = "runas"
 
    [void]$process.Start()
    if($wait -and !$process.HasExited)
    {
        $process.WaitForExit($processWaitMs)
        $exitVal = $process.ExitCode
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        write-host "Process output:$stdOut"
 
        if(![String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
        {
            #write-host "Error:$stdErr `n $Error"
            $Error.Clear()
        }
    }
    elseif($wait)
    {
        write-host "Process ended before capturing output."
    }
    
    #return $exitVal
    return $stdOut
}

# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    write-verbose "checking for admin"
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        if(!$noretry)
        { 
            write-host "restarting script as administrator. exiting..."
            Write-Host "run-process -processName "powershell.exe" -arguments $($SCRIPT:MyInvocation.MyCommand.Path) -noretry"
            run-process -processName "powershell.exe" -arguments "$($SCRIPT:MyInvocation.MyCommand.Path) -noretry"
       }
       
       exit 1
   }
    write-verbose "running as admin"
}

# ----------------------------------------------------------------------------------------------------------------
main

