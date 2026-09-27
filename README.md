# Quby

Native QR app for **iPhone** and **Mac**. Create styled codes, scan from the camera or photos, keep a searchable history, and export what you need — all on-device.

Built with **SwiftUI**, **SwiftData**, and **Foundation Models** (Apple Intelligence) for the **Apple Coding Hackathon**.

## What it solves

Codes for Wi‑Fi, websites, contacts, and more usually end up scattered across screenshots and notes. Quby keeps scanning, creating, safety checks, and history in one place — with optional smart grouping when Apple Intelligence is available.

## Platforms

| Platform | Minimum |
| --- | --- |
| iOS | 26.4 |
| macOS | 26.6 |

Open `Quby/Quby.xcodeproj` in Xcode and run the **Quby** scheme on a simulator, device, or your Mac.

## Features

### Create
- QR types: Website, Contact, Wi‑Fi, Email, SMS, Location, Text
- Appearance controls (colors, shapes, logo)
- Preview and share as PNG, PDF, or SVG
- Save into History

### Scan
- Live camera scanner
- Decode codes from the photo library
- QR and common barcode symbologies
- Optional nearby text context around a scan (OCR)

### History
- Created and scanned codes in one place
- Search, favorites, type filters, and sort order
- Detail view with actions (copy, open, share, type-specific helpers)
- **Smart organization** (Apple Intelligence): groups codes into titled sections with short list titles; reorganize or clear anytime from Filter
- Multi-select export:
  - Plain text
  - CSV (with or without images as a ZIP package)
  - Excel (`.xlsx`, with or without embedded images)
  - JSON
  - PDF table (with or without QR thumbnails)

### Safety & privacy
- Link safety warnings (lookalike domains, unencrypted `http`, and related risks)
- History and generated codes stay on this device
- Smart organization runs on-device via Foundation Models when available

### Settings & onboarding
- App preferences
- First-run guide (scan, create, smart organize, link safety, privacy)

## Project layout

```
Quby/
├── README.md
└── Quby/
    ├── Launch Screen.storyboard
    ├── Quby.xcodeproj
    └── Quby/
        ├── Models/
        ├── Services/
        │   ├── Intelligence/   # Foundation Models (smart History organize)
        │   ├── Creating/
        │   ├── Scanning/
        │   ├── Results/
        │   └── System/
        ├── ViewModels/
        ├── Views/
        └── QubyIcon.icon
```

## Requirements

- Xcode with the matching SDKs for the deployment targets above
- Camera / Photos permissions when using scan features
- Apple Intelligence–capable device (optional) for smart History organization

## Team

Project for the **Apple Coding Hackathon**, by **Xavier Moreno** and **Pol Hernández**.

## License

No license file is included yet. All rights reserved unless otherwise stated.
