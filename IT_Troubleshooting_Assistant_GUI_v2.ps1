
<# 
 IT Troubleshooting Assistant – GUI v2
 * Adds robust logging to files
 * Includes "Run All" button
 * Fixes potential UI freeze by executing diagnostics in background jobs
 * Uses /scan flag for CHKDSK to avoid interactive prompt
 * Adds summary report generation
#>

Add-Type -AssemblyName PresentationCore,PresentationFramework

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="IT Troubleshooting Assistant" Height="550" Width="780" ResizeMode="NoResize">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,0,0,10">
            <Button Name="btnNetwork" Content="Network" Width="110" Margin="5"/>
            <Button Name="btnSoftware" Content="Software" Width="110" Margin="5"/>
            <Button Name="btnHardware" Content="Hardware" Width="110" Margin="5"/>
            <Button Name="btnSecurity" Content="Security" Width="110" Margin="5"/>
            <Button Name="btnRunAll" Content="Run All" Width="110" Margin="5" Background="#FFB347"/>
        </StackPanel>

        <TextBox Name="txtLog" Grid.Row="1" Margin="0,0,0,10" AcceptsReturn="True"
                 VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" IsReadOnly="True"/>

        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="btnSave" Content="Save Summary" Width="120" Margin="0,0,10,0"/>
            <Button Name="btnExit" Content="Exit" Width="100"/>
        </StackPanel>
    </Grid>
</Window>
"@

# Load XAML
$reader  = New-Object System.Xml.XmlNodeReader $xaml
$window  = [Windows.Markup.XamlReader]::Load($reader)

# Get controls
$btnNetwork = $window.FindName("btnNetwork")
$btnSoftware= $window.FindName("btnSoftware")
$btnHardware= $window.FindName("btnHardware")
$btnSecurity= $window.FindName("btnSecurity")
$btnRunAll  = $window.FindName("btnRunAll")
$btnSave    = $window.FindName("btnSave")
$btnExit    = $window.FindName("btnExit")
$txtLog     = $window.FindName("txtLog")

# Prepare log directory
$LogDir = Join-Path $PSScriptRoot 'Troubleshooting_Logs'
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

Function Write-UI {
    param([string]$Message)
    $action = { param($msg) $txtLog.AppendText("$msg`n"); $txtLog.ScrollToEnd() }
    $txtLog.Dispatcher.Invoke($action, $Message)
}

Function Write-LogFile {
    param([string]$Category,[string]$Message)
    if (-not $Category) { return }
    $filePath = Join-Path $LogDir "$Category`_Log.txt"
    $Message | Out-File -FilePath $filePath -Append -Encoding utf8
}

Function Log {
    param([string]$Category,[string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp][$Category] $Message"
    Write-UI $line
    Write-LogFile $Category $line
}

# Helper to run command in background and stream output
Function Invoke-Async {
    param([string]$Category,[string]$Label,[string]$Command)
    Log $Category ">>> $Label : $Command"
    $job = Start-Job -ScriptBlock { param($cmd) Invoke-Expression $cmd 2>&1 } -ArgumentList $Command
    while ($job.State -eq 'Running') {
        Receive-Job $job -Keep | ForEach-Object { Log $Category $_ }
        Start-Sleep -Milliseconds 300
    }
    Receive-Job $job | ForEach-Object { Log $Category $_ }
    Remove-Job $job
}

# Diagnostic routines
Function Run-Network {
    Invoke-Async Network 'IP Configuration' 'ipconfig /all'
    Invoke-Async Network 'Ping External 8.8.8.8' 'ping -n 4 8.8.8.8'
    Invoke-Async Network 'Ping google.com' 'ping -n 4 google.com'
}

Function Run-Software {
    Invoke-Async Software 'SFC Scan' 'sfc /scannow'
    Invoke-Async Software 'DISM RestoreHealth' 'DISM /Online /Cleanup-Image /RestoreHealth'
}

Function Run-Hardware {
    Invoke-Async Hardware 'Device Manager Issues' 'Get-PnpDevice | Where-Object { $_.Status -ne "OK" }'
    Invoke-Async Hardware 'CHKDSK (scan)' 'chkdsk C: /scan'
}

Function Run-Security {
    Invoke-Async Security 'Firewall Status' 'Get-NetFirewallProfile'
    Invoke-Async Security 'Defender Status' 'Get-MpComputerStatus'
    Invoke-Async Security 'Open Ports Quick Scan' 'netstat -ano'
}

Function Disable-Buttons($state) {
    $btnNetwork.IsEnabled  = $state
    $btnSoftware.IsEnabled = $state
    $btnHardware.IsEnabled = $state
    $btnSecurity.IsEnabled = $state
    $btnRunAll.IsEnabled   = $state
}

Function Run-Group($group) {
    Disable-Buttons $false
    & $group
    Disable-Buttons $true
}

# Button Handlers
$btnNetwork.Add_Click({ Start-Job { Run-Group Run-Network } })
$btnSoftware.Add_Click({ Start-Job { Run-Group Run-Software } })
$btnHardware.Add_Click({ Start-Job { Run-Group Run-Hardware } })
$btnSecurity.Add_Click({ Start-Job { Run-Group Run-Security } })
$btnRunAll.Add_Click({
    Start-Job {
        Run-Group Run-Network
        Run-Group Run-Software
        Run-Group Run-Hardware
        Run-Group Run-Security
    }
})

# Save summary report
$btnSave.Add_Click({
    $summary = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $summary += "`n==== Summary Report ====`n"
    Get-ChildItem $LogDir -Filter '*_Log.txt' | ForEach-Object {
        $summary += "`n---- $($_.BaseName) ----`n"
        $summary += Get-Content $_.FullName
    }
    $summaryPath = Join-Path $LogDir 'Complete_Troubleshooting_Report.txt'
    $summary | Out-File -FilePath $summaryPath -Encoding utf8
    Write-UI "Summary saved to $summaryPath"
})

$btnExit.Add_Click({ $window.Close() })

# Start GUI
$null = $window.ShowDialog()
