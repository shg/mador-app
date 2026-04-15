# Mador

Mador is a macOS window management app centered on a chooser-driven custom layout workflow. Instead of exposing a large fixed set of predefined window actions, the current app surface is focused on user-defined layouts and per-layout key bindings.

## Provenance

Mador uses code derived from [Rectangle 0.95](https://github.com/rxhanson/Rectangle).

[Rectangle](https://github.com/rxhanson/Rectangle) is distributed under the MIT License and is itself based in part on [Spectacle](https://github.com/eczarny/spectacle). The repository `LICENSE` file retains the upstream copyright and attribution notices that must remain with substantial portions of the software.

The default configuration still starts with two layouts:

- `Left Half`
- `Right Half`

These are only initial examples. You can add, remove, reorder, and edit layouts from the app.

## Requirements

- macOS 11.0+
- Accessibility permission for Mador

## Build

The app uses Swift Package Manager for dependencies.

```bash
xcodebuild -project Mador.xcodeproj -scheme Mador -configuration Debug build
```

## Current Features

- Menu bar app with no Dock icon
- Fixed chooser shortcut: `Option+Q`
- Chooser window for selecting a saved layout
- Custom layouts defined by relative position and size percentages within the active screen's visible frame
- Configurable chooser key bindings per layout, including modifier key combinations
- Layout Manager window for adding, editing, removing, and reordering layouts
- Menu bar item behavior:
  - normal click opens or closes the chooser
  - `Option` click or right click opens the menu
- `Manage Layouts…` is available from both the chooser and the menu bar menu
- Repeating the same layout on the same window within 5 seconds moves that window to the next screen using the same relative layout

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
2. Press `Option+Q` or click the menu bar icon to open the chooser.
3. Press the key assigned to the layout you want to apply.
4. Use `Manage Layouts...` to add or edit layouts and change their chooser key bindings.

Each custom layout stores:

- a name
- a chooser key combination
- `X Anchor`: `Left` or `Right`
- `X %`
- `Y Anchor`: `Top` or `Bottom`
- `Y %`
- `Width %`
- `Height %`

Percentages are evaluated relative to the current screen's visible frame, so the menu bar area is excluded from layout placement.

## Troubleshooting

If window movement or resizing does not work as expected:

1. Confirm Accessibility is enabled for Mador in System Settings.
2. Check that no other window manager is intercepting the chooser shortcut or assigned layout keys.
3. Try the menu bar item instead of the keyboard shortcut to separate shortcut issues from window-management issues.
4. Use the logging window from the menu bar item while holding `Option`.

To reset Accessibility permissions for Mador:

```bash
tccutil reset Accessibility org.kakera.Mador
```

## Configuration Storage

Preferences are stored in:

`~/Library/Preferences/org.kakera.Mador.plist`

On launch, Mador also checks for a JSON config file at:

`~/Library/Application Support/Mador/MadorConfig.json`

Legacy Rectangle support and config locations are still read for migration compatibility.

## Uninstall

Quit Mador and move the app to the Trash. To remove stored preferences:

```bash
defaults delete org.kakera.Mador
```
