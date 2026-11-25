import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/main.dart' show desktopErrorWhere;

/// تقرير أخطاء ويندوز (٢٣ أكتوبر): «Null check operator used on a null value» وصل بلا موضع — صار يحمل
/// أوّل ثلاثة مواضع من كودنا (ملفّ:سطر) بلا مسارات الجهاز.
void main() {
  test('أوّل ثلاثة مواضع من كودنا، بلا تكرار، وما سواها لا يُذكر', () {
    final st = StackTrace.fromString('''
#0      _DevicesWallState.build (package:rad_mysvcs/screens/network_devices/devices_wall_screen.dart:412:23)
#1      StatefulElement.build (package:flutter/src/widgets/framework.dart:5729:27)
#2      _DevicesWallState.build (package:rad_mysvcs/screens/network_devices/devices_wall_screen.dart:412:23)
#3      _TileState._load (package:rad_mysvcs/screens/network_devices/widgets/device_tile.dart:88:9)
#4      DeskShell.build (package:rad_mysvcs/screens/desktop/desktop_shell.dart:240:5)
#5      Extra.x (package:rad_mysvcs/main.dart:10:1)
''');
    expect(desktopErrorWhere(st),
        'screens/network_devices/devices_wall_screen.dart:412 ← screens/network_devices/widgets/device_tile.dart:88 ← screens/desktop/desktop_shell.dart:240');
    expect(desktopErrorWhere(null), '');
    expect(desktopErrorWhere(StackTrace.fromString('#0 x (dart:async/zone.dart:1:1)')), 'async/zone.dart:1');
  });

  test('خطأٌ داخل فلاتر بلا سطرٍ من كودنا (٢٥ نوفمبر — «RangeError (length)» من ويندوز بلا موضع): أوّل ثلاثة مواضع من أيّ حزمة', () {
    final st = StackTrace.fromString('''
#0      _GrowableList.length= (dart:core-patch/growable_array.dart:255:5)
#1      EditableTextState.updateEditingValue (package:flutter/src/widgets/editable_text.dart:3456:12)
#2      TextInput._handleTextInputInvocation (package:flutter/src/services/text_input.dart:2101:9)
#3      TextInput._handleTextInputInvocation (package:flutter/src/services/text_input.dart:2101:9)
#4      MethodChannel._handleAsMethodCall (package:flutter/src/services/platform_channel.dart:600:55)
''');
    expect(desktopErrorWhere(st),
        'core-patch/growable_array.dart:255 ← flutter/widgets/editable_text.dart:3456 ← flutter/services/text_input.dart:2101');
    // كودنا موجود ⇒ مواضعه وحدها كما كانت
    final mixed = StackTrace.fromString('''
#0      RenderEditable.paint (package:flutter/src/rendering/editable.dart:2800:3)
#1      _TemplateEditor.build (package:rad_mysvcs/screens/whatsapp/whatsapp_templates_screen.dart:892:11)
''');
    expect(desktopErrorWhere(mixed), 'screens/whatsapp/whatsapp_templates_screen.dart:892');
  });
}
