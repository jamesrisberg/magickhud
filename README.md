# magickHUD

ImageMagick in a hover panel: drop images, pick a preset, check the command, run it. Results
land beside the originals and never overwrite anything. macOS 14+, ImageMagick 7.

## What it is

Drop one or many images onto magickHUD, pick a preset, check the command it will run, and run it:
the results land beside the originals (or wherever the settings say) and never overwrite anything.
magickHUD lives in the menu bar (no Dock icon) and is a MacHUD `hover` panel: MacHUD drops it down
while the pointer is over its dock button, and files dropped on that button arrive as `action drop`.

The panel shows the drop zone (QuickLook thumbnails with `magick identify` dimensions), a
searchable preset list, the preset's fields, a live preview of the exact argv, Run, a
before/after comparison for a single file, and the jobs list: per-file progress, Cancel,
Reveal in Finder and an errors disclosure with magick's own messages. Compact mode is a 44 pt
tile with a wand and a badge (running jobs, else images waiting) that also takes drops; click
it to open the panel. Dismissing hides; summoning brings back the same files, form and jobs.

Status: early (0.1). Needs ImageMagick 7 (`brew install imagemagick`). Without it the panel still shows
thumbnails and sizes (ImageIO) and says what to install.

## Install

Check out HUDKit (the shared kit and build scripts) next to this repo, then install:

```sh
ls ~/dev            # hudkit  magickhud
~/dev/magickhud/install.sh
```

`install.sh` builds a release, quits a running copy, installs `/Applications/magickHUD.app`, links
the `magickhud` command onto your PATH and launches it.

## Use

| Key | Action |
|---|---|
| Control-Option-I (image) | show or hide the panel (global) |
| Cmd-Return | run |
| Cmd-O | choose images |
| Cmd-F | search presets |
| Cmd-Shift-C | copy the command(s) |
| Esc, Cmd-W | clear the search, then hide |

The menu bar icon (a wand) has Show magickHUD, Add Images..., Compact Tile and Quit. Drop image
files (or a folder: the images directly inside it) on the panel, the compact tile or magickHUD's
button in the MacHUD dock.

## Presets

| Preset | argv (after `magick <input>`) |
|---|---|
| Resize | `-resize 50%` / `1920x` / `WxH` with fit (`^` fill, `!` exact, `>` only shrink) |
| Convert format | `-quality Q` for JPEG/WebP/HEIC/AVIF; output extension jpg, png, webp, heic, avif, gif, tiff, pdf |
| Compress | `-strip -quality Q`, same format |
| Web-ready | `-auto-orient -resize 1920x1920> -strip -quality Q`, JPEG/WebP/same |
| Thumbnail | `-auto-orient -thumbnail SxS^ -gravity center -extent SxS` |
| Crop | `-gravity G -crop 1:1` (16:9, 4:3, 3:2, 9:16) `+repage`, or `-crop WxH+X+Y +repage` |
| Trim edges | `-fuzz 5% -trim +repage` |
| Rotate / Flip | `-rotate 90/-90/180`, `-flip`, `-flop`, `-auto-orient` |
| Strip metadata | `-strip` |
| Grayscale | `-colorspace Gray` |
| Adjust colors | `-brightness-contrast BxC`, `-modulate 100,S,100` |
| Blur / Sharpen | `-blur 0xS` / `-sharpen 0xS` |
| Border | `-bordercolor C -border W` |
| Watermark text | `-gravity G -fill C -pointsize P -annotate +M+M TEXT` |
| Contact sheet | `magick montage <inputs> -tile Nx -geometry TxT+S+S -background C` (one output) |
| Custom (batch) | your arguments, with `{input} {output} {dir} {name} {ext}` tokens |

Every run is a batch: each preset (except the contact sheet) makes one command per image. The
commands are argv arrays handed to `Process`; nothing goes through a shell, so a file name or
watermark text is always one argument.

Outputs are `<name>_<preset>.<ext>` (the `output.suffix` setting) beside the original, in a
subfolder, or in one folder (`output.policy`). The Output field takes a one-off template such as
`{dir}/small/{name}.{ext}`. If a file already exists (or two inputs would collide) a `-2`, `-3`
... is added; the input is never written.

## MacHUD contract

Panel `tools`, kind `hover` (compact 44x44, `acceptsFileDrop`, dock `order` 4), socket
`magickhud`. Verbs: the HUDKit set (`hello`, `state`, `subscribe`, `panel show|hide|toggle|frame|mode`,
`settings get|set|schema`, `action`, `quit`) plus `action drop`, `run`, `jobs`, `cancel`,
`presets`, `files`, `clear` and `snapshot`. Full reference: [docs/CONTRACT.md](docs/CONTRACT.md).

```sh
magickhud drop ~/Desktop/*.png
magickhud run web                               # every dropped image
magickhud run resize ~/Desktop/a.png width=800 wait=1
magickhud jobs
magickhud presets query=crop
```

## Settings

| Key | Type | Default | |
|---|---|---|---|
| `output.policy` | `same` / `subfolder` / `folder` | `same` | where results go |
| `output.subfolder` | string | `magickHUD` | the folder beside each image for `subfolder` |
| `output.folder` | path | `~/Pictures/magickHUD` | the folder for `folder` (created on first use) |
| `output.suffix` | string | `_{preset}` | added to the original name |
| `quality.default` | int 1-100 | `85` | the quality presets start with |
| `magick.path` | path | empty | an explicit `magick`; empty searches PATH and the Homebrew prefixes |

Set them in MacHUD's settings window or with `magickhud settings set key=value`. Stored in
`~/Library/Application Support/magickHUD/preferences.json`.

## Build from source

Needs Swift 5.9+ and HUDKit checked out next to this repo (`../hudkit`).

```sh
swift test          # magickHUDKitTests (every preset's argv, naming, runner, identify; live magick runs when installed) + magickHUDTests (socket, manifest)
./build.sh          # build/magickHUD.app (release; ./build.sh debug for a debug build), CLI at Contents/Helpers/magickhud
./install.sh        # build, install to /Applications, link the CLI, launch
build/magickHUD.app/Contents/MacOS/magickHUD --drop <paths> [--preset <id>] [--run] --snapshot /tmp/m.png [--snapshot-mode compact]
```

`--snapshot` writes a PNG of the panel once it settles (after the run with `--run`); the glass is
drawn as a dark stand-in. `--drop` takes the same pipe-separated, percent-encoded list as
`action drop paths=`.

`build.sh` and `install.sh` call HUDKit's shared `scripts/hud-build.sh` and `scripts/hud-install.sh`
(set `HUDKIT_DIR` if HUDKit lives elsewhere). The version comes from [VERSION](VERSION); changes
are in [CHANGELOG.md](CHANGELOG.md).

Layout: `Sources/magickHUDKit` (presets, `CommandBuilder`, `OutputNaming`, `Runner`, `Identify`,
`Job`, settings; no UI), `Sources/magickHUD` (the app; `Resources/` holds Info.plist, the manifest
and the settings schema), `Sources/magickHUDCLI` (the `magickhud` tool).

## Isolation env vars for testing

| Variable | Effect |
|---|---|
| `MAGICKHUD_HOME` | base directory for everything magickHUD writes (default `~/Library/Application Support/magickHUD`); also keeps panel frames apart |
| `MAGICKHUD_SOCKET` | socket name (default `magickhud`); the CLI honours it too |
| `MAGICKHUD_NO_HOTKEYS` | set to skip registering the global hotkey |

```sh
MAGICKHUD_HOME=$(mktemp -d) MAGICKHUD_SOCKET=magickhud-test MAGICKHUD_NO_HOTKEYS=1 \
  build/magickHUD.app/Contents/MacOS/magickHUD &
MAGICKHUD_SOCKET=magickhud-test build/magickHUD.app/Contents/Helpers/magickhud hello
```

## License

MIT, see [LICENSE](LICENSE).
