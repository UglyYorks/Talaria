#!/usr/bin/env python3
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Source"

THEME_FILES = {
    "Source/Theme.h",
    "Source/Theme.m",
    "Source/design_system/ThemeColorScheme.h",
    "Source/design_system/ThemeDarkColors.m",
    "Source/design_system/ThemeLightColors.m",
    "Source/design_system/ThemeSharedColors.m",
}

CONTENT_DERIVED_ALLOWANCES = {
    (
        "Source/design_system/UIComponents.m",
        "colorWithCalibratedRed:redTotal / alphaTotal",
    ),
}

FORBIDDEN_PATTERNS = (
    (re.compile(r"TLColorFromHex\s*\("), "hex color outside theme files"),
    (re.compile(r"TLColorWithAlpha\s*\("), "alpha-derived color outside theme files"),
    (re.compile(r"\[NSColor\s+\w+Color\]"), "NSColor named color outside theme files"),
    (re.compile(r"\[NSColor\s+colorWith\w+"), "NSColor constructor outside theme files"),
    (re.compile(r"\bNSColor\.\w+Color\b"), "NSColor named color outside theme files"),
    (re.compile(r"\bCGColorCreate\w*\s*\("), "CGColor constructor outside theme files"),
    (re.compile(r"#[0-9A-Fa-f]{3,8}\b"), "hex CSS/color literal outside theme files"),
)

CSS_FUNCTION_PATTERN = re.compile(r"\b(?:rgb|rgba|hsl|hsla)\s*\(")
CSS_NAMED_COLOR_PATTERN = re.compile(
    r"\b(?:background|color|border-color|box-shadow|text-shadow)\s*:\s*"
    r"(?:black|white|transparent|red|green|blue|gray|grey)\b"
)


def is_allowed_content_derived(relative_path: str, line: str) -> bool:
    return any(
        relative_path == allowed_path and allowed_snippet in line
        for allowed_path, allowed_snippet in CONTENT_DERIVED_ALLOWANCES
    )


def audit_file(path: pathlib.Path) -> list[str]:
    relative_path = path.relative_to(ROOT).as_posix()
    if relative_path in THEME_FILES:
        return []

    violations = []
    text = path.read_text(encoding="utf-8")
    for line_number, line in enumerate(text.splitlines(), start=1):
        if is_allowed_content_derived(relative_path, line):
            continue

        for pattern, reason in FORBIDDEN_PATTERNS:
            if pattern.search(line):
                violations.append(f"{relative_path}:{line_number}: {reason}: {line.strip()}")

        if CSS_FUNCTION_PATTERN.search(line) and "rgba(%ld" not in line:
            violations.append(f"{relative_path}:{line_number}: static CSS color function: {line.strip()}")

        if CSS_NAMED_COLOR_PATTERN.search(line):
            violations.append(f"{relative_path}:{line_number}: static CSS named color: {line.strip()}")

    return violations


def main() -> int:
    violations = []
    for path in sorted(SOURCE_ROOT.rglob("*")):
        if path.suffix not in {".h", ".m", ".mm", ".cc"}:
            continue
        violations.extend(audit_file(path))

    if violations:
        print("Theme color audit failed. Visual colors must come from TLThemePalette semantic tokens.", file=sys.stderr)
        for violation in violations:
            print(f"  {violation}", file=sys.stderr)
        return 1

    print("Theme color audit passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
