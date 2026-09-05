#import "Theme.h"
#import "design_system/ThemeColorScheme.h"

// Shared tab/+ animation timing: 1.0 = normal, 10.0 = 10x slower for inspection.
static const CGFloat TLTabAnimationDurationMultiplier = 1.0;

NSColor *TLColorFromHex(NSUInteger hexValue) {
  CGFloat red = ((hexValue >> 16) & 0xff) / 255.0;
  CGFloat green = ((hexValue >> 8) & 0xff) / 255.0;
  CGFloat b = (hexValue & 0xff) / 255.0;
  return [NSColor colorWithCalibratedRed:red green:green blue:b alpha:1.0];
}

NSColor *TLColorWithAlpha(NSColor *color, CGFloat alpha) {
  NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: color;
  return [rgbColor colorWithAlphaComponent:alpha];
}

NSColor *TLContentAccentColorWithAlpha(NSColor *color, CGFloat alpha) {
  return TLColorWithAlpha(color, alpha);
}

NSColor *TLColorByInterpolatingColors(NSColor *startColor, NSColor *endColor, CGFloat progress) {
  CGFloat clampedProgress = MIN(MAX(progress, 0.0), 1.0);
  NSColor *startRGBColor = [startColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: startColor;
  NSColor *endRGBColor = [endColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: endColor;
  CGFloat startRed = 0.0;
  CGFloat startGreen = 0.0;
  CGFloat startBlue = 0.0;
  CGFloat startAlpha = 1.0;
  CGFloat endRed = 0.0;
  CGFloat endGreen = 0.0;
  CGFloat endBlue = 0.0;
  CGFloat endAlpha = 1.0;
  [startRGBColor getRed:&startRed green:&startGreen blue:&startBlue alpha:&startAlpha];
  [endRGBColor getRed:&endRed green:&endGreen blue:&endBlue alpha:&endAlpha];
  return [NSColor colorWithCalibratedRed:startRed + ((endRed - startRed) * clampedProgress)
                                   green:startGreen + ((endGreen - startGreen) * clampedProgress)
                                    blue:startBlue + ((endBlue - startBlue) * clampedProgress)
                                   alpha:startAlpha + ((endAlpha - startAlpha) * clampedProgress)];
}

CGColorRef TLCGColor(NSColor *color) {
  NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: color;
  return rgbColor.CGColor;
}

@implementation TLThemePalette

+ (instancetype)paletteForPreference:(TLThemePreference)preference {
  NSAppearance *appearance = NSApp.effectiveAppearance ?: [NSAppearance currentDrawingAppearance];
  return [self paletteForPreference:preference effectiveAppearance:appearance];
}

+ (instancetype)paletteForPreference:(TLThemePreference)preference effectiveAppearance:(NSAppearance *)appearance {
  BOOL dark = preference == TLThemePreferenceDark ||
    (preference == TLThemePreferenceSystem && [self isDarkAppearance:appearance]);

  TLThemePalette *palette = [[self alloc] init];
  palette.dark = dark;
  TLAssignSharedColorTokens(palette);
  [palette assignSharedLayoutTokens];
  if (dark) {
    TLApplyDarkThemeColors(palette);
  } else {
    TLApplyLightThemeColors(palette);
  }
  return palette;
}

+ (BOOL)isDarkEffectiveAppearance {
  NSAppearance *appearance = NSApp.effectiveAppearance ?: [NSAppearance currentDrawingAppearance];
  return [self isDarkAppearance:appearance];
}

+ (BOOL)isDarkAppearance:(NSAppearance *)appearance {
  appearance = appearance ?: NSApp.effectiveAppearance ?: [NSAppearance currentDrawingAppearance];
  NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:@[
    NSAppearanceNameAqua,
    NSAppearanceNameDarkAqua,
  ]];
  return [match isEqualToString:NSAppearanceNameDarkAqua];
}

- (void)assignSharedLayoutTokens {
  self.topbarHeight = 40.0;
  self.windowInitialWidth = 1200.0;
  self.windowInitialHeight = 720.0;
  self.windowMinimumWidth = 200.0;
  self.windowMinimumHeight = 520.0;
  self.trafficLightLeftInset = 15.0;
  self.trafficLightReservedWidth = 76.0;
  self.sidebarWidth = 250.0;
  self.sidebarMinimumWidth = 150.0;
  self.sidebarMaximumWidth = 320.0;
  self.sidebarTileSelectedBorderWidth = 2.0;
  self.sidebarTileSelectedAccentFillOpacity = 0.03;
  self.sidebarTileSystemIconSize = 16.0;
  self.sidebarAccessoryIconOpacity = 0.32;
  self.tabHeight = 36.0;
  self.compactButtonSurfaceSize = 25.0;
  self.compactButtonSurfaceOffsetX = -2.0;
  self.compactButtonCornerRadius = 6.0;
  self.tabActiveHeightReduction = 1.0;
  self.tabContentVerticalOffset = 1.0;
  self.tabMinWidth = 112.0;
  self.tabMaxWidth = 160.0;
  self.tabIconSize = 18.0;
  self.tabIconGlyphSize = 16.0;
  self.tabFlareRadius = 8.0;
  self.tabActiveFlareRadius = self.tabFlareRadius * 1.2;
  self.tabSelectionSlideDuration = 0.32 * TLTabAnimationDurationMultiplier;
  self.tabNeighborSelectionSlideDuration = 0.24 * TLTabAnimationDurationMultiplier;
  self.tabTeleportSelectionSlideDuration = 0.28 * TLTabAnimationDurationMultiplier;
  self.tabMetadataTransitionDuration = 0.60 * TLTabAnimationDurationMultiplier;
  self.tabSelectionLongJumpDistanceMultiplier = 1.3;
  self.tabReorderSlideDuration = 0.24 * TLTabAnimationDurationMultiplier;
  self.tabLifecycleTransitionDuration = 0.27 * TLTabAnimationDurationMultiplier;
  self.tabClosingTransitionDuration = 0.20 * TLTabAnimationDurationMultiplier;
  self.tabLifecycleCollapsedWidthRatio = 0.30;
  self.tabLifecycleContentFadeDurationRatio = 0.30;
  self.tabInsertionFadeStartProgress = 0.25;
  self.tabInsertionFadeEndProgress = 0.85;
  self.tabSeparatorFadeDuration = 0.20 * TLTabAnimationDurationMultiplier;
  self.tabHoverFadeDuration = 0.20 * TLTabAnimationDurationMultiplier;
  self.historyRowHeight = 60.0;
  self.historyRowSelectionHorizontalInset = 9.0;
  self.historyRowSelectionVerticalInset = 5.0;
  self.composerMinHeight = 76.0;
  self.composerButtonHeight = 46.0;
  self.messageInputSendButtonSize = 32.0;
  self.messageInputMaxHeight = 168.0;
  self.browserBackdropHeight = 75.0;
  self.browserToolbarButtonSize = 28.0;
  self.browserToolbarIconSize = 13.0;
  self.browserReducedHeightSpacing = 40.0;
  self.browserHeightTransitionDuration = 0.20;
  self.browserHeightTransitionOvershoot = 0.04;
  self.browserChatPaneHeightFraction = 0.55;
  self.browserChatPaneTransitionDuration = 0.20;
  self.browserChatPaneSlideDistance = 12.0;
  self.messageInputCornerRadius = 24.0;
  self.slashCommandRowHeight = 28.0;
  self.messageInputMinWidth = 200.0;
  self.messageInputMaxWidth = 800.0;
  self.messageMaxWidth = 760.0;
  self.messageHorizontalInset = 56.0;
  self.messageVerticalSpacing = 30.0;
  self.userMessageMaxWidthMultiplier = 0.70;
  self.assistantMessageMaxWidthMultiplier = 0.90;
  self.controlMinWidth = 78.0;
  self.fieldHeight = 32.0;
  self.settingsSheetWidth = 760.0;
  self.settingsSheetHeight = 640.0;
  self.settingsActionHeight = 34.0;
  self.brandMarkSize = 34.0;
  self.brandMarkInset = 2.0;
  self.brandMarkStrokeWidth = 2.0;
  self.brandMarkDotRadius = 2.4;
  self.brandMarkCrossInset = 7.0;
  self.focusRingSize = 3.0;
  self.borderWidth = 1.0;
  self.workspaceOutlineOpacity = 1.0 / 3.0;
  self.workspaceShadowRadius = 3.0;
  self.workspaceShadowOffsetY = -1.0;
  self.workspaceShadowOpacity = 1.0;
  self.radiusMedium = 8.0;
  self.slashCommandListCornerRadius = self.radiusMedium;
  self.radiusPill = 999.0;
  self.chipRadius = 15.0;
  self.chipVerticalPadding = 6.0;
  self.onboardingDemoOpenAppButtonHeight = 48.0;
  self.onboardingDemoOpenAppButtonHorizontalPadding = 34.0;
  self.onboardingDemoOpenAppButtonTopOffset = 30.0;
  self.space0 = 0.0;
  self.space2 = 4.0;
  self.space3 = 5.0;
  self.space4 = 7.0;
  self.space5 = 10.0;
  self.space6 = 12.0;
  self.space8 = 14.0;
  self.space9 = 16.0;
  self.space10 = 18.0;
  self.space11 = 22.0;
  self.space12 = 24.0;
  self.space16 = 52.0;
  self.sidebarActionIconSize = self.space9;
  self.sidebarActionStackHorizontalInset = self.space6 * 0.5;
  self.sidebarContentLeadingInset = self.space6 + self.space3;
  self.sidebarContentTrailingInset = self.space6;
  self.sidebarAgentTileMaximumWidth = (self.sidebarWidth - self.sidebarContentLeadingInset -
                                      self.sidebarContentTrailingInset - self.space5 * 2.0) / 3.0;
  self.sidebarActionStackLeadingInset = self.sidebarActionStackHorizontalInset + self.space3;
  self.sidebarActionStackTrailingInset = self.sidebarActionStackHorizontalInset;
  self.sidebarActionItemHorizontalInset = self.space5 * 0.5;
  self.sidebarUserButtonHorizontalInset = self.sidebarActionItemHorizontalInset + self.space2;
  self.sidebarUserButtonHeight = self.fieldHeight - self.space2;
  self.sidebarActionItemContentGap = self.space5 * 0.5;
  self.sidebarInboxOuterHorizontalInset = self.space3;
  self.sidebarInboxItemHorizontalInset = self.space5;
  self.sidebarInboxHeaderItemGap = self.space3;
  self.sidebarInboxItemLeadingOffset = 2.0;
  self.sidebarInboxIconSize = self.space6;
  self.sidebarInboxBadgeHorizontalPadding = (self.space4 * 0.5) + 1.0;
  self.sidebarInboxBadgeMinimumWidth = self.space9 + 2.0;
  self.sidebarBookmarkButtonSize = 32.0;
  self.sidebarBookmarkIconSize = 20.0;
  self.sidebarBookmarkSpacing = self.space3;
  self.sidebarBookmarkCornerRadius = self.radiusMedium;
  self.taskStatusPillHeight = self.fieldHeight - self.space2;
  self.taskStatusIndicatorSize = self.space6;
  self.taskStatusIndicatorDotSize = self.space2 * 0.5;
  self.taskStatusIndicatorInactiveOpacity = 0.28;
  self.taskStatusIndicatorBlinkDuration = 1.2;
  self.tabEmojiVerticalOffset = self.space2;
  self.tabIconLeadingInset = self.space5 + self.space5;
  self.tabIconTextSpacing = self.space4;
  self.tabInterTabTightening = 4.0;
  self.menuActionIconTextSpacing = self.space4;
  self.menuActionIconUpwardOffset = -1.0;
  self.agentSharedIconDownwardOffset = 1.0;
  self.agentSharedLabelDownwardOffset = 1.0;
  self.agentMenuAvatarSize = self.space16 * 0.85;
  self.agentTileBadgeWidth = 22.0;
  self.agentTileBadgeHeight = 14.0;
  self.agentTileBadgeIconSize = 12.0;
  self.agentTileBadgeInset = self.space2;
  self.roleOpacity = 0.72;
  self.disabledOpacity = 0.58;
  self.notchOverlayMinimumWidth = 224.0;
  self.notchOverlayMinimumHeight = 42.0;
  self.notchOverlayFallbackNotchWidth = 210.0;
  self.notchOverlayHorizontalPadding = 12.0;
  self.notchOverlayVerticalPadding = 8.0;
  self.notchOverlayTopOffset = 0.0;
  self.notchOverlayProximity = 86.0;
  self.notchOverlayCornerRadius = 16.0;
  self.notchOverlayTopFlareOutset = self.notchOverlayCornerRadius * 0.70;
  self.notchOverlayTopFlareHeight = self.notchOverlayCornerRadius * 0.70;
  self.notchOverlayTrackingInterval = 0.02;
  self.notchOverlayAnimationExpandDuration = 0.18;
  self.notchOverlayAnimationSettleDuration = 0.20;
  self.notchOverlayAnimationHideDuration = 0.20;
  self.notchOverlayAnimationOvershootScale = 1.06;
  self.notchOverlayDropMinimumWidth = 420.0;
  self.notchOverlayDropMinimumHeight = 96.0;
  self.notchOverlayDropHorizontalPadding = 28.0;
  self.notchOverlayDropVerticalPadding = 26.0;
  self.notchOverlayDropPromptDuration = 10.0;
  self.notchOverlayProgressHeight = 2.0;
  self.notchOverlayDropTargetInset = self.space6;
  self.notchOverlayDropIconSize = 40.0;
  self.notchOverlayDropIconSlideDistance = self.space8;
  self.notchOverlayDropIconAnimationDuration = 0.20;
  self.notchOverlayDropGlareDuration = 0.65;
  self.notchOverlayDropGlareOpacity = 0.75;

  self.agentListAvatarFont = [NSFont systemFontOfSize:28.0 weight:NSFontWeightRegular];
  self.bodyFont = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
  self.messageBodyFont = [NSFont systemFontOfSize:15.0 weight:NSFontWeightRegular];
  self.smallFont = [NSFont systemFontOfSize:11.8 weight:NSFontWeightRegular];
  self.labelFont = [NSFont systemFontOfSize:12.4 weight:NSFontWeightSemibold];
  self.sidebarActionTitleFont = [NSFont systemFontOfSize:13.4 weight:NSFontWeightSemibold];
  self.sidebarInboxUnreadTitleFont = [NSFont systemFontOfSize:13.4 weight:NSFontWeightSemibold];
  self.sidebarInboxReadTitleFont = [NSFont systemFontOfSize:13.4 weight:NSFontWeightRegular];
  self.sidebarInboxBadgeFont = [NSFont systemFontOfSize:10.8 weight:NSFontWeightRegular];
  self.tabIconFont = [NSFont fontWithName:@"AppleColorEmoji" size:13.0] ?: [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
  self.roleFont = [NSFont systemFontOfSize:10.5 weight:NSFontWeightBold];
  self.titleFont = [NSFont systemFontOfSize:15.2 weight:NSFontWeightBold];
  self.emptyTitleFont = [NSFont systemFontOfSize:17.0 weight:NSFontWeightBold];
  self.notchOverlayLabelFont = [NSFont systemFontOfSize:16.0 weight:NSFontWeightSemibold];
  self.onboardingDemoCaptionFont = [NSFont fontWithName:@"MyriadPro-Semibold" size:44.0]
      ?: [NSFont fontWithName:@"Myriad Pro Semibold" size:44.0]
      ?: [NSFont systemFontOfSize:44.0 weight:NSFontWeightSemibold];
  self.onboardingDemoAlternativeBrowserCorrectionFont = [NSFont fontWithName:@"Chalkduster" size:52.0]
      ?: [NSFont systemFontOfSize:52.0 weight:NSFontWeightRegular];
  self.onboardingDemoOpenAppButtonFont = [NSFont fontWithName:@"MyriadPro-Semibold" size:22.0]
      ?: [NSFont fontWithName:@"Myriad Pro Semibold" size:22.0]
      ?: [NSFont systemFontOfSize:22.0 weight:NSFontWeightSemibold];
  self.markdownHeading1Font = [NSFont systemFontOfSize:18.0 weight:NSFontWeightBold];
  self.markdownHeading2Font = [NSFont systemFontOfSize:16.0 weight:NSFontWeightBold];
  self.markdownHeading3Font = [NSFont systemFontOfSize:14.2 weight:NSFontWeightSemibold];
  self.markdownCodeFont = [NSFont monospacedSystemFontOfSize:12.2 weight:NSFontWeightRegular];
}

@end
