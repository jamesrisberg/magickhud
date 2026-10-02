# Changelog

All notable changes to magickHUD are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/); the current version is in [VERSION](VERSION).

## [Unreleased]

## [0.3.0] - 2026-10-02

### Fixed
- `--snapshot` draws the panel only: it no longer starts the control socket under the app's default name (which clashed with the running app), registers the hotkey or adds a second menu bar icon.

## [0.2.0] - 2026-09-29

### Changed
- Built with HUDKit 0.2.0: `hello` reports contract version 0.2.0, and a socket request's
  `args` values that are JSON objects or arrays reach the app as JSON text.

## [0.1.0] - 2026-09-27

First release: ImageMagick presets in a MacHUD hover panel. macOS 14+, ImageMagick 7.

### Added
- **Presets** (magickHUDKit, no UI): seventeen ImageMagick presets (resize, convert, compress,
  web-ready, thumbnail, crop, trim, rotate/flip, strip, grayscale, adjust, blur, sharpen,
  border, watermark, contact sheet, custom batch arguments). Commands are argv arrays run through
  `Process`, never a shell; `{input}` `{output}` `{dir}` `{name}` `{ext}` `{preset}` tokens.
  Outputs never overwrite an existing file, an input or another output of the run (`-2`, `-3`
  ... suffixes). Sequential batch runner with per-file progress and cancel; `magick identify`
  with an ImageIO fallback when ImageMagick is missing.
- **App**: menu bar app (no Dock icon) with one HUDKit hover panel `tools`: drop zone with
  QuickLook thumbnails and dimensions, searchable presets, the preset's fields, a live argv
  preview, Run, before/after for a single file, and a jobs list with progress, Cancel, Reveal and
  errors. Compact mode is a 44 pt wand tile with a badge that also takes drops. Global hotkey
  Control-Option-I; Cmd-Return, Cmd-O, Cmd-F, Cmd-Shift-C, Esc/Cmd-W in the panel. App icon and
  template menu bar icon from the MacHUD family set.
- **MacHUD contract** through HUDKit: manifest (`xyz.machud.magickhud`, dock `order` 4,
  `acceptsFileDrop`), settings schema (output policy, subfolder, folder, suffix, default quality,
  magick path), verbs `action drop`, `run`, `jobs`, `cancel`, `presets`, `files`, `clear`,
  `snapshot`; `panel show`/`hide` slide from the dock edge with `from=`/`to=`, and a hover show
  never takes key. Drops use HUDKit's `HUDDrop` encoding.
- **Menu bar consolidation**: while MacHUD runs, magickHUD's menu appears in MacHUD's status menu
  (`menu`, `menu-invoke`) and its own icon hides; opt out with `menuBar.consumed=false`, kept in
  `<home>/menubar.json`.
- **CLI** `magickhud` (`Contents/Helpers/magickhud`) with `drop`, `run`, `jobs`, `cancel`,
  `presets`, `files`, `clear`, `snapshot` and `watch` shorthands.
- **Testing**: `MAGICKHUD_HOME` / `_SOCKET` / `_NO_HOTKEYS` isolation; `--drop`, `--preset`,
  `--run`, `--snapshot`, `--snapshot-mode` launch flags.
- **Repo** follows HUDKit's conventions: `magickHUD*` targets, bundle files in
  `Sources/magickHUD/Resources`, `VERSION`, build/install shims into HUDKit's scripts, CI.
