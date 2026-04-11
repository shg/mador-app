# Mador Terminal Commands

The current worktree intentionally keeps the public feature set small. Mador currently exposes only two predefined placement actions, `Left Half` and `Right Half`, and the primary way to configure them is through the Preferences window.

This file is therefore limited to a few operational commands that still match the app's current direction.

## Accessibility Reset

If macOS Accessibility permission gets stuck:

```bash
tccutil reset All org.kakera.Mador
```

## Remove Stored Preferences

To clear Mador's stored defaults:

```bash
defaults delete org.kakera.Mador
```

## URL Execution

Current predefined actions can be triggered from Terminal:

```bash
open -g "mador://execute-action?name=left-half"
open -g "mador://execute-action?name=right-half"
```

Ignore-app tasks are also available:

```bash
open -g "mador://execute-task?name=ignore-app"
open -g "mador://execute-task?name=unignore-app"
```

## Configuration File Import

On launch, Mador checks for:

`~/Library/Application Support/Mador/MadorConfig.json`

If present, it imports the file and then renames or removes it. Legacy Rectangle config filenames and support directories are still checked for migration compatibility.

## Notes

Older Rectangle-era terminal commands for snap areas, thirds, fourths, maximize variants, Todo Mode, tiling, cascading, and other predefined actions are intentionally omitted here because they no longer describe the intended app surface of this branch.
