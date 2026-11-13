# Changelog

## 1.4.0

### New

- **Finisher damage overlay.** A strip on the target's health bar shows roughly how much health your finisher would take off at your current combo points. It turns red when the finisher would kill the target.
- **Pick the finisher to track** in the options panel:
  - Rogue: Eviscerate (default) or Rupture
  - Druid: Ferocious Bite (default) or Rip
- The overlay uses the highest rank you know and updates when you learn a new rank. The options panel shows which rank and damage range it's using.
- Ferocious Bite includes the bonus damage from your extra energy (English client only).
- New options: overlay on/off, overlay color, lethal color, overlay opacity, and **Damage adjust** (50–150%) to account for armor and talents.
- New slash command: `/ncp overlay` turns the overlay on or off.

### Changed

- The options panel is wider, with a new "Damage overlay" column.
- The options preview now shows a sample health bar, so you can see the overlay along with the combo points.

### Notes

- The damage shown is an estimate: the average of the spell tooltip's damage range. Armor, talents, crits and attack power aren't counted. Rupture and Rip show their total damage over the full duration.
- The overlay doesn't show on enemy players whose health is only reported as a percentage.

## 1.3.1

- First release: combo points under your target's nameplate for Rogues and Druids in Cat Form, with interlocking pips, a max-combo glow or pulse, an options panel with live preview, and a minimap button.
