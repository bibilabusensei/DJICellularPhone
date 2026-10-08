# DJICellularPhone

Experimental SwiftUI iPhone/iPad project for DJI Cellular Dongle 2 (IG831T).

**Current state: mock UI and diagnostics only.** Real USB modem access, SIM information, cellular data, IMS/VoLTE voice, audio transport and CallKit integration are not implemented.

## Build
GitHub Actions uses XcodeGen and Xcode to build an unsigned IPA artifact. Unsigned IPAs require separate signing/sideloading before installation.

## Important limits
CallKit provides a calling interface, not a cellular modem driver. iPhone USB access is restricted; DriverKit availability and entitlements differ on iPadOS. No claim is made that IG831T supports accessible VoLTE or that iOS permits third-party system-wide cellular connectivity.

## Next research
Identify IG831T USB VID/PID and interfaces on a host computer; establish supported iOS accessory transport; confirm data protocol, IMS/VoLTE and audio capabilities with real hardware. Avoid firmware and IMEI modification.
