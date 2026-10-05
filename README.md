# Windows Taskbar for macOS

An early native macOS implementation of a Windows 11-style taskbar. It uses AppKit for a borderless, all-Spaces panel and SwiftUI for the taskbar interface.

## Current functionality

- One taskbar panel per connected display
- Geometrically centered Start, Search, Task View, and app buttons
- Discovers a default set of installed macOS applications
- Launches applications and activates or hides running applications
- Tracks running and active application state through `NSWorkspace`
- Adds every normal running macOS application to the taskbar
- Displays Windows-style running and active indicators
- Shows a live time and date with a Windows-style calendar flyout
- Hides the macOS Dock while running and restores its previous settings on exit
- Includes nearby Wi-Fi scanning, permission recovery, secure connection/password flow, disconnect, and power controls
- Keeps Wi-Fi, audio, and battery tray state synchronized while the taskbar is running
- Changes the default audio output device and volume directly from the Sound flyout
- Shows charging state, remaining time, and battery-health data when macOS provides it
- Provides a Windows-style Quick Settings panel for Wi-Fi, Bluetooth status, dark mode, mute, brightness, and volume
- Lists connected Bluetooth devices and opens device management from the same panel
- Replaces the notification redirect with a Windows-style Notification Center and unread badge
- Records taskbar Wi-Fi, battery, Bluetooth, and application lifecycle events with dismiss and Clear all actions
- Includes live Wi-Fi, battery, sound, and running-application widgets
- Provides first-run setup for Accessibility, Wi-Fi permission, login startup, and Dock replacement
- Persists Dock visibility, login startup, and multi-display preferences
- Provides a persistent 26–56 pt taskbar icon-size slider in 0.5 pt steps with live preview and reset
- Scales taskbar height, button spacing, panel placement, and accessible application windows with icon size
- Hides the taskbar on displays occupied by a full-screen application and restores it afterward
- Includes Bluetooth discovery, paired/connected device lists, pairing confirmation, connect, and disconnect actions
- Uses a locale-aware Windows-style month calendar with navigation, today, and selected-date highlighting
- Includes an installer-image build script and optional Developer ID code-signing support
- Uses an Apple-logo Start button with a Windows-style installed-app launcher
- Provides Start-menu search with arrow-key navigation and Return-to-launch
- Persists pin/unpin choices and supports drag or context-menu reordering
- Adds confirmed Lock, Sleep, Restart, Shut Down, Sign Out, and taskbar Exit actions
- Provides Accessibility onboarding for window-level taskbar behavior
- Enumerates, groups, activates, minimizes, restores, and closes real application windows
- Shows a multi-window preview list with permission-safe icon/title fallbacks
- Closes flyouts with Escape or an outside click
- Collapses excess running apps into a responsive overflow panel
- Connects Start, Search, Task View, notifications, and Show Desktop to macOS actions
- Uses a translucent Windows-inspired material

The Apple-logo Start button opens a Windows-style application grid. Search opens Spotlight and Task View opens Mission Control. Wi-Fi, sound, battery, and the clock use custom Windows-style flyouts backed by native macOS system APIs. macOS requests Location access when the user starts Wi-Fi scanning; this permission is required to reveal nearby network names. Wi-Fi passwords remain in memory only for the current connection attempt and are cleared immediately afterward.

## Requirements

- macOS 13 or later
- Swift 5.10 or later

## Build and run

```sh
./Scripts/build-app.sh
open .build/WindowsTaskbar.app
```

Create a drag-to-Applications installer image:

```sh
./Scripts/build-dmg.sh
```

For a production-signed build, provide a Developer ID identity:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/build-dmg.sh
```

Apple notarization still requires the developer account credentials and Team ID belonging to
the release owner.

Stop the development build with `Control-C` in the terminal.

The taskbar currently overlays the bottom edge and temporarily hides the macOS Dock. Exiting through the Start menu power button restores the previous Dock preferences.
