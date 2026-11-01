import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:converto/services/gui/gui_preferences.dart';

void main() {
  test('Windows preferences use the user profile when HOME is absent', () {
    expect(
      GuiPreferences.dataDirectory({'USERPROFILE': r'C:\Users\Local User'}),
      p.join(r'C:\Users\Local User', '.converto'),
    );
  });
  test('explicit local data directory takes precedence', () {
    expect(
      GuiPreferences.dataDirectory({
        'HOME': '/home/user',
        'USERPROFILE': r'C:\Users\Local User',
        'CONVERTO_DATA_DIR': '/isolated/profile',
      }),
      '/isolated/profile',
    );
  });
}
