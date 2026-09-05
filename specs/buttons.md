# Theme-Appropriate Buttons

- App-owned buttons must use reusable controls from `Source/design_system/` with the active `TLThemePalette`.
- When adding or changing standard text action buttons, use `TLThemedButton`. Existing design-system icon and glass controls remain appropriate for their intended surfaces.
- Standard text action button backgrounds and their text/icons must use matching semantic token pairs: `primaryActionSurface` with `primaryActionText`, or `secondaryActionSurface` with `secondaryActionText`.
- Do not rely on `NSButton.contentTintColor` or `bezelColor` alone for bordered text buttons. AppKit can override their rendered colors, including in inactive windows and default actions; the design-system component must keep the foreground and background paired.
- Normal, hovered, pressed, disabled, focused, and inactive-window states must remain readable in light and dark themes. Interaction and focus visuals must use semantic tokens. Disabled treatment must preserve the foreground/background pairing.
- Theme changes must update existing buttons, including their title, icons, surface, and interaction states.
- Text action buttons should fit their labels and theme-defined padding. Use full-width buttons only when the layout calls for a full-width action; ordinary card actions should remain compact and fit narrow windows.
- New or changed button rendering must be verified in light and dark themes, including interaction states. Tests must inspect rendered foreground/background colors rather than only assigned tint properties.
- System-managed dialogs may retain native controls and behavior; custom app surfaces must use the design-system controls above.
