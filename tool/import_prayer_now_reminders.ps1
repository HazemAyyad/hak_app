param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$Ffmpeg
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$assetRoot = Join-Path $taskRoot 'assets/prayer/reminders'
$iosRoot = Join-Path $taskRoot 'ios/Runner/PrayerReminders'
$clips = [ordered]@{}
foreach ($edition in @('current', 'old')) {
    $suffix = if ($edition -eq 'old') { '_old' } else { '' }
    foreach ($entry in @(
        @('fajr', 'fagrsoon'), @('dhuhr', 'zohrsoon'), @('asr', 'asrsoon'),
        @('maghrib', 'maghribsoon'), @('isha', 'eshaasoon'), @('friday', 'gom3asoon')
    )) {
        $clips["pn-$edition/$($entry[0]).mp3"] = "$edition/$($entry[1])$suffix.mp3"
    }
}
foreach ($entry in @(
    @('intro.mp3', 'noti_intro_azan.mp3'), @('yarab.mp3', 'noti_yarab.mp3'),
    @('road.mp3', 'noti_yarab_road.mp3'), @('salaty.mp3', 'salaty.mp3'),
    @('light.wav', 'noti_light.wav'), @('knock.wav', 'noti_nocknock.wav'),
    @('wake.mp3', 'alsalah_khair_mn_alnowm.mp3')
)) {
    $clips["pn-general/$($entry[0])"] = "general-before-prayer/$($entry[1])"
}
$manifest = [ordered]@{
    source = 'PRAYER NOW'; package = 'com.AppRocks.now.prayer'; version = '9.3.5'
    apk_sha256 = '2a4af087cbd8e83511b914231797fc15508c0d9ca60321eba56adc8d7ef4d4ed'
    extracted_with = 'REA'; mapping_method = 'com.AppRocks.now.prayer.generalUTILS.UTils.T(int)'
    note = 'Original MP3/WAV bytes preserved. iOS notification copies are PCM, mono, 24 kHz, capped at 25 seconds; only wake.mp3 exceeds that limit.'
    ios_max_seconds = 25
    clips = @()
}
$buildRows = @(); $fileRows = @(); $groupRows = @(); $resourceRows = @()
$index = 0
foreach ($entry in $clips.GetEnumerator()) {
    $source = Join-Path $SourceRoot $entry.Value
    $target = Join-Path $assetRoot $entry.Key
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
    $soundName = 'haq-reminder-' + ([IO.Path]::ChangeExtension($entry.Key, $null).TrimEnd('.').Replace('/', '-')) + '.caf'
    $caf = Join-Path $iosRoot $soundName
    & $Ffmpeg -hide_banner -loglevel error -y -i $target -t 25 -ar 24000 -ac 1 -c:a pcm_s16le $caf
    if ($LASTEXITCODE -ne 0) { throw "CAF conversion failed: $($entry.Key)" }
    # Decode the full original file to detect malformed/truncated audio.
    & $Ffmpeg -hide_banner -loglevel error -xerror -i $target -f null -
    if ($LASTEXITCODE -ne 0) { throw "Audio validation failed: $($entry.Key)" }
    $manifest.clips += [ordered]@{
        original_resource = 'res/raw/' + [IO.Path]::GetFileName($entry.Value)
        asset = 'assets/prayer/reminders/' + $entry.Key
        sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLower()
        bytes = (Get-Item -LiteralPath $target).Length
        ios_sound = $soundName
        ios_sha256 = (Get-FileHash -LiteralPath $caf -Algorithm SHA256).Hash.ToLower()
    }
    $buildId = 'A32B' + $index.ToString('X20')
    $fileId = 'A32D' + $index.ToString('X20')
    $buildRows += "`t`t$buildId /* $soundName in Resources */ = {isa = PBXBuildFile; fileRef = $fileId /* $soundName */; };"
    $fileRows += "`t`t$fileId /* $soundName */ = {isa = PBXFileReference; lastKnownFileType = audio.caf; name = `"$soundName`"; path = `"PrayerReminders/$soundName`"; sourceTree = `"<group>`"; };"
    $groupRows += "`t`t`t`t$fileId /* $soundName */,"
    $resourceRows += "`t`t`t`t$buildId /* $soundName in Resources */,"
    $index++
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $assetRoot 'prayer-now-provenance.json'), ($manifest | ConvertTo-Json -Depth 8) + "`n", $utf8)
$projectPath = Join-Path $taskRoot 'ios/Runner.xcodeproj/project.pbxproj'
$project = [IO.File]::ReadAllText($projectPath).Replace("`r`n", "`n")
# Replace only this importer's deterministic resource entries on a repeat run.
$project = [regex]::Replace($project, '(?m)^\t+A32[BD][0-9A-F]{20} /\*[^\r\n]*\r?\n', '')
$project = $project.Replace('/* End PBXBuildFile section */', ($buildRows -join "`n") + "`n/* End PBXBuildFile section */")
$project = $project.Replace('/* End PBXFileReference section */', ($fileRows -join "`n") + "`n/* End PBXFileReference section */")
$runnerGroup = "97C146F01CF9000F007C117D /* Runner */ = {`n`t`t`tisa = PBXGroup;`n`t`t`tchildren = (`n"
$runnerResources = "97C146EC1CF9000F007C117D /* Resources */ = {`n`t`t`tisa = PBXResourcesBuildPhase;`n`t`t`tbuildActionMask = 2147483647;`n`t`t`tfiles = (`n"
if (!$project.Contains($runnerGroup) -or !$project.Contains($runnerResources)) { throw 'Runner Xcode sections not found' }
$project = $project.Replace($runnerGroup, $runnerGroup + ($groupRows -join "`n") + "`n")
$project = $project.Replace($runnerResources, $runnerResources + ($resourceRows -join "`n") + "`n")
[IO.File]::WriteAllText($projectPath, $project, $utf8)
Write-Output "Imported and decoded $index audio files; registered $index iOS CAF resources."
