# Design System Components

- Reusable native UI components must live in `Source/design_system/`.
- View and control classes intended for reuse across app surfaces must use the `TL` prefix.
- App-specific controllers may compose design system components, but must not define reusable design system controls inline.
- Design system components must consume `TLThemePalette` semantic tokens for colors, spacing, radius, and typography.
