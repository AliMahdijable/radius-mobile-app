import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Same window as the Windows build: 1280×820 centred, never below 420×640
    // (the phone-sized layout clips under that), shrunk to fit small screens.
    let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let width = min(1280, visible.width * 0.92)
    let height = min(820, visible.height * 0.92)
    self.setFrame(
      NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height),
      display: true)
    self.minSize = NSSize(width: 420, height: 640)
    self.title = "MyServices Pro"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
