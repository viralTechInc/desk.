import Foundation

/// A video-call link found on a calendar event (Google Meet, Zoom, Teams…).
struct ConferenceLink: Hashable, Sendable {
    enum Service: Hashable, Sendable {
        case googleMeet, zoom, teams, webex, facetime

        var label: String {
            switch self {
            case .googleMeet: "Google Meet"
            case .zoom: "Zoom"
            case .teams: "Microsoft Teams"
            case .webex: "Webex"
            case .facetime: "FaceTime"
            }
        }
    }

    let url: URL
    let service: Service

    var joinTitle: String { "Join \(service.label)" }

    /// Host plus path, without the scheme or query noise, for display.
    var shortText: String {
        let host = url.host ?? ""
        let path = url.path == "/" ? "" : url.path
        return host + path
    }
}

/// Finds conferencing links in the fields EventKit exposes. Google Calendar puts the Meet
/// link in the event URL or in the description ("Join with Google Meet: https://…"); other
/// services land in the location or notes. Pure so it can be unit-tested.
enum ConferenceLinkDetector {
    static func detect(url: URL?, location: String?, notes: String?) -> ConferenceLink? {
        if let url, let link = classify(url) { return link }
        for text in [location, notes].compactMap({ $0 }) {
            for candidate in urls(in: text) {
                if let link = classify(candidate) { return link }
            }
        }
        return nil
    }

    /// Recognises a known meeting service; anything else is ignored so random links in a
    /// description never masquerade as a call.
    static func classify(_ url: URL) -> ConferenceLink? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path
        let hasPath = path.count > 1
        let service: ConferenceLink.Service?
        if host == "meet.google.com" {
            service = hasPath ? .googleMeet : nil
        } else if host.hasSuffix("zoom.us") || host.hasSuffix("zoom.com") {
            service = (path.hasPrefix("/j/") || path.hasPrefix("/my/") || path.hasPrefix("/w/") || path.hasPrefix("/s/")) ? .zoom : nil
        } else if host == "teams.microsoft.com" || host == "teams.live.com" {
            service = (path.contains("/l/meetup-join") || path.contains("/meet/")) ? .teams : nil
        } else if host.hasSuffix("webex.com") {
            service = hasPath ? .webex : nil
        } else if host == "facetime.apple.com" {
            service = hasPath ? .facetime : nil
        } else {
            service = nil
        }
        guard let service else { return nil }
        return ConferenceLink(url: url, service: service)
    }

    /// Every http(s) URL in free text, in order of appearance.
    static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap { match in
            guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
            return url
        }
    }
}
