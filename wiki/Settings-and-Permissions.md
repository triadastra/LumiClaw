# Settings and Permissions

Lumi provides a permissions panel and deep-links into macOS Privacy panes.

## Permissions Panel

In app: `Settings -> Permissions`

Available controls include:

- Accessibility
- Screen Recording
- Microphone
- Camera
- Automation
- Input Monitoring
- Full Disk Access
- Privileged Helper

## Guided Full Access

`Enable Full Access (Guided)` only opens/requests missing permissions and skips already-granted ones.

## Why prompts can reappear after reinstall

macOS permission trust is tied to app identity and signature state.

Prompts can return if:

- app bundle is deleted and recreated
- signing identity changes
- ad-hoc signing is used

Use a stable bundle ID and stable signing identity to reduce re-prompts.
