/// Characters outside WinAnsi need a real Unicode font renderer. Never silently
/// replace them with missing glyphs in the small built-in PDF text fallback.
class PdfText {
  static const _extraWinAnsi = {
    0x20ac,
    0x201a,
    0x0192,
    0x201e,
    0x2026,
    0x2020,
    0x2021,
    0x02c6,
    0x2030,
    0x0160,
    0x2039,
    0x0152,
    0x017d,
    0x2018,
    0x2019,
    0x201c,
    0x201d,
    0x2022,
    0x2013,
    0x2014,
    0x02dc,
    0x2122,
    0x0161,
    0x203a,
    0x0153,
    0x017e,
    0x0178,
  };
  static bool needsUnicodeFont(String text) =>
      text.runes.any((r) => r > 255 && !_extraWinAnsi.contains(r));
  static void requireBasicFont(String text) {
    if (needsUnicodeFont(text)) {
      throw UnsupportedError(
        'Non-Western PDF text requires a locally installed LibreOffice for font rendering.',
      );
    }
  }
}
