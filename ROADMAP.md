# AirType development priorities

## Landed baseline

- `main` was fast-forwarded to `0f53854`: local-only runtime, recordable voice
  shortcuts, and optional on-demand audio with compatibility fallback.
- The origin remote is a third-party fork. Publishing requires a user-owned
  destination or write access; a local merge is not a remote push.

## P0 — Small shell cleanup (this branch)

- Product display name: AirType. Preserve executable, bundle ID, preferences,
  driver identity and signing requirement for continuity.
- Menu contains Settings and Quit only. Settings opens the current control panel;
  a dedicated preferences page is a later step.
- Remove support/payment prompts, code and images from the app and local site.
- Preserve preset mapping choices and show a direct custom-record button for
  every eligible ordinary mapping row. The voice-button restriction is addressed
  by the P1 action-model change, not hidden behind a cosmetic dropdown change.
- Three hand-authored SVG menu-icon candidates are pending user selection.
  Do not apply a candidate or generate the application logo until selection.

## P1 — Separate voice actions by button

- Add explicit Typeless Dictate and Codex Dictation mapping targets, each with
  its own recorded keyboard shortcut; no mandatory global target selector.
- Unconfigured shortcuts remain visibly unconfigured, never silently inherit
  another app's key binding. Preserve Right Cmd for the existing Typeless setup.
- Tie every voice action to remote-microphone ownership and host recording state,
  instead of emitting only a hotkey. Keep one active voice session at a time.
- Switching targets: stop the current target, confirm stop, then start the next;
  on failure report the state instead of starting both or inserting text twice.
- Codex action initially requires the intended Codex window to be foreground.
  First configure/test its dictation hotkey in that app, then record it here.
- Verify keyboard only, remote only, and cross-close; quick tap, disconnect,
  cancellation, timeout and immediate target switching are acceptance cases.

## P2 — Single-source home screen

- Default to the remote microphone; remove MacBook/dual-mixer cards and per-source
  mute/solo from the normal home screen.
- Show connection state, active target, truthful idle/listening state and Stop.
- Move on-demand/compatibility mode, permissions and diagnostics into Settings.
- Add a microphone source picker later if headset/USB microphone input is wanted;
  do not silently mix an extra physical microphone into the current setup.

## Visual track — gated by SVG approval

- Review A (key + waveform), B (air + cursor), C (air + A) at 18/24/48 px on light
  and dark backgrounds. A is the proposed starting direction.
- After selection, refine monochrome idle/listening/error variants for macOS
  template rendering. No permanent product-name text in the menu bar.
- Only then generate the App logo with the requested image-generation workflow;
  apply consistent app/window/asset names and validate the exported icons.

## P3 — Setup and recovery

- Per-action Test with separate key-received, hotkey-sent and host-listening
  evidence. Do not label a simulated trigger as a successful recording.
- Put launch-at-login, language, local log controls and opt-in diagnostic
  recordings into preferences; keep these out of the menu bar.
- Export/import settings and provide a reset of one mapping without deleting all.
- Retain offline behavior and the compatibility fallback; keep old release builds
  for rollback. Hardware acceptance remains separate from automated assertions.
