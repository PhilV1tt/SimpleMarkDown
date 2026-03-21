# SimpleMarkDown

A minimal Markdown editor for macOS with live inline preview — no separate pane, the formatting appears directly in the text as you type (Obsidian-style).

## Features

- **Live inline preview** — syntax is hidden when the cursor moves away, rendered inline
- **GitHub Markdown syntax** supported:
  - Headings H1–H6
  - Bold, italic, bold+italic
  - Strikethrough
  - Inline code and fenced code blocks
  - Blockquotes
  - Unordered and ordered lists
  - Task lists `- [ ]` / `- [x]`
  - Tables with column alignment
  - Links and images
  - Horizontal rules
- **Settings** (⌘,) — theme (system / light / dark), font size, font family
- **Open / Save** files (⌘O / ⌘S)

## Install

1. Download `SimpleMarkDown.dmg` from the [latest release](https://github.com/PhilV1tt/SimpleMarkDown/releases/latest)
2. Open the DMG and drag the app to your **Applications** folder
3. First launch: **right-click → Open** (required once to bypass macOS Gatekeeper for unsigned apps)

## Requirements

- macOS 14 or later

## Build from source

- Xcode 15 or later required

1. Clone the repo
2. Open `SimpleMarkDown.xcodeproj` in Xcode
3. Press ⌘R to build and run
