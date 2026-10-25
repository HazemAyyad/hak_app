param(
    [string]$Java = 'C:/Program Files/Android/Android Studio/jbr/bin/java.exe',
    [string]$AndroidJar = 'C:/Users/Hazem/AppData/Local/Android/Sdk/platforms/android-36/android.jar',
    [string]$FlutterJar = 'C:/src/flutter/bin/cache/artifacts/engine/android-x64/flutter.jar',
    [string]$GradleCache = 'C:/Users/Hazem/.gradle/caches/modules-2/files-2.1'
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
Push-Location $taskRoot
try {
    function Find-TaskJar([string]$relative) {
        $taskJar = rg --files (Join-Path $GradleCache $relative) -g '*.jar' | Select-Object -First 1
        if (!$taskJar) { throw "Required cached jar missing: $relative. This check does not install dependencies." }
        return $taskJar
    }
    $taskCompiler = @(
        Find-TaskJar 'org.jetbrains.kotlin/kotlin-compiler-embeddable/2.2.20'
        Find-TaskJar 'org.jetbrains.kotlin/kotlin-stdlib/2.2.20'
        Find-TaskJar 'org.jetbrains.kotlin/kotlin-script-runtime/2.2.20'
        Find-TaskJar 'org.jetbrains.kotlin/kotlin-reflect/1.6.10'
        Find-TaskJar 'org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm/1.8.0'
        Find-TaskJar 'org.jetbrains/annotations/13.0'
    ) -join ';'
    $taskTarget = @(
        Find-TaskJar 'org.json/json/20180813'
        $AndroidJar
        $FlutterJar
        Join-Path $taskRoot 'build/audio_service/intermediates/compile_library_classes_jar/debug/bundleLibCompileToJarDebug/classes.jar'
        Find-TaskJar 'org.jetbrains.kotlin/kotlin-stdlib/2.2.20'
        Find-TaskJar 'androidx.lifecycle/lifecycle-common-jvm/2.8.7'
        Find-TaskJar 'androidx.annotation/annotation-jvm/1.9.1'
    ) -join ';'
    New-Item -ItemType Directory -Force -Path build/p08-native-check | Out-Null
    # Only the generated Android resource ID is represented by a small stand-in.
    # Both actual Kotlin source files compile against the cached Android/Flutter
    # APIs. This does not validate packaged resources, Gradle, or phone behavior.
    [IO.File]::WriteAllText((Join-Path $taskRoot 'build/p08-native-check/ResourceIds.kt'),
        'package com.haqfoundation.haq_app; object R { object drawable { const val ic_haq_reminder = 1 } }')
    & $Java -cp $taskCompiler org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 `
        -classpath $taskTarget -d build/p08-native-check/classes `
        build/p08-native-check/ResourceIds.kt `
        android/app/src/main/kotlin/com/haqfoundation/haq_app/MainActivity.kt `
        android/app/src/main/kotlin/com/haqfoundation/haq_app/HaqReminders.kt `
        test/native/HaqReminderScheduleChecks.kt
    if ($LASTEXITCODE -ne 0) { throw 'Native source check failed.' }
    $taskRuntime = (Join-Path $taskRoot 'build/p08-native-check/classes') + ';' + $taskTarget
    & $Java -cp $taskRuntime com.haqfoundation.haq_app.HaqReminderScheduleChecksKt
    if ($LASTEXITCODE -ne 0) { throw 'Native scheduling checks failed.' }
} finally { Pop-Location }
