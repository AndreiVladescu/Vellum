import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Opens maximised — "fullscreen windowed": the screen's visible frame, so
    // the menu bar and Dock keep their space and the title bar stays. Not
    // `toggleFullScreen`, which takes over the display and hides both.
    //
    // `visibleFrame` rather than `zoom(nil)` because zoom *toggles*: if
    // anything else ever zooms the window first, calling it here would put it
    // back. Falls back to the window's own frame on the vanishingly rare path
    // where there is no screen yet.
    self.setFrame(self.screen?.visibleFrame ?? self.frame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
