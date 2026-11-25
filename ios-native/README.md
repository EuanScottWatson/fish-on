# Fish On native preview

This is an early, read-only SwiftUI migration. It uses the existing Fish On HTTP API and has a separate bundle identifier so it can be installed beside the current app. It cannot access or migrate React Native offline drafts; keep the current app installed. Catch editing, camera, offline capture, identification, country collection, guide images/range overlays, surveys, statistics and trip editing are not yet implemented. This preview is not a replacement.

The server is tried at the user-specified address, the existing LAN address and the existing Tailscale address. Tests run against fixtures; no production data belongs in this repository. Generate and build the Xcode project via the Swift workflow. Installation uses the existing iLoader process. Device and remote-network tests remain necessary.
