# Fish On iOS app

This is an Expo / React Native app with native views, native maps, photo selection and location access. It uses the existing Fish On server for catch storage and identification, and downloads the same FishBase and Environment Agency snapshots. It is not a Safari shortcut or an embedded web view.

## Test and build

- Install dependencies: `npm ci`.
- Check that the JavaScript bundles: `npx expo export --platform ios --output-dir /tmp/fishbook-ios-export`.
- A physical iPhone build via Expo EAS requires an Expo account and Apple Developer signing credentials; TestFlight requires a paid Apple Developer Program membership. Run `npx eas-cli login`, `npx eas-cli build:configure`, then `npx eas-cli build --platform ios --profile production` when those accounts are available. A production build must be submitted to TestFlight/App Store Connect to install it. Internal preview builds require registered devices and signing.
- Alternatively, on a Mac with Xcode, use `npx expo run:ios --device` and configure signing in Xcode. Apple account requirements differ for local development signing.
- The bundle identifier `uk.fishbook.homelab` is a placeholder: configure a unique identifier under the owning Apple Developer team before signing. EAS may need to add its project ID to app configuration.

The app defaults to `http://192.168.32.48:7782` and allows an alternative server address under Settings. The existing server has no login and uses HTTP, so use it only on trusted local or private networks. An internet-facing deployment needs authentication and HTTPS before it is safe to expose. An iOS build has not been signed or tested on an iPhone yet.

The native guide and map are an initial implementation. The map shows up to 500 survey points in the visible area; zoom in for more. Some profile content needs an internet connection. Photo identification transmits the photo to Naturalis NIA and may be rate limited.

## Offline catches

Catches saved without a species are kept as review drafts on the phone. Confirm a species and save to queue the catch for upload. Confirmed drafts retry while the app is active and when it returns to the foreground; a stable catch ID prevents duplicate server records after an interrupted response. Pending photos are copied into the app's document storage before the draft is saved. The existing server still provides shared catch storage; photo identification and distribution observations need a connection. The native implementation requires real-device testing, including photo permissions, offline storage, crop gestures, and reinstall/update behaviour.
