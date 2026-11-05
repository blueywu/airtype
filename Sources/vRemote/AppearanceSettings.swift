import AppKit
import Combine
import SwiftUI

/// An app-local preference. System mode leaves NSWindow.appearance unset.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" }
    }
    var symbol: String {
        switch self { case .system: "circle.lefthalf.filled"; case .light: "sun.max"; case .dark: "moon" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
    var nativeAppearance: NSAppearance? {
        switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
    }
}
final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings(defaults: AirTypeEnvironment.defaults)
    private let defaults: UserDefaults
    @Published var selection: AppAppearance {
        didSet { defaults.set(selection.rawValue, forKey: "appearance.mode") }
    }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        selection = defaults.string(forKey: "appearance.mode").flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
}
struct WindowAppearanceBridge: NSViewRepresentable {
    var selection: AppAppearance
    final class View: NSView {
        var selection: AppAppearance = .system
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.appearance = selection.nativeAppearance
        }
    }
    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ view: View, context: Context) {
        view.selection = selection
        view.window?.appearance = selection.nativeAppearance
    }
}
