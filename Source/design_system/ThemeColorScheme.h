#import <Foundation/Foundation.h>

@class TLThemePalette;

NS_ASSUME_NONNULL_BEGIN

void TLAssignSharedColorTokens(TLThemePalette *palette);
void TLApplyLightThemeColors(TLThemePalette *palette);
void TLApplyDarkThemeColors(TLThemePalette *palette);

NS_ASSUME_NONNULL_END
