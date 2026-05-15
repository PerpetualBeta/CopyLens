import Cocoa
import Sparkle

/// Sparkle 2.x bootstrap. Held by AppDelegate so the SPUStandardUpdater
/// stays alive for the lifetime of the process. Feed URL and EdDSA public
/// key live in Info.plist. The EdDSA value there is currently a placeholder
/// — regenerate before first release.
final class SparkleDelegate: NSObject {

    private var updater: SPUStandardUpdaterController?

    func start() {
        updater = SPUStandardUpdaterController(startingUpdater: true,
                                                updaterDelegate: nil,
                                                userDriverDelegate: nil)
        clog("SparkleDelegate: SPUStandardUpdater started")
    }
}
