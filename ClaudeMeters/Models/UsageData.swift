import Foundation

struct MeterUsage {
    let percentUsed: Int
    let resetsAt: Date
}

struct UsageSnapshot {
    let session: MeterUsage
    let weekly: MeterUsage
    let fetchedAt: Date
}
