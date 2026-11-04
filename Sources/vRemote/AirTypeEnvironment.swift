import Foundation

/// The review harness sets these before any shared store is initialized.
/// Production uses the existing preferences namespace to preserve user settings.
enum AirTypeEnvironment {
    static var defaults: UserDefaults = .standard
    static var usageFile = AppStorage.applicationSupportDirectory.appendingPathComponent("Usage/sessions-v1.json")
}
