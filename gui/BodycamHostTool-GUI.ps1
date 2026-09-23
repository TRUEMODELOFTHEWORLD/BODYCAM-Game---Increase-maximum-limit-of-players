param([switch]$ValidateOnly)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BodycamKeys {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
"@

[System.Windows.Forms.Application]::EnableVisualStyles()

$appRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $appRoot 'ue4ss\Mods\BodycamHostTest\config.json'
$logPath = Join-Path $appRoot 'ue4ss\Mods\BodycamHostTest\BodycamHostTest.log'
if (-not (Test-Path -LiteralPath $configPath)) {
    $developerConfig = Join-Path $appRoot 'mod\BodycamHostTest\config.json'
    if (Test-Path -LiteralPath $developerConfig) {
        $configPath = $developerConfig
        $logPath = Join-Path $appRoot 'mod\BodycamHostTest\BodycamHostTest.log'
    }
}
$script:config = $null
$script:experimentalRows = @{}
$script:expanded = $false

if ($ValidateOnly) {
    if (-not (Test-Path -LiteralPath $configPath)) { throw "Config not found: $configPath" }
    $validationConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if (-not $validationConfig.playerAndBotLimits) { throw 'Missing playerAndBotLimits section.' }
    if ($null -eq $validationConfig.playerAndBotLimits.maxPlayers) { throw 'Missing maxPlayers value.' }
    if ($validationConfig.playerAndBotLimits.PSObject.Properties.Name -notcontains 'maxBotsPerTeam') { throw 'Missing maxBotsPerTeam field.' }
    Write-Output "GUI validation passed: $configPath"
    exit 0
}

$colors = @{
    Background = [Drawing.Color]::FromArgb(17, 20, 27)
    Surface = [Drawing.Color]::FromArgb(27, 32, 42)
    Surface2 = [Drawing.Color]::FromArgb(35, 42, 54)
    Text = [Drawing.Color]::FromArgb(238, 242, 248)
    Muted = [Drawing.Color]::FromArgb(154, 164, 181)
    Accent = [Drawing.Color]::FromArgb(61, 214, 168)
    AccentDark = [Drawing.Color]::FromArgb(33, 145, 113)
    Warning = [Drawing.Color]::FromArgb(245, 184, 75)
    Error = [Drawing.Color]::FromArgb(242, 102, 115)
}

function New-Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [float]$size = 9, [bool]$bold = $false) {
    $c = New-Object Windows.Forms.Label
    $c.Text = $text; $c.Location = New-Object Drawing.Point($x, $y); $c.Size = New-Object Drawing.Size($w, $h)
    $c.ForeColor = $colors.Text; $c.BackColor = [Drawing.Color]::Transparent
    $style = if ($bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $c.Font = New-Object Drawing.Font('Segoe UI', $size, $style)
    return $c
}

function New-Button([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [bool]$accent = $false) {
    $c = New-Object Windows.Forms.Button
    $c.Text = $text; $c.Location = New-Object Drawing.Point($x, $y); $c.Size = New-Object Drawing.Size($w, $h)
    $c.FlatStyle = 'Flat'; $c.FlatAppearance.BorderSize = 0; $c.Cursor = 'Hand'
    $c.Font = New-Object Drawing.Font('Segoe UI Semibold', 9)
    $c.ForeColor = if ($accent) { $colors.Background } else { $colors.Text }
    $c.BackColor = if ($accent) { $colors.Accent } else { $colors.Surface2 }
    return $c
}

function New-Number([decimal]$min, [decimal]$max, [int]$x, [int]$y, [int]$w = 110, [int]$decimals = 0) {
    $c = New-Object Windows.Forms.NumericUpDown
    $c.Location = New-Object Drawing.Point($x, $y); $c.Size = New-Object Drawing.Size($w, 28)
    $c.Minimum = $min; $c.Maximum = $max; $c.DecimalPlaces = $decimals
    $c.Increment = if ($decimals -gt 0) { [decimal]0.5 } else { [decimal]1 }
    $c.Font = New-Object Drawing.Font('Segoe UI', 10); $c.BackColor = $colors.Surface2; $c.ForeColor = $colors.Text
    $c.BorderStyle = 'FixedSingle'
    return $c
}

function Set-Status([string]$text, [string]$kind = 'normal') {
    $statusLabel.Text = $text
    $statusLabel.ForeColor = switch ($kind) { 'error' {$colors.Error} 'warning' {$colors.Warning} default {$colors.Muted} }
}

function Ensure-ConfigShape {
    if (-not $script:config.playerAndBotLimits) {
        $limits = [ordered]@{ maxPlayers = 24; maxBotsPerTeam = 12 }
        $script:config | Add-Member -NotePropertyName playerAndBotLimits -NotePropertyValue ([pscustomobject]$limits) -Force
    }
    if (-not $script:config.experimentalServerSettings) {
        $script:config | Add-Member -NotePropertyName experimentalServerSettings -NotePropertyValue ([pscustomobject]@{}) -Force
    }
}

function Load-Config {
    try {
        if (-not (Test-Path -LiteralPath $configPath)) { throw "Config not found: $configPath" }
        $script:config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        Ensure-ConfigShape
        $maxPlayers.Value = [decimal]$script:config.playerAndBotLimits.maxPlayers
        $maxBots.Maximum = [decimal][Math]::Min(32, [int]$maxPlayers.Value)
        $botValue = $script:config.playerAndBotLimits.maxBotsPerTeam
        $botEnabled.Checked = $null -ne $botValue
        $maxBots.Enabled = $botEnabled.Checked
        if ($null -ne $botValue) { $maxBots.Value = [decimal]$botValue }
        foreach ($name in $script:experimentalRows.Keys) {
            $row = $script:experimentalRows[$name]
            $value = $script:config.experimentalServerSettings.$name
            $row.Enabled.Checked = $null -ne $value
            $row.Input.Enabled = $row.Enabled.Checked
            if ($null -ne $value) {
                if ($row.Kind -eq 'bool') { $row.Input.Checked = [bool]$value }
                else { $row.Input.Value = [decimal]$value }
            }
        }
        Set-Status "Loaded $(Split-Path -Leaf $configPath)" 'normal'
    } catch {
        Set-Status $_.Exception.Message 'error'
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to load config', 'OK', 'Error') | Out-Null
    }
}

function Save-Config {
    try {
        Ensure-ConfigShape
        $script:config.playerAndBotLimits.maxPlayers = [int]$maxPlayers.Value
        $script:config.playerAndBotLimits.maxBotsPerTeam = if ($botEnabled.Checked) { [int]$maxBots.Value } else { $null }
        foreach ($name in $script:experimentalRows.Keys) {
            $row = $script:experimentalRows[$name]
            $value = $null
            if ($row.Enabled.Checked) {
                $value = if ($row.Kind -eq 'bool') { [bool]$row.Input.Checked }
                    elseif ($row.Kind -eq 'int') { [int]$row.Input.Value }
                    else { [double]$row.Input.Value }
            }
            if ($script:config.experimentalServerSettings.PSObject.Properties.Name -contains $name) {
                $script:config.experimentalServerSettings.$name = $value
            } else {
                $script:config.experimentalServerSettings | Add-Member -NotePropertyName $name -NotePropertyValue $value
            }
        }
        $json = $script:config | ConvertTo-Json -Depth 5
        [IO.File]::WriteAllText($configPath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        Set-Status 'Saved. Use an Apply button to send the matching hotkey.' 'normal'
        return $true
    } catch {
        Set-Status "Save failed: $($_.Exception.Message)" 'error'
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to save config', 'OK', 'Error') | Out-Null
        return $false
    }
}

function Send-BodycamKey([int]$vk, [string]$label) {
    $process = Get-Process -Name 'Bodycam-Win64-Shipping' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $process -or $process.MainWindowHandle -eq 0) {
        Set-Status 'BODYCAM window not found. Start the game and enter a hosted match.' 'error'
        return
    }
    [BodycamKeys]::ShowWindow($process.MainWindowHandle, 9) | Out-Null
    [BodycamKeys]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 180
    [BodycamKeys]::keybd_event([byte]$vk, 0, 0, [UIntPtr]::Zero)
    [BodycamKeys]::keybd_event([byte]$vk, 0, 2, [UIntPtr]::Zero)
    Set-Status "$label sent to BODYCAM. Check BodycamHostTest.log for the result." 'normal'
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Bodycam Host Tool'; $form.Size = New-Object Drawing.Size(780, 610)
$form.MinimumSize = New-Object Drawing.Size(780, 610); $form.MaximumSize = New-Object Drawing.Size(780, 930)
$form.StartPosition = 'CenterScreen'; $form.BackColor = $colors.Background; $form.ForeColor = $colors.Text
$form.Font = New-Object Drawing.Font('Segoe UI', 9); $form.AutoScaleMode = 'Dpi'

$title = New-Label 'BODYCAM HOST TOOL' 28 20 500 35 18 $true
$subtitle = New-Label 'Configure the existing UE4SS mod, then apply its hotkeys.' 30 55 600 24 9 $false
$subtitle.ForeColor = $colors.Muted
$form.Controls.AddRange(@($title, $subtitle))

$mainPanel = New-Object Windows.Forms.Panel
$mainPanel.Location = New-Object Drawing.Point(28, 92); $mainPanel.Size = New-Object Drawing.Size(706, 195); $mainPanel.BackColor = $colors.Surface
$form.Controls.Add($mainPanel)
$mainPanel.Controls.Add((New-Label 'PRIMARY LIMITS' 20 14 260 25 10 $true))
$mainPanel.Controls.Add((New-Label 'Player capacity' 20 52 220 24 10 $true))
$mainPanel.Controls.Add((New-Label 'Applied with F9. Accepted test range: 2-64.' 20 78 330 22 8 $false))
$mainPanel.Controls[$mainPanel.Controls.Count - 1].ForeColor = $colors.Muted
$maxPlayers = New-Number 2 64 245 55 90 0; $mainPanel.Controls.Add($maxPlayers)
$applyPlayers = New-Button 'Save + Apply F9' 505 51 175 38 $true; $mainPanel.Controls.Add($applyPlayers)

$mainPanel.Controls.Add((New-Label 'Bots per team' 20 116 220 24 10 $true))
$mainPanel.Controls.Add((New-Label 'TDM: per side. FFA: total. Applied with F10.' 20 142 350 22 8 $false))
$mainPanel.Controls[$mainPanel.Controls.Count - 1].ForeColor = $colors.Muted
$botEnabled = New-Object Windows.Forms.CheckBox
$botEnabled.Text = 'Enabled'; $botEnabled.Location = New-Object Drawing.Point(245, 119); $botEnabled.Size = New-Object Drawing.Size(78, 25)
$botEnabled.ForeColor = $colors.Text; $botEnabled.BackColor = [Drawing.Color]::Transparent
$maxBots = New-Number 0 32 332 117 76 0
$applyBots = New-Button 'Save + Apply F10' 505 115 175 38 $false
$mainPanel.Controls.AddRange(@($botEnabled, $maxBots, $applyBots))

$toolbar = New-Object Windows.Forms.Panel
$toolbar.Location = New-Object Drawing.Point(28, 302); $toolbar.Size = New-Object Drawing.Size(706, 56); $toolbar.BackColor = $colors.Surface
$form.Controls.Add($toolbar)
$saveButton = New-Button 'Save config' 12 10 120 36 $true
$reloadButton = New-Button 'Reload' 142 10 92 36 $false
$openConfigButton = New-Button 'Open config' 244 10 108 36 $false
$openLogButton = New-Button 'Open log' 362 10 94 36 $false
$launchButton = New-Button 'Launch BODYCAM' 466 10 140 36 $false
$probeButton = New-Button 'F12 Probe' 616 10 78 36 $false
$toolbar.Controls.AddRange(@($saveButton,$reloadButton,$openConfigButton,$openLogButton,$launchButton,$probeButton))

$advancedButton = New-Button '>  Show experimental settings' 28 373 260 38 $false
$advancedButton.TextAlign = 'MiddleLeft'; $form.Controls.Add($advancedButton)
$advancedHint = New-Label 'Hidden by default | F11 applies enabled fields together' 308 382 420 22 8 $false
$advancedHint.ForeColor = $colors.Muted; $form.Controls.Add($advancedHint)

$advancedPanel = New-Object Windows.Forms.Panel
$advancedPanel.Location = New-Object Drawing.Point(28, 422); $advancedPanel.Size = New-Object Drawing.Size(706, 0)
$advancedPanel.BackColor = $colors.Surface; $advancedPanel.AutoScroll = $true; $advancedPanel.Visible = $false
$form.Controls.Add($advancedPanel)

$specs = @(
    @('PhaseDuration','Match duration',60,3600,'float'),
    @('bUseTimerForWaitingPlayers','Use waiting timer',0,1,'bool'),
    @('WaitingForPlayersDuration','Waiting duration',0,300,'float'),
    @('RoundWarmupDuration','Round warmup',0,120,'float'),
    @('EndRoundDuration','End-round delay',0,120,'float'),
    @('RespawnDelay','Respawn delay',0,60,'float'),
    @('RemainingTimeToStartTimerSounds','Countdown sound threshold',0,30,'float'),
    @('ScoreLimit','Score limit',1,500,'int'),
    @('MaxPhases','Maximum phases',1,20,'int'),
    @('TeamSwitchInterval','Team switch interval',0,120,'int'),
    @('GraceWindowDistance','Loadout grace distance',0,5000,'float'),
    @('GraceWindowDuration','Loadout grace duration',0,120,'float'),
    @('VoteMapTimerMax','Map vote timer',5,300,'int')
)

$y = 12
foreach ($spec in $specs) {
    $name,$label,$min,$max,$kind = $spec
    $enabled = New-Object Windows.Forms.CheckBox
    $enabled.Location = New-Object Drawing.Point(15, $y + 2); $enabled.Size = New-Object Drawing.Size(22, 24)
    $enabled.BackColor = [Drawing.Color]::Transparent
    $caption = New-Label $label 42 $y 280 25 9 $false
    if ($kind -eq 'bool') {
        $input = New-Object Windows.Forms.CheckBox
        $input.Text = 'On'; $input.Location = New-Object Drawing.Point(340, $y); $input.Size = New-Object Drawing.Size(75, 25)
        $input.ForeColor = $colors.Text; $input.BackColor = [Drawing.Color]::Transparent
    } else {
        $decimals = if ($kind -eq 'int') { 0 } else { 1 }
        $input = New-Number ([decimal]$min) ([decimal]$max) 340 $y 120 $decimals
    }
    $input.Enabled = $false
    $enabled.Add_CheckedChanged({ $this.Tag.Enabled = $this.Checked })
    $enabled.Tag = $input
    $advancedPanel.Controls.AddRange(@($enabled,$caption,$input))
    $script:experimentalRows[$name] = @{ Enabled=$enabled; Input=$input; Kind=$kind }
    $y += 34
}
$applyExperimental = New-Button 'Save + Apply experimental settings (F11)' 340 $y 338 38 $false
$advancedPanel.Controls.Add($applyExperimental)

$statusPanel = New-Object Windows.Forms.Panel
$statusPanel.Location = New-Object Drawing.Point(28, 522); $statusPanel.Size = New-Object Drawing.Size(706, 48); $statusPanel.BackColor = $colors.Surface
$form.Controls.Add($statusPanel)
$statusLabel = New-Label 'Loading configuration...' 14 14 675 22 8 $false
$statusLabel.ForeColor = $colors.Muted; $statusPanel.Controls.Add($statusLabel)

$botEnabled.Add_CheckedChanged({ $maxBots.Enabled = $botEnabled.Checked })
$maxPlayers.Add_ValueChanged({
    $newMaximum = [decimal][Math]::Min(32, [int]$maxPlayers.Value)
    $maxBots.Maximum = $newMaximum
    if ($maxBots.Value -gt $newMaximum) { $maxBots.Value = $newMaximum }
})
$saveButton.Add_Click({ [void](Save-Config) })
$reloadButton.Add_Click({ Load-Config })
$applyPlayers.Add_Click({ if (Save-Config) { Send-BodycamKey 0x78 'F9 player-limit command' } })
$applyBots.Add_Click({ if (Save-Config) { Send-BodycamKey 0x79 'F10 bot-limit command' } })
$applyExperimental.Add_Click({ if (Save-Config) { Send-BodycamKey 0x7A 'F11 server-settings command' } })
$probeButton.Add_Click({ Send-BodycamKey 0x7B 'F12 read-only bot probe' })
$openConfigButton.Add_Click({ if (Test-Path $configPath) { Start-Process notepad.exe -ArgumentList "`"$configPath`"" } })
$openLogButton.Add_Click({ if (Test-Path $logPath) { Start-Process notepad.exe -ArgumentList "`"$logPath`"" } else { Set-Status 'Log does not exist yet.' 'warning' } })
$launchButton.Add_Click({ Start-Process 'steam://rungameid/2406770'; Set-Status 'BODYCAM launch requested through Steam.' })
$advancedButton.Add_Click({
    $script:expanded = -not $script:expanded
    $advancedPanel.Visible = $script:expanded
    $advancedPanel.Height = if ($script:expanded) { 420 } else { 0 }
    $advancedButton.Text = if ($script:expanded) { 'v  Hide experimental settings' } else { '>  Show experimental settings' }
    $form.Height = if ($script:expanded) { 930 } else { 610 }
    $statusPanel.Top = if ($script:expanded) { 850 } else { 522 }
})

Load-Config
[void]$form.ShowDialog()
