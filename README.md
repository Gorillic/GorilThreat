# GorilThreat

GorilThreat is a minimal threat bar addon for WoW Anniversary.

## Features
- Single threat bar with SAFE, RISING, DANGER, AGGRO states
- Movable and resizable bar when unlocked
- In-bar sound toggle icon
- Minimap button to open options
- Profile system: create, rename, delete, and switch
- Optional SharedMedia texture list in Bar style dropdown

## Requirements
- WoW Anniversary (`_anniversary_`)
- Required: `LibThreatClassic2` for threat data (bundled in this package)
- Optional: `SharedMedia` (or any addon that provides `LibSharedMedia-3.0`) for extra bar textures

## Installation
- Installation: Copy the GorilThreat folder into World of Warcraft\_anniversary_\Interface\AddOns\ 
- (final path should be ...\Interface\AddOns\GorilThreat\GorilThreat.toc).


## Commands
- `/gt` or `/gorilthreat`: open options
- `/gt help`: show command help
- `/gt reset`: reset active profile settings
- `/gt test`: run dynamic test cycle
- `/gt test rising|danger|aggro|off`: set explicit test mode

## Profiles
- Use the **Profile** dropdown to switch profiles.
- Use **Profile name** + **Create** to add a profile.
- Use **Rename Active** to rename the current profile.
- Use **Delete Active** to remove the current profile (with confirmation).

## Visual Tuning
- **Enable low noise** reduces SAFE/RISING visual intensity.
- **Low noise alpha (%)** controls how transparent SAFE/RISING states become while low-noise mode is enabled.
- Start around `70-75%` for a softer look without losing readability.
- **Enable aggro blink** adds a pulse effect while you are in AGGRO state.
- **Bar sound button** (top-left of the bar):
  - Left-click toggles addon alert sounds on/off.
  - Right-click opens options quickly.

## Troubleshooting
- If settings do not refresh immediately, run `/reload`.
- If you do not see threat updates, verify threat library availability and combat/target conditions.
- If SharedMedia textures are missing from the list, verify SharedMedia is installed in the same game flavor.
