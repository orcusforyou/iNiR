# Modules — Scoped Agent Rules

This file applies to `modules/` and its children unless a deeper `AGENTS.md` overrides it.

## What modules are in iNiR

`modules/` contains the user-facing UI surface of the shell.
Most requests here are visible, interaction-heavy, and style-sensitive.

### ii-family modules (Material Design)

| Module | Files | Purpose |
|--------|-------|---------|
| `bar/` | 33 | Flagship top/bottom bar with workspace, systray, media, weather |
| `sidebarLeft/` | 21+ | AI chat, YT Music, Wallhaven, anime, draggable widgets |
| `sidebarRight/` | 21+ | Toggles, calendar, notifications, tools (pomodoro, calc, notepad) |
| `controlPanel/` | 11 | Quick settings overlay |
| `settings/` | 21 | All config UI pages |
| `dock/` | 11 | App dock (all 4 positions) |
| `overview/` | 9 | Workspace overview + app search |
| `verticalBar/` | 8 | Vertical bar variant |
| `lock/` | 6 | Lock screen |
| `cheatsheet/` | 9 | Keybind viewer |
| `mediaControls/` | 6 | MPRIS player layouts |
| `wallpaperSelector/` | 7 | Wallpaper picker |
| `regionSelector/` | 7 | Screenshot, recording, OCR tools |
| `clipboard/` | 2 | Clipboard history |
| `onScreenDisplay/` | 3 | Volume/brightness/media OSD |
| `onScreenKeyboard/` | 4 | Virtual keyboard |
| `background/` | 3 | Desktop widgets layer |
| Others | ~15 | altSwitcher, sessionScreen, polkit, screenCorners, shellUpdate, closeConfirm, tilingOverlay, notificationPopup |

### waffle-family modules (Windows 11)

All under `modules/waffle/` — see `modules/waffle/AGENTS.md`.

### Shared infrastructure

`modules/common/` — see `modules/common/AGENTS.md`.

## Expectations when working in modules

- Treat the request as user-facing behavior, not isolated code.
- Consider both panel families when relevant.
- Consider all global styles (material, cards, aurora, inir, angel) when visuals or layout are involved.
- Check loading, empty, disabled, hover, active, and overflow states when appropriate.

## Required workflow

1. Find the authoritative component and its nearby consumers.
2. Read the actual files you will touch.
3. Search for similar module patterns first.
4. Verify singleton and config APIs before using them.
5. Pass preflight before editing.
6. Verify runtime and the exact visible behavior after editing.

## Design rules

- Prefer existing shared widgets from `modules/common/widgets/` over new bespoke implementations.
- Keep visual tokens consistent with the owning family: `Appearance` for ii, `Looks` for waffle.
- Respect user settings such as animation and transparency preferences.
- Do not make the UI more repetitive or heavier unless the request explicitly calls for it.
- LazyLoader pattern is used for heavy panels (Bar, WaffleBar, WaffleStartMenu, etc.).

## Completion standard

A module task is incomplete if any of the following were skipped:
- affected style/family review
- config compatibility review
- overflow and state handling review
- runtime/log verification
- direct feature test
