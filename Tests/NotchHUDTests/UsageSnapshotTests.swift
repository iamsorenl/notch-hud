import Foundation
import Testing
@testable import NotchHUD

@Test func usageSnapshotParsesBothWindows() {
    let data = Data(#"{"five_hour":{"utilization":37},"seven_day":{"utilization":12}}"#.utf8)

    let snapshot = UsageSnapshot.parse(data)

    #expect(snapshot == UsageSnapshot(fiveHourPercent: 37, sevenDayPercent: 12))
}

@Test func usageSnapshotRoundsFractionalUtilization() {
    let data = Data(#"{"five_hour":{"utilization":36.6},"seven_day":{"utilization":0.4}}"#.utf8)

    let snapshot = UsageSnapshot.parse(data)

    #expect(snapshot == UsageSnapshot(fiveHourPercent: 37, sevenDayPercent: 0))
}

@Test func usageSnapshotClampsOutOfRangeUtilization() {
    let data = Data(#"{"five_hour":{"utilization":140},"seven_day":{"utilization":-3}}"#.utf8)

    let snapshot = UsageSnapshot.parse(data)

    #expect(snapshot == UsageSnapshot(fiveHourPercent: 100, sevenDayPercent: 0))
}

@Test func usageSnapshotAllowsOneMissingWindow() {
    let data = Data(#"{"five_hour":{"utilization":50}}"#.utf8)

    let snapshot = UsageSnapshot.parse(data)

    #expect(snapshot == UsageSnapshot(fiveHourPercent: 50, sevenDayPercent: nil))
}

@Test func usageSnapshotIsNilWhenNoWindowsPresent() {
    #expect(UsageSnapshot.parse(Data("{}".utf8)) == nil)
}

@Test func usageSnapshotIsNilForGarbage() {
    #expect(UsageSnapshot.parse(Data("not json".utf8)) == nil)
    #expect(UsageSnapshot.parse(Data(#"{"five_hour":{"utilization":"lots"}}"#.utf8)) == nil)
}
