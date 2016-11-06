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
   Version    : 161106 original
   History    : 

.EXAMPLE  
    .\azur-rm-log-reader.ps1
    query azure rm for all resource manager logs
 
.PARAMETER detail
    optional parameter to log information to console

#>  

param (
    [switch]$detail=$true
)

Add-Type -AssemblyName PresentationFramework            
Add-Type -AssemblyName PresentationCore  

$global:command = "get-azurermlog -DetailedOutput"
$global:listbox = $null
$global:index = @{}
$global:creds
$global:window = $null
$timer = new-object Windows.Threading.DispatcherTimer
$error.Clear()
$refreshTime = "0:1:00.0"
$global:completed = 0
$global:eventStartTime = [DateTime]::MinValue

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
                <RowDefinition Height="20" />
                <RowDefinition Height="20" />
                <RowDefinition Height="*" />
            </Grid.RowDefinitions>
            <TextBox x:Name="inputTextBox" Grid.Row="0" />
            <Button x:Name="refreshButton" Content="Refresh" Grid.Row="1"/>
       
            <ListBox x:Name="listbox" Grid.Row="2" Height="Auto">
           </ListBox>
           </Grid>
      </DockPanel>
    </Window>
"@
    $global:Window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    
    #Connect to Controls
    $global:inputTextBox = $global:Window.FindName('inputTextBox')
    $refreshButton = $global:Window.FindName('refreshButton')
    $global:listbox = $global:Window.FindName('listbox')
    #$removeButton = $global:Window.FindName('removeButton')
    $listbox.Add_SelectionChanged({open-event})
    $listbox.Items.SortDescriptions.Add((new-object ComponentModel.SortDescription(“Content”, [ComponentModel.ListSortDirection]::Descending)));
    
    $global:Window.Add_Loaded({

        $timer.Add_Tick({
            write-host "." -NoNewline
            run-command -command $global:inputTextBox.Text
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
    $global:inputTextBox.Text = $global:command
    $refreshButton.Add_Click({run-command -command $global:inputTextBox.Text})
    run-command -command $global:inputTextBox.Text

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
function run-command($command)
{
    try
    {
        if($global:eventStartTime -eq [DateTime]::MinValue)
        {
            $items = Invoke-Expression $command
        }
        else
        {
            $items = Invoke-Expression "$($command) -StartTime $($global:eventStartTime)"
        }
        
        foreach($item in ($items | Sort-Object EventTimestamp))
        {
            add-item -lbitem $item -color "Yellow"
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

    $lbi.Content = "$($lbitem.EventTimeStamp)   $($lbitem.ResourceGroupName)   $($lbitem.Status)   $($lbitem.SubStatus)   $($lbitem.CorrelationId)   $($lbitem.EventDataId)   $($lbitem.OperationName)"
    
    
    if(!$global:index.ContainsKey($lbitem.EventDataId))
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

        $lbi.Tag = $lbitem.EventDataId
        #$ret = $global:listbox.Items.Add($lbi)
        $ret = $global:listbox.Items.Insert(0,$lbi)
        $global:index.Add($lbitem.EventDataId,$($lbitem.CorrelationId))
    }
    else
    {
        # write-host "$(($item | out-string)) exists"
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

    $eventWindow=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    
    #Connect to Controls
    $eventListbox = $eventWindow.FindName('listbox')
    
    $items = Invoke-Expression "$($global:command) -CorrelationID $($global:index[$global:listbox.SelectedItem.Tag])"
    
    foreach($item in $items)
    {
        [Windows.Controls.ListBoxItem]$lbi = new-object Windows.Controls.ListBoxItem

        $lbi.Content = "$(($item | format-list | Out-String))"

        if(($item | format-list | out-string) -imatch "level.+\:.+Error")
        {
            $lbi.Background = "AliceBlue"
            $lbi.Foreground = "Red"

            if($detail)
            {
                write-host $lbi.Content -BackgroundColor "Red"
            }

        }
        else
        {
            $lbi.Background = "AliceBlue"
            $lbi.Foreground = "Green"
            if($detail)
            {
                write-host $lbi.Content -BackgroundColor "Green"
            }
        }

        $ret = $eventListbox.Items.Add($lbi)
    }

    $eventWindow.ShowDialog()
}

#-------------------------------------------------------------------------------------------------------------------------------
main

