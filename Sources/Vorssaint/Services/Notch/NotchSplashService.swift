// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The status is asked of a server on this Mac over plain HTTP, with an
/// ephemeral session of the app's own: nothing is cached, nothing is answered
/// from a cache, and the only header sent unasked says what answer is wanted.
private let splashStatusSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpAdditionalHeaders = ["Accept": "application/json"]
    configuration.waitsForConnectivity = false
    return URLSession(configuration: configuration)
}()

/// The app's own monitoring session.
///
/// `NotchSplashService` - which lives with the dashboard's other rules - is
/// the reading, the task's clock, and the notices, with its world handed in.
/// This is where the app's world is described: the address, the key, and the
/// interval as the settings keep them, the system clock, the words in the
/// language the app speaks, and the system's notifications. A test hands the
/// same class a document it made, a clock of its own, and a list to catch its
/// notices in, and so can ask it what a whole afternoon does to a reading.
extension NotchSplashService {
    static let shared = NotchSplashService(
        read: { url, timeout, key in
            var query = URLRequest(url: url)
            query.httpMethod = "GET"
            query.cachePolicy = .reloadIgnoringLocalCacheData
            query.timeoutInterval = timeout
            if let authorization = NotchSplashEndpoint.authorization(key ?? "") {
                query.setValue(authorization, forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await splashStatusSession.data(for: query)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 200)
        },
        address: { NotchSplashSupport.endpoint() },
        enabled: { NotchSplashSupport.isEnabled() },
        savedInterval: { NotchSplashSupport.savedInterval() },
        savedKey: { NotchSplashSupport.savedAPIKey() },
        keepInterval: { seconds in
            UserDefaults.standard.set(seconds, forKey: DefaultsKey.notchSplashIntervalSeconds)
        },
        clock: Date.init,
        strings: { FeatureStrings.notchSplash(L10n.shared.language) },
        deliver: { notice in Notifier.post(title: notice.title, body: notice.body) })
}
