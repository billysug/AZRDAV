param
(
    [Parameter(Mandatory=$true)]
    [string]$gitUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$destinationFile
)

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $logFile = "$((get-variable myinvocation -scope script).Value.Mycommand.Definition).log"
    log-info "starting: $((get-variable myinvocation -scope script).Value.Mycommand.Definition)"
    get-workingDirectory
        
    
}

# ----------------------------------------------------------------------------------------------------------------
function git-update($updateUrl, $destinationFile)
{
    log-info "get-update:checking for updated script: $($updateUrl)"

    try 
    {
        $git = Invoke-RestMethod -Method Get -Uri $updateUrl 
        $gitClean = [regex]::Replace($git, '\W+', "")

        if(![IO.File]::Exists($destinationFile))
        {
            $fileClean = ""    
        }
        else
        {
            $fileClean = [regex]::Replace(([IO.File]::ReadAllBytes($destinationFile)), '\W+', "")
        }

        if(([string]::Compare($gitClean, $fileClean) -ne 0))
        {
            log-info "copying script $($destinationFile)"
            [IO.File]::WriteAllText($destinationFile, $git)
            return $true
        }
        else
        {
            log-info "script is up to date"
        }
        
        return $false
        
    }
    catch [System.Exception] 
    {
        log-info "get-update:exception: $($error)"
        $error.Clear()
        return $false    
    }
}
# ----------------------------------------------------------------------------------------------------------------

function get-workingDirectory()
{
    $retVal = [string]::Empty
 
    if (Test-Path variable:\hostinvocation)
    {
        $retVal = $hostinvocation.MyCommand.Path
    }
    else
    {
        $retVal = (get-variable myinvocation -scope script).Value.Mycommand.Definition
    }
  
    if (Test-Path $retVal)
    {
        $retVal = (Split-Path $retVal)
    }
    else
    {
        $retVal = (Get-Location).path
        log-info "get-workingDirectory: Powershell Host $($Host.name) may not be compatible with this function, the current directory $retVal will be used."
        
    } 
 
    
    Set-Location $retVal | out-null
 
    return $retVal
}

# ----------------------------------------------------------------------------------------------------------------
function log-info($data, [switch] $nocolor = $false)
{
    try
    {

        $foregroundColor = "White"

        if(!$nocolor)
        {
            if($data.ToString().ToLower().Contains("error"))
            {
                $foregroundColor = "Red"
            }
            elseif($data.ToString().ToLower().Contains("fail"))
            {
                $foregroundColor = "Red"
            }
            elseif($data.ToString().ToLower().Contains("warning"))
            {
                $foregroundColor = "Yellow"
            }
            elseif($data.ToString().ToLower().Contains("exception"))
            {
                $foregroundColor = "Yellow"
            }
            elseif($data.ToString().ToLower().Contains("debug"))
            {
                $foregroundColor = "Gray"
            }
            elseif($data.ToString().ToLower().Contains("information"))
            {
                $foregroundColor = "Green"
            }
        }

        Write-Host $data -ForegroundColor $foregroundColor
        out-file -Append -InputObject "$([DateTime]::Now.ToString())::$([Diagnostics.Process]::GetCurrentProcess().ID)::$($data)" -FilePath $logFile
    }
    catch {}
}

# ----------------------------------------------------------------------------------------------------------------

main
