# Kover patch

Upstream: onnxruntime_plus 1.5.0.

`android/build.gradle` no longer declares its own `buildscript` with Android Gradle Plugin 7.3.0, which conflicts with the app's plugin and needs a download, and compiles against SDK 36 instead of 33. The `example` folder, the armeabi-v7a `libonnxruntime.so` and the macOS, Windows and Linux folders are left out; the voice that uses it is only offered on 64-bit ARM.

Drop this copy and the `dependency_overrides` entry in `pubspec.yaml` once upstream fixes it.

On iOS, the Swift package links `ios/onnxruntime_plus/onnxruntime.xcframework.zip` instead of downloading ONNX Runtime 1.15.1: Microsoft took its GitHub repositories and `download.onnxruntime.ai` offline in November 2026, and the old Azure URL answers 404. The zip is `runtimes/ios/native/onnxruntime.xcframework.zip` from the `Microsoft.ML.OnnxRuntime` 1.22.0 NuGet package, whose SHA-512 matches nuget.org (`zb3eqkL6hHPGzZgArsuTH9VWdUs4ooKTJHBXF6ZZfQsPvzModaAEv3u69zwtqKuwUJ/DPc8i+uKoyXMzdwqrPg==`); the zip's SHA-256 is `8a64917aecbb87ad49ca78f8a1e442f713ea633d8475e576369802fb2af6e767`. It is a static library looked up at runtime through `DynamicLibrary.process()`, so the target links with `-u _OrtGetApiBase` to keep it. The CocoaPods podspec is unchanged and unused, since the app builds plugins with Swift Package Manager.

`OrtValueTensor` gained `createFloats(shape)` and `floats`: the latter reads or updates the float32 data of a tensor in place, without the nested lists that `value` builds, which dominated the time of a synthesis step.
