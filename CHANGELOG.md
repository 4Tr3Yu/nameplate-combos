# Changelog

## 1.5.0

### Changed

- **The damage overlay is now a separate indicator.** Instead of tinting the target's health bar, the finisher damage shows as a thin yellow bar of its own, attached to the nameplate the same way as the combo points. The health bar itself is no longer changed.
- The indicator is as wide as the health bar and uses the same scale: the yellow part runs from where the target's health would drop to after the finisher up to its current health. It still turns red when the finisher would kill.
- By default it sits just above the health bar.
- If you used 1.4.x, the indicator color and opacity reset to the new yellow, fully opaque defaults.

### New

- Indicator position options: height, vertical offset and horizontal offset.

## 1.4.2

### Fixed

- The damage overlay could stay hidden because the finisher's damage numbers couldn't be read. The addon now tries three ways to read the spell's text, and if the text hasn't loaded yet it tries again a couple of seconds later instead of giving up until you learn a new spell.
- The overlay now draws on top of the health bar the same way the combo points do, so the bar can't cover it.

### New

- `/ncp debug` prints what the overlay is using: tracked finisher, rank, damage numbers found, target health and nameplate details. Include its output when reporting a problem.

## 1.4.1

### Fixed

- Combo points stopped updating and the damage overlay didn't show in 1.4.0. The overlay used spell functions that newer game clients no longer have; it now works with both old and new clients.
- If the damage overlay ever runs into a problem, the combo points keep working and a single message is printed in chat instead.

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
