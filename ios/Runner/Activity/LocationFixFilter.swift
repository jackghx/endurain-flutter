import Foundation

/// Decides which raw CoreLocation fixes become track points.
///
/// Pure value logic with no CoreLocation dependency so it is covered by plain
/// XCTest unit tests. One filter is created per collection run (start, resume
/// after pause, or relaunch recovery) and rejects, in order:
///
/// - fixes CoreLocation marks invalid (negative `horizontalAccuracy`);
/// - fixes less accurate than `maxAccuracyMeters`;
/// - cached fixes stamped well before this collection run started, which iOS
///   can deliver first when updates begin (a few seconds of slack keeps a
///   fresh fix determined just before `startUpdatingLocation` returned);
/// - fixes that do not advance time past the last accepted point;
/// - implausible device-reported speeds;
/// - a short warm-up: until one fix reaches `warmUpAccuracyMeters` (or
///   `warmUpTimeoutMillis` passes), coarse early fixes are discarded so the
///   track does not start with a scatter of points around the true position.
struct LocationFixFilter {
    static let maxAccuracyMeters: Double = 100
    static let warmUpAccuracyMeters: Double = 20
    static let warmUpTimeoutMillis: Int64 = 30_000
    static let staleToleranceMillis: Int64 = 5_000
    static let maxSpeedMetersPerSecond: Double = 90

    enum Decision: Equatable {
        case accept
        case rejectInvalid
        case rejectInaccurate
        case rejectStale
        case rejectOutOfOrder
        case rejectSpeed
        case rejectWarmUp
    }

    let collectionStartMillis: Int64
    private(set) var isWarmedUp = false
    private(set) var lastAcceptedMillis: Int64?

    init(collectionStartMillis: Int64, lastAcceptedMillis: Int64?) {
        self.collectionStartMillis = collectionStartMillis
        self.lastAcceptedMillis = lastAcceptedMillis
    }

    /// Evaluates one fix and records it as the latest point when accepted.
    /// `speed` is the device-reported speed; negative means unavailable.
    mutating func evaluate(
        timestampMillis: Int64,
        horizontalAccuracy: Double,
        speed: Double
    ) -> Decision {
        guard horizontalAccuracy >= 0 else {
            return .rejectInvalid
        }
        guard horizontalAccuracy <= Self.maxAccuracyMeters else {
            return .rejectInaccurate
        }
        guard timestampMillis >= collectionStartMillis - Self.staleToleranceMillis else {
            return .rejectStale
        }
        if let previous = lastAcceptedMillis {
            guard timestampMillis > previous else {
                return .rejectOutOfOrder
            }
            if speed >= 0, speed > Self.maxSpeedMetersPerSecond {
                return .rejectSpeed
            }
        }
        if !isWarmedUp {
            let warmUpElapsed = max(0, timestampMillis - collectionStartMillis)
            guard horizontalAccuracy <= Self.warmUpAccuracyMeters
                || warmUpElapsed >= Self.warmUpTimeoutMillis
            else {
                return .rejectWarmUp
            }
            isWarmedUp = true
        }
        lastAcceptedMillis = timestampMillis
        return .accept
    }
}
