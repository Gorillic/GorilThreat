# Changelog

## 0.1.2 - Unreleased
- Synced addon version to `0.1.2` in `core.lua` and `GorilThreat.toc`.
- Added minimap right-click action to toggle bar lock/unlock.
- Expanded minimap tooltip with right-click lock/unlock hint.
- Added green unlock overlay on the threat bar while unlocked.
- Improved resize handling to reduce jumpy movement while shaping the bar.
- Updated AGGRO presentation: at 100% aggro, bar is hard red, text shows `AGGRO!!`, and flash is enabled.
- Clarified and expanded project license text in `LICENSE` under ALL RIGHTS RESERVED (TheGorilAbi).
- Explicitly documented that third-party libraries under `libs/` remain under their original licenses.
- Removed unused placeholder `media/` folder (`sfx/.gitkeep`, `textures/.gitkeep`).

## 0.1.1 - 2026-02-20
- Updated minimap icon to Ability_Devour.
- Updated addon icon to Ability_Devour.
- Added short minimap tooltip with addon name and click hint.
- Polished minimap drag behavior by hiding tooltip on drag start.
- Changed project root license from MIT to ALL RIGHTS RESERVED.
- Kept third-party library licensing under `libs/` unchanged.

## 0.1.0 - 2026-02-18
- Initial public baseline.
- Added single threat bar UI with SAFE, RISING, DANGER, AGGRO states.
- Added movable/resizable bar (lock/unlock + resize handle).
- Added minimap button and in-bar sound toggle shortcut.
- Added sound control sync between options and bar button.
- Added dynamic profile management (create, rename, delete with confirmation).
- Added bar style selector with built-in styles and optional SharedMedia support.
- Added grouped/paged style dropdown behavior for large SharedMedia lists.
- Added bar style hover preview with restore on menu close.
- Added missing-library safe behavior for LibThreatClassic2 and graceful fallback handling.
