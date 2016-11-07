<#  
.SYNOPSIS  
    powershell script to query azure rm logs

.DESCRIPTION  
    script authenticates to azure rm 
    runs get-azurermlog
    colors certain event operations 
    displays events in console and listbox
    in listbox allows for viewing specific events under operation

.NOTES  
   Originator : jgilber
   File Name  : azur-rm-log-reader.ps1
   Version    : 161107 added deployments
   History    : 161106 original

.EXAMPLE  
    .\azur-rm-log-reader.ps1
    query azure rm for all resource manager logs
 
.PARAMETER detail
    optional parameter to log information to console

#>  

param (
    [switch]$detail=$false,
    [string]$resourceGroupName
)

#$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName PresentationFramework            
Add-Type -AssemblyName PresentationCore  

$global:command = "get-azurermlog -DetailedOutput"
$global:deploymentcommand = "Get-AzureRmResourceGroupDeployment -ResourceGroupName"
$global:listbox = $null
$global:inputTextBox = $null
$global:index = @{}
$global:creds
$global:window = $null
$timer = new-object Windows.Threading.DispatcherTimer
$error.Clear()
$refreshTime = "0:1:00.0"
$global:completed = 0
$global:eventStartTime = [DateTime]::MinValue

#Get-AzureRmResourceGroupDeployment -ResourceGroupName rdsdepjag2

#-------------------------------------------------------------------------------------------------------------------------------
function main()
{
     # authenticate
    try
    {
        Get-AzureRmResourceGroup | Out-Null
    }
    catch
    {
        Add-AzureRmAccount
    }

    [xml]$xaml = @"
    <Window 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="Window" Title="main" WindowStartupLocation = "CenterScreen" ResizeMode="CanResize"
        ShowInTaskbar = "True" Background = "lightgray"> 
        <DockPanel>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="25" />
                <RowDefinition Height="20" />
                <RowDefinition Height="*" />
            </Grid.RowDefinitions>
            <Label x:Name="labelInputTextBox" Grid.Row="0" Content="Resource Group Name:" Width="150" Margin="0,0,0,0" HorizontalAlignment="Left"/>
            <TextBox x:Name="inputTextBox" Grid.Row="0" Margin="150,0,0,0" HorizontalAlignment="Stretch"/>
            <Button x:Name="refreshButton" Content="Refresh" Grid.Row="1"/>
            <ListBox x:Name="listbox" Grid.Row="2" Height="Auto">
           </ListBox>
           </Grid>
      </DockPanel>
    </Window>
"@
    $global:Window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    
    #Connect to Controls
    $refreshButton = $global:Window.FindName('refreshButton')
    $global:listbox = $global:Window.FindName('listbox')
    $global:inputTextBox = $global:Window.FindName('inputTextBox')
    $global:inputTextBox.Text = $resourceGroupName

    $listbox.Add_SelectionChanged({open-event})
    $listbox.Items.SortDescriptions.Add((new-object ComponentModel.SortDescription(“Content”, [ComponentModel.ListSortDirection]::Descending)));
    
    $global:Window.Add_Loaded({

        $timer.Add_Tick({
            write-host "." -NoNewline
            run-commands

            if($global:completed)
            {
                $timer.Stop()
            }
        })

        $timer.Interval = [TimeSpan]$refreshTime
        #Start timer
        $timer.Start()
    })

    #Events

    $refreshButton.Add_Click({ run-commands })
    
    run-commands    

     try
     {
        $global:Window.ShowDialog()
     }
     finally
     {
        $global:completed = 1
        $timer.Stop()
     }
 
}

#-------------------------------------------------------------------------------------------------------------------------------
function get-localTime($utcTime)
{
    return [System.TimeZoneInfo]::ConvertTimeFromUtc($utcTime, [System.TimeZoneInfo]::Local)
}

#-------------------------------------------------------------------------------------------------------------------------------
function run-commands()
{
    $localTime = get-localTime -utcTime $global:eventStartTime
    if($localTime -ne [DateTime]::MinValue)
    {
        run-command -command "$($global:command) -StartTime `'$($localTime)`'"
    }
    else
    {
        run-command -command $global:command
    }

    if(![string]::IsNullOrEmpty($global:inputTextBox.Text))
    {
        run-command -command "$($global:deploymentcommand) $($global:inputTextBox.Text)"
    }
}

#-------------------------------------------------------------------------------------------------------------------------------
function is-deployment($items)
{

    if($items.Count -gt 0 -and $items[0].EventTimeStamp -ne $null)
    {
        return $false
    }
    elseif($items.Count -gt 0 -and $items[0].TimeStamp -ne $null)
    {
        return $true
    }

    return $null
}      

#-------------------------------------------------------------------------------------------------------------------------------
function run-command($command)
{
    try
    {
        $items = Invoke-Expression $command

        if($items.Count -lt 1)
        {
            return
        }

        if(is-deployment -items $items)
        {
            foreach($item in ($items | Sort-Object Timestamp))
            {
                add-depitem -lbitem $item -color "Magenta"
            }      
        }
        else
        {
            foreach($item in ($items | Sort-Object EventTimestamp))
            {
                add-item -lbitem $item -color "Yellow"
            }      
        }
    }
    catch
    {
        write-host "Exception:run-command $($error)"
    }

}

#-------------------------------------------------------------------------------------------------------------------------------
function add-item($lbitem, $color)
{

    [Windows.Controls.ListBoxItem]$lbi = new-object Windows.Controls.ListBoxItem
    $lbi.Background = $color
    $failed = $false

    if($lbitem.Status -imatch "Fail")
    {
        $lbi.Background = "Red"
        $failed = $true
    }
    elseif($lbitem.Status -imatch "Succeeded")
    {
        $lbi.Background = "LightBlue"
    }
    elseif($lbitem.Status -imatch "Started")
    {
        $lbi.Background = "LightGreen"
    }
    elseif($lbitem.Status -imatch "Completed")
    {
        $lbi.Background = "Gray"
    }

    #write-host $lbitem.Properties.Content["statusMessage"]

    $lbi.Content = "$((get-localTime -utcTime $lbitem.EventTimeStamp).ToString("o"))   EVENT: $($lbitem.ResourceGroupName)   $($lbitem.Status)   $($lbitem.SubStatus)   $($lbitem.CorrelationId)   $($lbitem.EventDataId)   $($lbitem.OperationName)"
    
    
    if($lbItem.EventDataId -eq $null -or !$global:index.ContainsKey($lbitem.EventTimeStamp.ToString("o")))
    {
        if($detail)
        {
            if($failed)
            {
                write-host $lbi.Content -BackgroundColor "Red"
            }
            else
            {
                write-host $lbi.Content -BackgroundColor "Green"
            }
        }

        if($lbitem.EventTimeStamp -gt $global:eventStartTime)
        {
            $global:eventStartTime = $lbitem.EventTimeStamp
        }

        $lbi.Tag = $lbitem
        #$ret = $global:listbox.Items.Add($lbi)
        $ret = $global:listbox.Items.Insert(0,$lbi)

        $global:index.Add($lbitem.EventTimeStamp.ToString("o"),$($lbitem.CorrelationId))
    }
    else
    {
        write-host "$(($item | out-string)) exists"
    }
}

#-------------------------------------------------------------------------------------------------------------------------------
function add-depitem($lbitem, $color)
{

    [Windows.Controls.ListBoxItem]$lbi = new-object Windows.Controls.ListBoxItem
    $lbi.Background = $color
    $failed = $false

    if($lbitem.ProvisioningState -imatch "Failed")
    {
        $lbi.Background = "Red"
        $failed = $true
    }
    elseif($lbitem.ProvisioningState -imatch "Succeeded")
    {
        $lbi.Background = "LightBlue"
    }
    elseif($lbitem.ProvisioningState -imatch "Started")
    {
        $lbi.Background = "LightGreen"
    }
    elseif($lbitem.ProvisioningState -imatch "Completed")
    {
        $lbi.Background = "Gray"
    }

    #write-host $lbitem.Properties.Content["statusMessage"]

    $lbi.Content = "$((get-localTime -utcTime $lbitem.TimeStamp).ToString("o"))   DEPLOYMENT: $($lbitem.ResourceGroupName)   $($lbItem.DeploymentName)   $($lbitem.ProvisioningState)   $($lbitem.Mode)   $($lbitem.CorrelationId) $($lbitem.Output)"
    
    
    if(!$global:index.ContainsKey($lbitem.TimeStamp.ToString("o")))
    {
        if($detail)
        {
            if($failed)
            {
                write-host $lbi.Content -BackgroundColor "Red"
            }
            else
            {
                write-host $lbi.Content -BackgroundColor "Green"
            }
        }

        $lbi.Tag = $lbitem
        $ret = $global:listbox.Items.Insert(0,$lbi)

        $global:index.Add($lbitem.TimeStamp.ToString("o"),$($lbitem.CorrelationId))
    }
    else
    {
        write-host "$(($item | out-string)) exists"
    }
}

#-------------------------------------------------------------------------------------------------------------------------------
function open-event()
{
    write-host $global:listbox.SelectedItem
    [xml]$xaml = @"
    <Window 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="Window" Title="event info" WindowStartupLocation = "CenterScreen" ResizeMode="CanResize"
        ShowInTaskbar = "True" Background = "lightgray"> 
        <Grid Name="grid">
            <ListBox x:Name="listbox" Grid.Row="0" 
             ScrollViewer.CanContentScroll="True"
             ScrollViewer.VerticalScrollBarVisibility="Auto">
           </ListBox>
        </Grid>
    </Window>
"@

    #$eventcommand = "$($global:command) -CorrelationID $($global:listbox.SelectedItem.Tag.CorrelationId) | ? EventDataId -eq $($global:listbox.SelectedItem.Tag.EventDataId)"
    #write-host $eventcommand
    #$items = Invoke-Expression $eventcommand
    
    #if([string]::IsNullOrEmpty($items) -or $items.Count -lt 1)
    #{
    #    write-host "no event information"
    #    return
    #}
    try
    {
        $eventWindow=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    
        #Connect to Controls
        $eventListbox = $eventWindow.FindName('listbox')
        $item = $global:listbox.SelectedItem.Tag
        [Windows.Controls.ListBoxItem]$lbi = new-object Windows.Controls.ListBoxItem

        if(is-deployment -items $item)
        {
            $lbi.Content = ($item | fl * | out-string) 
        }
        else
        {
            $content = new-object Text.StringBuilder
            $content.AppendLine("ID:$($item.Id)")
            $content.AppendLine("LEVEL:$($item.Level)")
            $content.AppendLine("OPERATION ID:$($item.OperationId)")
            $content.AppendLine("OPERATION NAME:$($item.OperationName)")
    
            $content.AppendLine("PROPERTIES:")
            if($item.Properties.Content.IsInitialized)
            {
                $content.AppendLine("`tSTATUS CODE: $($item.Properties.Content["statusCode"])")
                $statusMessage = $item.Properties.Content["statusMessage"] | ConvertFrom-Json

                if($statusMessage.getType().Name -eq "String")
                {
                    $content.AppendLine("`tSTATUS MESSAGE:$($statusMessage)")   
                }
                else
                {
                    $content.AppendLine("`tSTATUS MESSAGE STATUS: $($statusMessage.status)")
                    $content.AppendLine("`tSTATUS MESSAGE ERROR CODE: $($statusMessage.error.code)")
                    $content.AppendLine("`tSTATUS MESSAGE ERROR MESSAGE: $($statusMessage.error.message)")
                    $content.AppendLine("`tSTATUS MESSAGE ERROR DETAILS CODE: $($statusMessage.error.details.code)")
                    $content.AppendLine("`tSTATUS MESSAGE ERROR DETAILS MESSAGE: $($statusMessage.error.details.message)")
                    #$content.AppendLine("`tSTATUS MESSAGE: $($statusMessage.error.status) $($statusMessage.error.code) $($statusMessage.error.message) $($statusMessage.error.details)")
                }
            }

            $content.AppendLine("RESOURCE GROUP NAME:$($item.ResourceGroupName)")
            $content.AppendLine("RESOURCE PROVIDER NAME:$($item.ResourceProviderName)")
            $content.AppendLine("RESOURCE ID:$($item.ResourceId)")
            $content.AppendLine("STATUS:$($item.Status)")
            $content.AppendLine("SUBSTATUS:$($item.SubStatus)")
            $content.AppendLine("SUBMISSION TIME STAMP:$($item.SubmissionTimestamp)")
            $content.AppendLine("SUBSCRIPTION ID:$($item.SubscriptionId)")

            $lbi.Content = $content.ToString()
        }

        if(($item | format-list | out-string) -imatch "(level.+\:.+Error)|provisioningstate.+\:.+failed")
        {
            $lbi.Background = "AliceBlue"
            $lbi.Foreground = "Red"

            if($detail)
            {
                write-host ($item | fl * | out-string) -BackgroundColor "Red"
            }

        }
        else
        {
            $lbi.Background = "AliceBlue"
            $lbi.Foreground = "Green"
            if($detail)
            {
                write-host ($item | fl * | out-string) -BackgroundColor "Green"
            }
        }

        $ret = $eventListbox.Items.Add($lbi)
        $eventWindow.ShowDialog()
    }
    catch
    {
        write-host "open-event:exception $($error)"
        $error.Clear()
    }
}

#-------------------------------------------------------------------------------------------------------------------------------
main

