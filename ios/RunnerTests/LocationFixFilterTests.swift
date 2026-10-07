import XCTest

@testable import Runner

/// Unit tests for `LocationFixFilter`, the gate between raw CoreLocation fixes
/// and persisted track points.
final class LocationFixFilterTests: XCTestCase {

  private let start: Int64 = 1_700_000_000_000

  private func warmedUpFilter() -> LocationFixFilter {
    var filter = LocationFixFilter(collectionStartMillis: start, lastAcceptedMillis: nil)
    XCTAssertEqual(filter.evaluate(timestampMillis: start, horizontalAccuracy: 5, speed: 2), .accept)
    return filter
  }

  func testRejectsNegativeAccuracyAsInvalid() {
    var filter = warmedUpFilter()

    XCTAssertEqual(filter.evaluate(timestampMillis: start + 1_000, horizontalAccuracy: -1, speed: 2), .rejectInvalid)
  }

  func testRejectsFixesWorseThanMaxAccuracy() {
    var filter = warmedUpFilter()

    XCTAssertEqual(filter.evaluate(timestampMillis: start + 1_000, horizontalAccuracy: 101, speed: 2), .rejectInaccurate)
    XCTAssertEqual(filter.evaluate(timestampMillis: start + 2_000, horizontalAccuracy: 100, speed: 2), .accept)
  }

  func testRejectsCachedFixFromBeforeCollectionStarted() {
    var filter = LocationFixFilter(collectionStartMillis: start, lastAcceptedMillis: nil)

    XCTAssertEqual(filter.evaluate(timestampMillis: start - 120_000, horizontalAccuracy: 5, speed: 0), .rejectStale)
    XCTAssertEqual(filter.evaluate(timestampMillis: start - 5_001, horizontalAccuracy: 5, speed: 0), .rejectStale)
    XCTAssertNil(filter.lastAcceptedMillis)
  }

  func testAcceptsFreshFixStampedJustBeforeCollectionStarted() {
    var filter = LocationFixFilter(collectionStartMillis: start, lastAcceptedMillis: nil)

    XCTAssertEqual(filter.evaluate(timestampMillis: start - 1_000, horizontalAccuracy: 5, speed: 0), .accept)
  }

  func testRejectsFixesThatDoNotAdvanceTime() {
    var filter = warmedUpFilter()

    XCTAssertEqual(filter.evaluate(timestampMillis: start, horizontalAccuracy: 5, speed: 2), .rejectOutOfOrder)
    XCTAssertEqual(filter.evaluate(timestampMillis: start - 1, horizontalAccuracy: 5, speed: 2), .rejectOutOfOrder)
  }

  func testRejectsImplausibleSpeedButIgnoresUnavailableSpeed() {
    var filter = warmedUpFilter()

    XCTAssertEqual(filter.evaluate(timestampMillis: start + 1_000, horizontalAccuracy: 5, speed: 91), .rejectSpeed)
    XCTAssertEqual(filter.evaluate(timestampMillis: start + 2_000, horizontalAccuracy: 5, speed: -1), .accept)
  }

  func testWarmUpDiscardsCoarseFixesUntilOneIsAccurate() {
    var filter = LocationFixFilter(collectionStartMillis: start, lastAcceptedMillis: nil)

    XCTAssertEqual(filter.evaluate(timestampMillis: start + 1_000, horizontalAccuracy: 65, speed: 0), .rejectWarmUp)
    XCTAssertFalse(filter.isWarmedUp)
    XCTAssertEqual(filter.evaluate(timestampMillis: start + 2_000, horizontalAccuracy: 12, speed: 0), .accept)
    XCTAssertTrue(filter.isWarmedUp)
    // Once warmed up, the normal accuracy gate applies.
    XCTAssertEqual(filter.evaluate(timestampMillis: start + 3_000, horizontalAccuracy: 65, speed: 0), .accept)
  }

  func testWarmUpTimesOutSoPoorSkyViewStillRecords() {
    var filter = LocationFixFilter(collectionStartMillis: start, lastAcceptedMillis: nil)

    XCTAssertEqual(filter.evaluate(timestampMillis: start + 29_999, horizontalAccuracy: 40, speed: 0), .rejectWarmUp)
    XCTAssertEqual(filter.evaluate(timestampMillis: start + 30_000, horizontalAccuracy: 40, speed: 0), .accept)
  }

  func testRestoredLastPointBlocksOlderFixesAfterRelaunch() {
    var filter = LocationFixFilter(collectionStartMillis: start, lastAcceptedMillis: start + 5_000)

    XCTAssertEqual(filter.evaluate(timestampMillis: start + 4_000, horizontalAccuracy: 5, speed: 0), .rejectOutOfOrder)
    XCTAssertEqual(filter.evaluate(timestampMillis: start + 6_000, horizontalAccuracy: 5, speed: 0), .accept)
  }
}
