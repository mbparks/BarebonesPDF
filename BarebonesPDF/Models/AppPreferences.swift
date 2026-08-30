import Foundation

enum PreferenceKey {
    static let sidebarVisible = "sidebarVisible"
    static let inspectorVisible = "inspectorVisible"
    static let viewerMode = "viewerMode"
    static let zoomBehavior = "zoomBehavior"
}

struct AppPreferences {
    static var sidebarVisible: Bool {
        get { registeredDefaults.bool(forKey: PreferenceKey.sidebarVisible) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.sidebarVisible) }
    }

    static var inspectorVisible: Bool {
        get { registeredDefaults.bool(forKey: PreferenceKey.inspectorVisible) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.inspectorVisible) }
    }

    static var viewerMode: ViewerMode {
        get { ViewerMode(rawValue: registeredDefaults.string(forKey: PreferenceKey.viewerMode) ?? "") ?? .continuous }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: PreferenceKey.viewerMode) }
    }

    static var zoomBehavior: ZoomBehavior {
        get { ZoomBehavior(rawValue: registeredDefaults.string(forKey: PreferenceKey.zoomBehavior) ?? "") ?? .fitWidth }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: PreferenceKey.zoomBehavior) }
    }

    private static var registeredDefaults: UserDefaults {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.sidebarVisible: true,
            PreferenceKey.inspectorVisible: false,
            PreferenceKey.viewerMode: ViewerMode.continuous.rawValue,
            PreferenceKey.zoomBehavior: ZoomBehavior.fitWidth.rawValue
        ])
        return .standard
    }
}
