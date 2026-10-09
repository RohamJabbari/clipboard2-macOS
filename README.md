# Clippy

A native macOS clipboard manager: menu bar app, Spotlight-style quick panel, snippets,
keychain-backed secrets, paste-time transforms and AI actions. Swift 6, SwiftUI first,
AppKit only where SwiftUI can't do the job. Requires macOS 14+; uses Liquid Glass on macOS 26.

## Install / rebuild

```sh
make install     # xcodegen → Release build → quit running copy → /Applications → launch
make test        # unit tests (Swift Testing)
make debug       # Debug build (bundle id at.softmaze.Clippy.debug, separate data)
make icon        # regenerate the app icon set from scripts/make-icon.swift
```

Needs Xcode 26 and `xcodegen` (`brew install xcodegen`). `project.yml` is the source of
truth; the `.xcodeproj` is generated and git-ignored. Signing uses the Apple Development
identity of team `XWTH2647FF` (not ad-hoc) so the Accessibility grant survives rebuilds.

## Using it

| Where | Keys |
|---|---|
| Open quick panel | **⌘⇧V** (change in Settings → General) |
| Navigate / paste | ↑ ↓, **Return** pastes into the app you came from, **⌥Return** pastes as plain text |
| Quick slots | **⌘1–9** paste the item bound to that slot (or the Nth row if the slot is empty); **⌘⇧1–9** binds the selection |
| Actions | **⌘K**: transforms, AI actions, Save as Secret, pin, delete |
| Multi-select | **⌘-click** toggles, **⇧-click** selects a range, **⇧↑/⇧↓** extend, **⌘A** selects all (empty search); Return pastes them all, text joined by line breaks |
| Other | **⌘P** pin, **⌫** delete (history only), **Tab** cycles filters, **Esc** closes |

Filters: All, Pinned, Text, Images, Files, Snippets, Secrets, This App (items copied from the
app you were in when you opened the panel).

**Auto-paste** needs Accessibility access (System Settings → Privacy & Security →
Accessibility → Clippy). Without it Clippy copies the item and you press ⌘V yourself.

**Secrets** are for things like a database password you paste many times a day. Add them in
Settings → Secrets, or select a copied value in the panel and choose ⌘K → Save as Secret
(which also removes it from history). Pasting asks for Touch ID once per unlock window
(default 15 min, ends on sleep/lock), marks the clipboard as concealed so no clipboard
manager records it, and clears it again after 30 s. Bind a secret to a quick slot and give
the slot a global shortcut to paste it from any app without opening the panel.

**Snippets** support `{date}`, `{time}`, `{clipboard}`, `{cursor}` and custom fields like
`{name}`, which prompt for a value before pasting.

**AI actions** (Translate EN/DE/FA, Summarize, Fix Grammar, Explain, custom prompts) run
through the provider chosen in Settings → AI:

- Anthropic (Claude API, default `claude-sonnet-5-5`)
- OpenAI, DeepSeek, OpenRouter, any OpenAI-compatible endpoint (Ollama, LM Studio, Groq…)
- Claude (Subscription): click "Sign in with Claude" in Settings → AI (and "Set Up Claude" if
  Claude Code isn't installed). It drives Anthropic's own Claude Code login, then runs `claude -p`.
  No API key or API billing, but slower to start. Clippy never borrows a subscription token
  itself; that would break Anthropic's terms.

Model IDs aren't hardcoded beyond defaults: "Fetch Models" reads each provider's `/models`.

## Where data lives

| What | Where |
|---|---|
| History database (SwiftData) | `~/Library/Application Support/at.softmaze.Clippy/Clippy.store` |
| Images and thumbnails | `~/Library/Application Support/at.softmaze.Clippy/Blobs/` |
| Settings, ignore list, slots | `UserDefaults` (`at.softmaze.Clippy`) |
| API keys | login Keychain, service `at.softmaze.Clippy.anthropic` |
| Secrets | login Keychain, service `at.softmaze.Clippy.secrets` |

## Architecture

```
Clippy/
  App/            ClippyApp (MenuBarExtra + Settings scenes), AppEnvironment (owns all
                  services, shared paste flows, URL hooks), SettingsOpener, AppPaths/Log
  Models/         ClipItem + Snippet (@Model), RawCapture/ProcessedCapture, AppRef
  Services/
    ClipboardMonitor   polls NSPasteboard.changeCount every 0.5 s (Timer with tolerance);
                       ClipboardFilter decides capture vs skip; PasteboardReader reads types
    CaptureProcessing  @concurrent hashing (SHA-256), PNG + thumbnail encoding, blob writes
    ClipStore          dedupe-by-hash (moves to top), pin, delete, retention, orphan cleanup
    PasteService       pasteboard writes (marked so we don't re-capture), CGEvent ⌘V,
                       concealed secret writes with auto-clear
    Transform          pure text transforms; JSONFormatter keeps key order
    SnippetExpander    placeholder parsing/expansion (pure)
    AI                 providers, streaming clients (Anthropic SSE, OpenAI SSE, Claude Code
                       stream-json), Keychain, AIRun
    Secrets            SecretVault (Keychain CRUD), SecretStore (Touch ID gate, unlock window)
    QuickSlots         ⌘1–9 bindings + global slot shortcuts (KeyboardShortcuts)
    FrontmostAppTracker  remembers the last non-Clippy app (paste target, "This App")
  UI/
    MenuBar/      popover (recent 200 + pinned, search, pause/clear/settings/quit)
    Panel/        QuickPanelController (non-activating NSPanel, NSGlassEffectView on 26,
                  NSVisualEffectView before; local key monitor), PanelViewModel (modes:
                  browse / actions / snippet form / save secret / AI), views
    Settings/     General (+ quick slots), Appearance, Ignored Apps, Snippets, Secrets,
                  Transforms, AI, Sync, About
```

Design notes:

- **Never captured:** `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType`,
  anything Clippy wrote itself (`at.softmaze.clippy.internal`), and copies from ignored apps
  (prefilled with 1Password, Bitwarden, Keychain Access, Passwords).
- **Dedupe:** text and rich text share a hash namespace, so the same words with or without
  formatting are one item; recopying bumps `lastCopiedAt` and keeps the richer formats.
- **Retention:** max items (default 500) and max age (default 30 days); pinned and
  slot-bound items are exempt. Runs after each capture and every 30 minutes.
- **Non-activating panel:** the frontmost app keeps focus, so ⌘V lands where you were typing.
- **Concurrency:** default MainActor isolation (Swift 6.2); hashing and image work run
  `@concurrent` off the main actor; nothing blocks the main thread on capture.
- **Memory:** a 700-capture stress run on a private pasteboard stayed flat at 18–20 MB.
- **Debug hooks** (Debug builds only): `clippy://snapshot?path=…` renders the panel to PNG,
  `clippy://stress?count=N` drives captures through a private pasteboard.
  `clippy://settings`, `clippy://panel`, `clippy://accessibility` work in all builds.

## Not done yet

- Phase 5 (end-to-end encrypted sync + PWA) is waiting on a schema/security-rules review.
- Live AI calls weren't exercised from the build machine (no key there); request shapes and
  stream parsing are unit-tested.
