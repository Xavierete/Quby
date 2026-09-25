# Quby

Native QR app for **iPhone** and **Mac**. Create styled codes, scan from the camera or photos, keep a searchable history, and export what you need.

Built with **SwiftUI** and **SwiftData** for the **Apple Coding Hackathon**.

## Platforms

| Platform | Minimum |
| --- | --- |
| iOS | 26.4 |
| macOS | 26.6 |

Open `Quby/Quby.xcodeproj` in Xcode and run the **Quby** scheme on a simulator, device, or your Mac.

## Features

### Create
- QR types: Website, Contact, Wi‑Fi, Email, SMS, Location
- Appearance controls (colors, logo, and related styling)
- Preview before saving to history

### Scan
- Live camera scanner
- Decode codes from the photo library
- Support for QR and common barcode symbologies
- Optional nearby text context captured around a scan (OCR)

### History
- Created and scanned codes in one place
- Favorites, type filters, and sort order
- Detail view with actions (copy, open, share, and type-specific helpers)
- Multi-select export:
  - Plain text
  - CSV (with or without images as a ZIP package)
  - Excel (`.xlsx`, with or without embedded images)
  - JSON
  - PDF table (with or without QR thumbnails)

### Settings
- App preferences and guide

## Project layout

```
Quby/
├── README.md
└── Quby/
    ├── Quby.xcodeproj
    └── Quby/
        ├── Models/
        ├── Services/
        ├── ViewModels/
        └── Views/
```

## Requirements

- Xcode with the matching SDKs for the deployment targets above
- Camera / Photos permissions when using scan features

## Team

Project for the **Apple Coding Hackathon**, by **Xavier Moreno** and **Pol Hernández**.

## License

No license file is included yet. All rights reserved unless otherwise stated.
