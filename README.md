# Windows Taskbar for macOS

A native macOS implementation of a Windows-style taskbar with a modern floating panel, Start menu, quick settings, notifications, and app management.

## Overview

This project recreates the feel of a Windows 11 taskbar on macOS using AppKit and SwiftUI. It runs as a lightweight system utility and is designed to behave like a stylized desktop panel rather than a full macOS shell replacement.

The application includes:

- A taskbar panel per display
- Windows-inspired Start menu and app launcher
- Search, Task View, and desktop controls
- Running app indicators and grouped window management
- Wi‑Fi, sound, battery, Bluetooth, and clock flyouts
- Notification center and quick settings panels
- Dock and login-item integration
- Custom theming and scaling controls

## Requirements

Before running or building the project, make sure your system meets the following:

- macOS 13 or later
- Swift 5.10 or later
- Xcode command line tools installed
- A valid Apple developer identity if you want to sign and package a production build

## Installing prerequisites

If you do not already have the command line tools installed, run:

```sh
xcode-select --install
```

## Running the app

Build the development app:

```sh
./Scripts/build-app.sh
```

Then open the generated app:

```sh
open .build/WindowsTaskbar.app
```

To stop the development build, press `Control-C` in the terminal.

## Creating an installer image

To generate a drag-to-Applications installer image:

```sh
./Scripts/build-dmg.sh
```

For a signed production build, provide a Developer ID certificate:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/build-dmg.sh
```

Apple notarization still requires the developer account credentials and Team ID belonging to the release owner.

## Permissions and system access

On first launch, the app may request system permissions to enable full functionality. These are typical requirements for this kind of desktop utility:

- Accessibility access: required for window management, app activation, and taskbar behavior
- Wi‑Fi access / Location permission: required for nearby network discovery and Wi‑Fi-related controls
- Login items / startup: optional, for launching the taskbar automatically at login
- Dock replacement behavior: the app temporarily hides the macOS Dock while running and restores it when closed

The app only keeps Wi‑Fi connection data in memory for the active connection flow and clears it promptly after use.

## Notes

- The taskbar overlays the bottom edge of the screen and temporarily hides the Dock while active.
- Exiting through the Start menu power actions restores the previous Dock preferences.
- The app is designed for macOS desktops and can manage multi-display layouts.

## Development notes

The project is built around native macOS frameworks and custom UI panels. It is intended as a desktop enhancement and not a full replacement for the operating system shell.
