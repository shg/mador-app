# Mador

Mador is a macOS window management app. The current worktree is intentionally reduced to the smallest useful placement surface while the project moves toward user-defined layouts.

## Provenance

Mador uses code derived from Rectangle 0.95.

Rectangle is distributed under the MIT License and is itself based in part on Spectacle. The repository `LICENSE` file retains the upstream copyright and attribution notices that must remain with substantial portions of the software.

At this stage, Mador exposes only two predefined window placements:

- `Left Half`
- `Right Half`

Other historical predefined actions from Rectangle/Mador are not part of the intended app surface for this branch.

## Requirements

- macOS 11.0+
- Accessibility permission for Mador

## Build

The app uses Swift Package Manager for dependencies.

```bash
xcodebuild -project Mador.xcodeproj -scheme Mador -configuration Debug build
```

## License

Mador is distributed under the MIT License. See [LICENSE](LICENSE).

This repository also uses third-party components, including:

- [Rectangle](https://github.com/rxhanson/Rectangle)
- [Spectacle](https://github.com/eczarny/spectacle)
- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [MASShortcut](https://github.com/rxhanson/MASShortcut)

When redistributing the app or substantial portions of the source, keep the applicable copyright and license notices for Mador, Rectangle, Spectacle, Sparkle, and MASShortcut.

## Use

1. Launch Mador and grant Accessibility access when prompted.
2. Open Preferences.
3. Assign shortcuts for `Left Half` and `Right Half`.
4. Trigger the action from the shortcut or the menu bar menu.

## URL Actions

Mador supports executing the current predefined actions by URL:

- `mador://execute-action?name=left-half`
- `mador://execute-action?name=right-half`

Example:

```bash
open -g "mador://execute-action?name=left-half"
```

The ignore-app tasks are also available:

```text
mador://execute-task?name=ignore-app
mador://execute-task?name=unignore-app
```

You can also pass a bundle identifier:

```text
mador://execute-task?name=ignore-app&app-bundle-id=com.apple.Safari
```

## Troubleshooting

If window movement or resizing does not work as expected:

1. Confirm Accessibility is enabled for Mador in System Settings.
2. Check that no other window manager is intercepting the same shortcuts.
3. Try the menu item instead of the shortcut to separate shortcut issues from window-management issues.
4. Use the logging window from the menu bar item while holding `Option`.

To reset Accessibility permissions for Mador:

```bash
tccutil reset All org.kakera.Mador
```

## Configuration Storage

Preferences are stored in:

`~/Library/Preferences/org.kakera.Mador.plist`

On launch, Mador also checks for a JSON config file at:

`~/Library/Application Support/Mador/MadorConfig.json`

Legacy Rectangle support/config locations are still read for migration compatibility.

## Uninstall

Quit Mador and move the app to the Trash. To remove stored preferences:

```bash
defaults delete org.kakera.Mador
```
