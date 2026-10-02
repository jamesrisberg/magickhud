# magickHUD's MacHUD contract

magickHUD implements the MacHUD contract through HUDKit; the canonical spec is HUDKit's
[docs/CONTRACT.md](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md). MacHUD reads
`magickHUD.app/Contents/Resources/machud.json` without launching the app and talks to the running
app over a Unix socket.

The shared parts are specified there and not repeated here: [socket](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#socket) (location,
framing, replies), the [required verbs](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#verbs), [`subscribe`](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#subscribe-and-state-events),
the [settings schema](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#settings-schema) format, [hover and windowed behaviour](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#behaviour-hover-and-windowed),
[file drops](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#file-drops), the [launch announcement](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#launch-announcement) and [menu bar consolidation](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#menu-bar-consolidation).
This page lists what magickHUD adds.

- Manifest: `Sources/magickHUD/Resources/machud.json`: app `xyz.machud.magickhud`, socket `magickhud`, one panel
  `tools` (`kind: hover`, symbol `wand.and.stars`, default 720x560, compact 44x44, capabilities
  `acceptsFileDrop`, settings schema `settings.json`, dock `order` 4: after Scratch, Stash and
  ffmpegHUD).
- Hover: MacHUD shows the panel while the pointer is over its dock button and hides it on leave.
  `panel show`/`hide`/`toggle` fade in 0.22 s / out 0.18 s and keep the last frame, mode, dropped
  files, form and jobs. Neither a socket show nor launch activates the app, and only
  `reason=click`/`summon` makes the panel key; otherwise it becomes key when clicked
  (Control-Option-I and the menu bar item show it focused). Dock options: `from=<edge>` slides
  out of that edge to the `panel frame` MacHUD assigned (else next to `anchor=x,y,w,h`), in
  0.08 s with `reason=hover`; `hide to=<edge>` slides back in 0.1 s. A show during a hide wins. Dismiss
  (the header's close button, Esc, Cmd-W) hides; it never quits.
- Drops: files dropped on the dock button arrive as `action drop paths=`. Paths are
  percent-encoded (everything except ASCII letters, digits and `/-._~`) and joined with `|`, the
  same encoding as HUDKit's `HUDDrop`; `file://` URLs and plain paths are accepted too.
- Socket: `~/Library/Application Support/MacHUD/sockets/magickhud.sock` (0600), one JSON object
  per line in and out.
- CLI: `magickhud <command> [key=value ...]` (`magickHUD.app/Contents/Helpers/magickhud`).
  `drop`, `run`, `jobs`, `cancel`, `presets`, `files`, `clear` and `snapshot` are shorthands for
  `action name=<verb>`; file arguments are encoded for you.

## Verbs

| Command | Args | Result |
|---|---|---|
| `hello` | | `{app, name, hudkit, version, panels, verbs}`: `hudkit` is the contract version, `version` the app's |
| `state` | | `{panels: [{id: "tools", visible, mode, badge?, status?}]}`: `badge` is the number of running jobs, else of dropped images (absent when zero); `status` is the newest job's line (`Resize 2/5`, `Resize: 5 done`, `Resize: 1 failed`), else `3 images` |
| `subscribe` | `events=state` | `state` events on visibility, mode, frame, drops and every job change |
| `panel show` / `hide` / `toggle` | `id=tools`, optional `from=`/`to=<edge>`, `anchor=x,y,w,h`, `reason=hover\|click\|summon` | without taking focus (unless `reason=click`/`summon`); `from=`/`to=` slide out of / back into the dock (see Hover above) |
| `panel frame` | `id=tools x= y= w= h=` | AppKit screen coordinates, kept for the current mode |
| `panel mode` | `id=tools` + `full`, `compact` or `parked` (`edge=`, `peek=`) | `compact` is the 44 pt wand tile with the badge; a click returns to full |
| `action drop` | `paths=` (required), `show=1` | adds the images (a folder adds the images directly inside it; missing files and non-images are skipped, duplicates ignored), identifies them, then replies `{added: [{path, format, width, height, frames, bytes}], skipped: [...], count}` |
| `action run` | `preset=` (required), `input=` (encoded list, default: the dropped images), `output=` (template), `wait=1`, `show=1`, plus the preset's fields as `key=value` | plans and starts a job. Replies `{job}` at once, or with `wait=1` when it has finished (`ok` false if any file failed, with `error`). An unknown field is an error that lists the preset's fields |
| `action jobs` | `id=` (optional) | `{running, jobs: [...]}` newest first, or `{job}` |
| `action cancel` | `id=` (default: every running job) | stops the running command (its partial output is removed) and skips the rest |
| `action presets` | `query=` | `{presets: [{id, title, summary, combinesInputs, fields: [{id, label, kind, default, options?, required?}]}]}` |
| `action files` | | the dropped images |
| `action clear` | | empties the drop zone |
| `action snapshot` | `path=`, `preset=` | writes a PNG of the panel (debugging, docs) |
| `action show` / `hide` / `toggle` | | same as the panel verbs |
| `settings get` / `set` / `schema` | | see below |
| `quit` | | replies, cancels running jobs, quits (the socket file is removed) |

A job is `{id, preset, title, state (pending/running/done/failed/cancelled), progress (0-1), done,
failed, total, created, outputs, items: [{inputs, output, status, argv, exit?, error?}]}`.

Output tokens (in `output=`, `output.suffix` and the custom preset's arguments): `{input}`,
`{output}`, `{dir}` (the input's folder), `{name}` (its name without extension), `{ext}` (the
output extension), `{preset}` (the preset's word, e.g. `resized`). A relative template is beside
the input; one without an extension gets the preset's. Outputs never overwrite: an existing
file, an input or another output of the same run gets a `-2`, `-3` ... suffix.

```sh
magickhud action run preset=resize input=/tmp/a%20b.png width=32 wait=1
magickhud run convert ~/Desktop/shot.png format=webp quality=70
magickhud run custom args="-resize 50% -strip" ext=jpg
```

## Settings

`Sources/magickHUD/Resources/settings.json` (HUDKit's settings schema format); values are stored
in `<home>/preferences.json`, where home is `~/Library/Application Support/magickHUD` or
`$MAGICKHUD_HOME`. `settings set` validates every value before applying any.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `output.policy` | `same` / `subfolder` / `folder` | `same` | where results go |
| `output.subfolder` | string | `magickHUD` | the folder beside each image for `subfolder` |
| `output.folder` | path | `~/Pictures/magickHUD` | the folder for `folder` (created on first use) |
| `output.suffix` | string | `_{preset}` | added to the original name |
| `quality.default` | int 1-100 | `85` | the quality presets start with |
| `magick.path` | path | empty | an explicit `magick`; empty searches PATH and the Homebrew prefixes |

## Menu bar consolidation

While MacHUD runs it shows magickHUD's status menu inside its own (`menu`, `menu-invoke`) and
the menu bar icon hides; it comes back when MacHUD quits or the user turns the
`menuBar.consumed` setting off (served by HUDKit's router, default `true`). The setting is
kept in `<home>/menubar.json` (so `MAGICKHUD_HOME` isolates it), never in the user's real preferences from a test instance.
See [menu bar consolidation](https://github.com/jamesrisberg/hudkit/blob/main/docs/CONTRACT.md#menu-bar-consolidation).

## Environment

| Variable | Read by | Effect |
|---|---|---|
| `MAGICKHUD_HOME` | app | base directory for preferences; an isolated instance also keeps its panel frames apart |
| `MAGICKHUD_SOCKET` | app, CLI | socket name (default `magickhud`) |
| `MAGICKHUD_NO_HOTKEYS` | app | skip the global hotkey |

Together they let a second instance run beside the real one:

```sh
MAGICKHUD_HOME=/tmp/mh MAGICKHUD_SOCKET=magickhud-test MAGICKHUD_NO_HOTKEYS=1 \
  build/magickHUD.app/Contents/MacOS/magickHUD &
MAGICKHUD_SOCKET=magickhud-test build/magickHUD.app/Contents/Helpers/magickhud state
```

## Launch flags

| Flag | Effect |
|---|---|
| `--drop <paths>` | start with these images (the `action drop paths=` encoding: pipe-separated, percent-encoded) |
| `--preset <id>` | start on that preset |
| `--run` | run the preset on the dropped images (with `--snapshot`, the PNG is written after the run) |
| `--snapshot <path.png>` | show the panel, write a PNG of it once it settles (dark stand-in for the glass) and quit; serves no control socket, announces nothing, registers no hotkey and adds no menu bar item, so it never touches a running instance |
| `--snapshot-mode compact` | picture the compact tile rather than the full panel |
