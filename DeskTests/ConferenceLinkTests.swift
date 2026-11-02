import Foundation
import Testing
@testable import Desk

@Suite("Conference link detection")
struct ConferenceLinkTests {
    @Test func meetLinkInNotes() {
        let link = ConferenceLinkDetector.detect(
            url: nil, location: "Office",
            notes: "Weekly sync.\n\nJoin with Google Meet: https://meet.google.com/abc-defg-hij\nOr dial: (CA) +1 587-555-0100")
        #expect(link?.service == .googleMeet)
        #expect(link?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(link?.joinTitle == "Join Google Meet")
        #expect(link?.shortText == "meet.google.com/abc-defg-hij")
    }

    @Test func meetLinkInURLFieldWins() {
        let link = ConferenceLinkDetector.detect(
            url: URL(string: "https://meet.google.com/xyz-abcd-efg"), location: nil,
            notes: "https://zoom.us/j/123456789")
        #expect(link?.service == .googleMeet)
    }

    @Test func zoomInLocation() {
        let link = ConferenceLinkDetector.detect(url: nil, location: "https://us02web.zoom.us/j/123456789?pwd=abc", notes: nil)
        #expect(link?.service == .zoom)
        #expect(link?.url.query == "pwd=abc")
    }

    @Test func teamsInNotes() {
        let notes = "Microsoft Teams meeting\nJoin on your computer: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d\nMeeting ID: 123"
        let link = ConferenceLinkDetector.detect(url: nil, location: nil, notes: notes)
        #expect(link?.service == .teams)
    }

    @Test func unrelatedLinksAreIgnored() {
        #expect(ConferenceLinkDetector.detect(url: URL(string: "https://example.com/agenda"), location: "Room 4", notes: "See https://docs.google.com/document/d/1") == nil)
        #expect(ConferenceLinkDetector.detect(url: nil, location: nil, notes: nil) == nil)
    }

    @Test func bareMeetHostIsNotACall() {
        #expect(ConferenceLinkDetector.detect(url: URL(string: "https://meet.google.com/"), location: nil, notes: nil) == nil)
        #expect(ConferenceLinkDetector.detect(url: nil, location: nil, notes: "https://meet.google.com") == nil)
    }

    @Test func splitterCarriesTheLink() {
        let cal = TestSupport.calendar()
        let day = LocalDate(year: 2026, month: 11, day: 2)
        var source = ExternalEventSplitter.Source(
            eventIdentifier: "ev", title: "Standup",
            start: cal.date(day, minutesFromMidnight: 9 * 60), end: cal.date(day, minutesFromMidnight: 9 * 60 + 30),
            isAllDay: false, calendarID: "c", calendarTitle: "Work", sourceTitle: "Google", color: .blue, location: nil)
        source.notes = "Join with Google Meet: https://meet.google.com/abc-defg-hij"
        let slices = ExternalEventSplitter.slices(of: source, in: day...day, calendar: cal)
        #expect(slices.first?.conference?.service == .googleMeet)
        #expect(ScheduleEntry.external(slices[0]).conference?.url.host == "meet.google.com")
    }
}
