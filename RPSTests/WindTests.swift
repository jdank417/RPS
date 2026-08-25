//
//  WindTests.swift
//  RPSTests
//
//  Covers the pure throttle/staleness decisions in Wind.swift, ported from
//  the reference app's wind.service.spec.ts (the parts that don't require
//  mocking a live HTTP request, which the reference exercises via Angular's
//  HttpTestingController).
//

import Testing
import Foundation
@testable import RPS

struct WindThrottleTests {

    @Test func fetchesWhenNothingHasEverBeenFetched() {
        let now = Date()
        #expect(Wind.shouldRefresh(now: now, lastFetchAt: nil, lastLat: nil, lastLon: nil, lat: 42.479, lon: -70.82))
    }

    // Called on every GPS fix - about once a second - so not refetching has
    // to be the overwhelmingly common path.
    @Test func doesNotRefetchForABoatThatHasBarelyMoved() {
        let start = Date()
        let now = start.addingTimeInterval(30)
        let should = Wind.shouldRefresh(now: now, lastFetchAt: start, lastLat: 42.479, lastLon: -70.82, lat: 42.4791, lon: -70.8201)
        #expect(!should)
    }

    @Test func refetchesOnceTheBoatHasSailedIntoADifferentForecastCell() {
        let start = Date()
        let now = start.addingTimeInterval(5)
        // Several miles away.
        let should = Wind.shouldRefresh(now: now, lastFetchAt: start, lastLat: 42.479, lastLon: -70.82, lat: 42.6, lon: -70.6)
        #expect(should)
    }

    @Test func refetchesAfterTheRefreshIntervalEvenWithoutMoving() {
        let start = Date()
        let now = start.addingTimeInterval(Wind.refreshInterval + 1)
        let should = Wind.shouldRefresh(now: now, lastFetchAt: start, lastLat: 42.479, lastLon: -70.82, lat: 42.479, lon: -70.82)
        #expect(should)
    }

    @Test func doesNotRefetchJustUnderTheRefreshIntervalWithoutMoving() {
        let start = Date()
        let now = start.addingTimeInterval(Wind.refreshInterval - 1)
        let should = Wind.shouldRefresh(now: now, lastFetchAt: start, lastLat: 42.479, lastLon: -70.82, lat: 42.479, lon: -70.82)
        #expect(!should)
    }
}

struct WindStalenessTests {

    @Test func freshReadingIsNotStale() {
        let reading = WindReading(fromDeg: 200, speedKts: 10, gustKts: nil, at: Date())
        #expect(!Wind.isStale(reading, now: reading.at.addingTimeInterval(60)))
    }

    @Test func readingPastStaleIntervalIsStale() {
        let reading = WindReading(fromDeg: 200, speedKts: 10, gustKts: nil, at: Date())
        #expect(Wind.isStale(reading, now: reading.at.addingTimeInterval(Wind.staleInterval + 1)))
    }

    @Test func ageTextDescribesJustNowMinutesHoursAndDays() {
        let readingAt = Date()
        let reading = WindReading(fromDeg: 0, speedKts: 5, gustKts: nil, at: readingAt)
        #expect(Wind.ageText(reading, now: readingAt.addingTimeInterval(10)) == "just now")
        #expect(Wind.ageText(reading, now: readingAt.addingTimeInterval(12 * 60)) == "12 min ago")
        #expect(Wind.ageText(reading, now: readingAt.addingTimeInterval(3 * 3600)) == "3h ago")
        #expect(Wind.ageText(reading, now: readingAt.addingTimeInterval(2 * 24 * 3600)) == "2d ago")
    }
}
