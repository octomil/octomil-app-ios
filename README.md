<p align="center">
  <strong>Octomil iOS App</strong><br>
  Companion app for managing on-device AI models.
</p>

<p align="center">
  <a href="https://github.com/octomil/octomil-app-ios/actions/workflows/ci.yml"><img src="https://github.com/octomil/octomil-app-ios/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/octomil/octomil-app-ios/blob/main/LICENSE"><img src="https://img.shields.io/github/license/octomil/octomil-app-ios" alt="License"></a>
</p>

## Overview

The Octomil iOS app is a companion app that pairs with the [Octomil iOS SDK](https://github.com/octomil/octomil-ios) to provide a management interface for on-device AI models.

### Features

- **Model Management** -- Browse, download, and manage on-device models
- **Device Pairing** -- QR/deep-link pairing with the Octomil platform
- **Settings** -- Configure SDK behavior, telemetry, and privacy preferences

## Requirements

- iOS 16.0+
- Xcode 15.0+

## Getting Started

```bash
# Clone the repo
git clone https://github.com/octomil/octomil-app-ios.git
cd octomil-app-ios

# Generate Xcode project (if using xcodegen)
xcodegen generate

# Open in Xcode
open OctomilApp.xcodeproj
```

## Architecture

```
OctomilApp/
├── App/            # App entry point, state management
├── Screens/        # SwiftUI screens (Home, Pair, ModelDetail, Settings)
├── Services/       # Local pairing server, network services
└── Assets.xcassets # App icons and assets
```

## License

See [LICENSE](LICENSE) for details.
