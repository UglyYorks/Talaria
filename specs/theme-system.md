# Theme System

The app must use a portable, token-based native theme system.

## Requirements

- Theme values must be defined as named primitive and semantic tokens in Objective-C.
- Native views must consume semantic theme tokens instead of hard-coded colors, spacing, radius, shadow, or typography values.
- Theme variants must be implemented by resolving semantic tokens from a selected theme preference: `system`, `light`, or `dark`.
- AppKit may store and switch the active theme name, but visual styling must be handled by applying the resolved theme palette to native views.
- The theme should be reusable across apps by keeping theme tokens in a dedicated theme module.
- Light and dark color mappings must live in separate source files. Shared color primitives may live in a shared color-token file.
- Native UI colors must come from the theme color scheme. Do not add `NSColor` literals, hex values, asset colors, or system colors directly in view/controller code.
- Every visual color used by app chrome, native components, generated HTML/CSS, shadows, borders, focus/hover states, and text must be read from the active `TLThemePalette` through a semantic token so it can change when the theme changes.
- View/controller/component code must not derive visual colors with inline alpha, dark-mode conditionals, hard-coded hex values, static CSS color names, or direct `NSColor`/`CGColor` constructors. Add a semantic token to the theme instead.
- Theme changes must reapply the resolved palette to existing windows, controllers, reusable components, generated renderers, cached rows, and layer-backed views so no stale colors remain on screen.
- Content-derived colors, such as an average color sampled from an image, are allowed only when the color represents the content itself rather than the app chrome. These colors must be isolated to that content accent and all surrounding surfaces, borders, hover states, and fallback colors must still come from the theme.
- `make test` must include an audit that rejects direct visual color construction outside the theme module and documented content-derived exceptions.
- If a needed color is missing from the scheme, the agent must ask the user to add it. The request must propose a semantic token name, its intended usage, and values for both light and dark schemes.

## Token Structure

Use primitive tokens for raw design values:

```objc
palette.gray700 = TLColorFromHex(0x404040);
palette.space3 = 5.0;
palette.radiusMedium = 8.0;
```

Use semantic tokens for component-facing values:

```objc
palette.controlSurface = palette.white;
palette.controlText = palette.gray900;
palette.accent = palette.gray700;
palette.controlRadius = palette.radiusMedium;
```

Views must reference semantic tokens:

```objc
button.layer.backgroundColor = palette.accent.CGColor;
button.contentTintColor = palette.accentText;
button.layer.cornerRadius = palette.controlRadius;
```

## Theme Switching

Theme variants should override semantic tokens by resolving a new palette:

```objc
TLThemePalette *palette = [TLThemePalette paletteForPreference:selectedTheme];
```

The app should switch themes by saving the selected theme preference and reapplying the resolved palette to visible windows and controls.
