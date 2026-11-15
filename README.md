# DynamicTargetPing

A small World of Warcraft addon that builds a character macro named **DynamicTargetPing** from an ordered list of target names. Put the macro on your action bar to try each name in order and ping the first matching target.

## Install for development (symlink)

A symlink lets WoW load the working copy directly, so edits do not need to be copied into the game folder. Set `WOW_DIR` to your WoW installation directory, then run:

```sh
ln -s "/path/to/DynamicTarget" "$WOW_DIR/_retail_/Interface/AddOns/DynamicTargetPing"
```

Replace `/path/to/DynamicTarget` with this repository checkout's absolute path. The destination must not already exist. For a different WoW edition, replace `_retail_` with its install folder. On Windows, create a directory symlink at `Interface\AddOns\DynamicTargetPing` to this repository (for example, with `mklink /D`).

Remove only the symlink—not this repository—to uninstall the development link. After changing addon Lua code, use `/reload` in-game; after changing the TOC, fully restart WoW.

## Use

- `/dtp` (or the Addon Compartment) toggles a small window: drag rows to reorder, type a name or press **+** for your target, drag the header icon to an action bar. Double-click the header or press **-** to minimize.
- Right-click a target portrait and choose **Add to DynamicTargetPing**, or use `/dtp add [name]`.
- `/dtp list` prints the ordered list; the first matching entry has priority by default.
- `/dtp up <#>` raises an entry's priority. `/dtp remove <name|#>` removes one; `/dtp clear` clears the list.
- `/dtp priority on|off` toggles first-match priority. `/dtp test` shows the generated macro and its character count.
- Open `/macro` and drag **DynamicTargetPing** to an action bar. The macro is created or refreshed automatically. Macro edits are deferred during combat.

Names and priority are saved per character. The generated macro is limited to 255 characters and uses a character macro slot.
