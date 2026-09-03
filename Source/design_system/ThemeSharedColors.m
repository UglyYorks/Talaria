#import "ThemeColorScheme.h"
#import "Theme.h"

void TLAssignSharedColorTokens(TLThemePalette *palette) {
  palette.black = TLColorFromHex(0x000000);
  palette.white = TLColorFromHex(0xffffff);
  palette.gray50 = TLColorFromHex(0xfafafa);
  palette.gray100 = TLColorFromHex(0xf5f5f5);
  palette.gray200 = TLColorFromHex(0xe5e5e5);
  palette.gray300 = TLColorFromHex(0xd4d4d4);
  palette.gray400 = TLColorFromHex(0xa3a3a3);
  palette.gray500 = TLColorFromHex(0x737373);
  palette.gray600 = TLColorFromHex(0x525252);
  palette.gray700 = TLColorFromHex(0x404040);
  palette.gray800 = TLColorFromHex(0x262626);
  palette.gray900 = TLColorFromHex(0x171717);
  palette.gray950 = TLColorFromHex(0x0a0a0a);
  palette.blue300 = TLColorFromHex(0x93c5fd);
  palette.blue500 = TLColorFromHex(0x0a84ff);
  palette.blue600 = TLColorFromHex(0x2563eb);
  palette.green500 = TLColorFromHex(0x34c759);
  palette.red500 = TLColorFromHex(0xff3b30);
}
