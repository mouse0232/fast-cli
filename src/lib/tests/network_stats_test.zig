const std = @import("std");
const testing = std.testing;
const NetworkStats = @import("network_stats.zig").NetworkStats;

test "NetworkStats packet loss calculation" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    // Add 7 successful and 3 failed measurements
    for (0..7) |_| {
        try stats.addMeasurement(true, 10.0);
    }
    for (0..3) |_| {
        try stats.addMeasurement(false, 0.0);
    }

    const loss_rate = stats.packetLossRate();
    try testing.expectApproxEqAbs(@as(f64, 30.0), loss_rate, 0.01);
}

test "NetworkStats jitter calculation" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    // Add varying latencies
    try stats.addMeasurement(true, 10.0);
    try stats.addMeasurement(true, 20.0);
    try stats.addMeasurement(true, 30.0);
    try stats.addMeasurement(true, 40.0);

    const jitter = stats.jitter();
    try testing.expectApproxEqAbs(@as(f64, 10.0), jitter, 0.01);
}

test "NetworkStats min/max latency" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    try stats.addMeasurement(true, 15.0);
    try stats.addMeasurement(true, 25.0);
    try stats.addMeasurement(true, 10.0);
    try stats.addMeasurement(true, 30.0);

    try testing.expectEqual(@as(f64, 10.0), stats.minLatency().?);
    try testing.expectEqual(@as(f64, 30.0), stats.maxLatency().?);
}

test "NetworkStats with no measurements" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    try testing.expectEqual(@as(f64, 0.0), stats.packetLossRate());
    try testing.expectEqual(@as(f64, 0.0), stats.jitter());
    try testing.expect(stats.meanLatency() == null);
    try testing.expect(stats.minLatency() == null);
    try testing.expect(stats.maxLatency() == null);
}
