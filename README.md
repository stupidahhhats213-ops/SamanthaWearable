# SamanthaWearable (iOS)

Native SwiftUI bridge for Samantha Control Center wearable API (`:8510`) with Meta Wearables DAT glasses integration.

**Version:** 0.2.0 (build 3)  
**Bundle ID:** `com.samantha.wearable`  
**Deployment target:** iOS 17.2 (`MinimumOSVersion` in MWDATCore.xcframework 1.0.0)  
**Default server:** `http://100.116.10.96:8510` (Tailscale)  
**Meta SDK:** [meta-wearables-dat-ios](https://github.com/facebook/meta-wearables-dat-ios) **1.0.0**  
**SPM products:** `MWDATCore`, `MWDATCamera`  
**Package tools:** `swift-tools-version: 6.0` · binary built with Xcode toolchain `2660` / iOS SDK `26.5`

## What v0.2.0 does

1. Health-check / register / heartbeat to Samantha (unchanged contract)
2. Real Meta glasses registration + device session via DAT SDK
3. Live glasses telemetry in heartbeats (`glasses_connected`, battery, camera/mic/audio flags)
4. One controlled **TEST CAMERA** capture (in-stream JPEG) with on-phone preview

**Not in this milestone:** vision upload, continuous streaming to server, speech → Samantha, TTS, WebSocket, Hermes.

## Open on a Mac

This project was authored on Windows. Build/install requires **macOS + Xcode 26.4+** (per Meta getting-started; earlier Xcode may work if it can resolve the binary SPM package).

```bash
open ~/Desktop/SamanthaWearable/SamanthaWearable.xcodeproj
```

On first open, Xcode resolves SPM package `https://github.com/facebook/meta-wearables-dat-ios` @ **1.0.0**.

## Physical device prerequisites

1. Meta AI app installed on the iPhone
2. Developer Mode enabled for the glasses (Meta AI → Settings → Your glasses → Developer Mode)
3. Physical iPhone + physical Meta glasses (MockDeviceKit is available in the SDK but **not** wired as the default path)
4. Signed run from Xcode onto the physical iPhone (not Simulator for real glasses)

## Meta registration flow

```text
Launch app → Wearables.configure()
  → user taps CONNECT META GLASSES
  → Wearables.startRegistration() → Meta AI app
  → Meta AI callback samanthawearable://…?metaWearablesAction=…
  → .onOpenURL → Wearables.handleUrl(_:)
  → registrationState == .registered
  → user taps CONNECT → DeviceSession via AutoDeviceSelector
  → connectionState == .connected → heartbeat carries glasses telemetry
```

## Info.plist entries added (Meta)

| Key | Purpose |
|-----|---------|
| `CFBundleURLTypes` / `samanthawearable` | Meta AI registration/permission callback scheme |
| `LSApplicationQueriesSchemes` / `fb-viewapp` | Let SDK detect/open Meta AI |
| `MWDAT.AppLinkURLScheme` | `samanthawearable://` (must match URL scheme) |
| `MWDAT.MetaAppID` | `0` for Developer Mode (skips attestation) |
| ~~`ClientToken` / `TeamID`~~ | **Omitted** for Developer Mode (production-only) |
| `UIBackgroundModes` | `processing`, `bluetooth-central`, `bluetooth-peripheral`, `external-accessory` |
| `UISupportedExternalAccessoryProtocols` | `com.meta.ar.wearable` (BT Classic camera) |
| `NSBluetoothAlwaysUsageDescription` | BLE glasses link |
| `NSBluetoothPeripheralUsageDescription` | BLE glasses link |
| `NSBonjourServices` / `_bonjour._tcp` | Wi-Fi glasses discovery |
| `NSCameraUsageDescription` | Mock phone-camera feed (sample parity) |
| `NSMicrophoneUsageDescription` | Glasses mic permission flow |

**Preserved:** Samantha ATS local-network exceptions for `100.116.10.96` / `192.168.1.241`. ATS is **not** globally disabled. `NSLocalNetworkUsageDescription` updated to cover both Samantha and glasses Wi-Fi.

## Heartbeat glasses fields

When disconnected:

```json
{
  "glasses_connected": false,
  "glasses_battery_percent": null,
  "camera_available": false,
  "microphone_available": false,
  "audio_output_available": false
}
```

When connected, values come from live DAT state (`Device.batteryLevel`, `checkPermissionStatus(.camera/.microphone)`). Audio output is reported **UNSUPPORTED** / `false` — no stable public speaker probe in DAT 1.0.0 core/camera.

## Camera test

Production path: start `DeviceSession` → `addCamera` → `stream.start()` → `stream.capturePhoto(format: .jpeg)` → preview sheet on iPhone.

Standalone `Camera.photo` capture is **experimental** in 1.0.0 and not used.

Speech (`MWDATSpeech`) is **experimental** / not production-publishable — not implemented in UI.

## Acceptance (physical)

Must be verified on physical iPhone + Meta glasses + live Samantha `:8510`. This Windows authoring environment **cannot** run that validation.
