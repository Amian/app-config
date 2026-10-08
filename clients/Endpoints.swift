// Endpoints.swift — reference copy lives in github.com/Amian/app-config (clients/).
// Copy this file into the app unchanged. It reads the app's backend addresses from the shared
// endpoints file, so a backend can move without an app update.
//
// Launch never waits for the network: it uses the copy saved last time, else the built-in
// defaults, then fetches the file in the background (Cloudflare first, GitHub as backup).
// A file that fails any check is ignored and the saved copy is kept.
//
// Usage (once, at launch, before any request):
//     Endpoints.configure(appId: "com.amian.halalchecker", defaults: [
//         "api": URL(string: "https://wrapfast-backend-u2fl.onrender.com")!,
//     ])
// Then build requests from `Endpoints.url("api")`, and on a network error or 5xx call
// `Endpoints.refresh()` (throttled to once a minute) so a moved backend is picked up at once.

import Foundation

enum Endpoints {
    // Shared state below is only touched while holding `lock`.
    nonisolated(unsafe) static var sources = [
        URL(string: "https://apptor-config.pages.dev/endpoints.json")!,
        URL(string: "https://raw.githubusercontent.com/Amian/app-config/main/public/endpoints.json")!,
    ]

    private static let cacheKey = "endpoints.v1"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var appId = ""
    nonisolated(unsafe) private static var builtIn: [String: URL] = [:]
    nonisolated(unsafe) private static var current: [String: URL] = [:]
    nonisolated(unsafe) private static var refreshing = false
    nonisolated(unsafe) private static var lastRefresh: Date?

    /// Call once at launch. `defaults` must name every service the app uses.
    static func configure(appId: String, defaults: [String: URL]) {
        var merged = defaults
        if let saved = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] {
            for (name, value) in saved {
                if let url = URL(string: value) { merged[name] = url }
            }
        }
        lock.lock()
        self.appId = appId
        builtIn = defaults
        current = merged
        lock.unlock()
        refresh(force: true)
    }

    /// The base address for a service, e.g. `Endpoints.url("api")`.
    static func url(_ name: String) -> URL {
        lock.lock()
        defer { lock.unlock() }
        guard let url = current[name] ?? builtIn[name] else {
            preconditionFailure("Endpoints: no address for \"\(name)\". Add it to the defaults in configure().")
        }
        return url
    }

    /// Fetches the file again. Throttled to once a minute unless `force` is set.
    static func refresh(force: Bool = false) {
        lock.lock()
        let now = Date()
        if refreshing || (!force && lastRefresh.map { now.timeIntervalSince($0) < 60 } == true) {
            lock.unlock()
            return
        }
        refreshing = true
        lastRefresh = now
        let appId = self.appId
        let sources = self.sources
        lock.unlock()

        Task.detached(priority: .utility) {
            var found: [String: String]?
            for source in sources {
                if let services = await fetch(source, appId: appId) {
                    found = services
                    break
                }
            }
            finishRefresh(found)
        }
    }

    // Synchronous so it can take the lock (NSLock is not allowed directly in async code).
    private static func finishRefresh(_ found: [String: String]?) {
        lock.lock()
        if let found {
            var merged = builtIn
            for (name, value) in found {
                merged[name] = URL(string: value)
            }
            current = merged
        }
        refreshing = false
        lock.unlock()
        if let found {
            UserDefaults.standard.set(found, forKey: cacheKey)
        }
    }

    /// The services for this app (shared defaults plus its own entry), or nil if the file fails
    /// any check. Every address must be https.
    private static func fetch(_ source: URL, appId: String) async -> [String: String]? {
        let request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let file = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              file["version"] as? Int == 1
        else { return nil }

        var services: [String: String] = [:]
        let sections: [Any?] = [file["default"], (file["apps"] as? [String: Any])?[appId]]
        for case let section? in sections {
            guard let entries = section as? [String: String] else { return nil }
            for (name, value) in entries {
                guard let url = URL(string: value), url.scheme == "https", url.host?.isEmpty == false else {
                    return nil
                }
                services[name] = value
            }
        }
        return services
    }
}
