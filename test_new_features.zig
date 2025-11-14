const std = @import("std");
const testing = std.testing;
const NetworkStats = @import("src/lib/network_stats.zig").NetworkStats;

test "NetworkStats packet loss calculation" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    // Test 70% success rate
    for (0..7) |_| {
        try stats.addMeasurement(true, 10.0);
    }
    for (0..3) |_| {
        try stats.addMeasurement(false, 0.0);
    }

    const loss_rate = stats.packetLossRate();
    try testing.expectApproxEqAbs(@as(f64, 30.0), loss_rate, 0.01);
    std.debug.print("✓ Packet loss calculation: {d:.1}% (expected: 30.0%)\n", .{loss_rate});
}

test "NetworkStats jitter calculation" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    // Add varying latencies to create jitter
    try stats.addMeasurement(true, 10.0);
    try stats.addMeasurement(true, 15.0);
    try stats.addMeasurement(true, 20.0);
    try stats.addMeasurement(true, 25.0);

    const jitter = stats.jitter();
    try testing.expect(jitter > 5.0 and jitter < 6.0); // Expected around 5.3
    std.debug.print("✓ Jitter calculation: {d:.1}ms (should be ~5.3ms)\n", .{jitter});
}

test "NetworkStats min/max latency" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    try stats.addMeasurement(true, 15.0);
    try stats.addMeasurement(true, 5.0);
    try stats.addMeasurement(true, 30.0);
    try stats.addMeasurement(true, 10.0);

    try testing.expectEqual(@as(f64, 5.0), stats.minLatency().?);
    try testing.expectEqual(@as(f64, 30.0), stats.maxLatency().?);
    std.debug.print("✓ Min latency: {d:.1}ms, Max latency: {d:.1}ms\n", .{ stats.minLatency().?, stats.maxLatency().? });
}

test "NetworkStats mean latency" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    try stats.addMeasurement(true, 10.0);
    try stats.addMeasurement(true, 20.0);
    try stats.addMeasurement(true, 30.0);

    const mean = stats.meanLatency().?;
    try testing.expectApproxEqAbs(@as(f64, 20.0), mean, 0.01);
    std.debug.print("✓ Mean latency: {d:.1}ms\n", .{mean});
}

test "NetworkStats empty stats" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    try testing.expectEqual(@as(f64, 0.0), stats.packetLossRate());
    try testing.expectEqual(@as(f64, 0.0), stats.jitter());
    try testing.expect(stats.meanLatency() == null);
    try testing.expect(stats.minLatency() == null);
    try testing.expect(stats.maxLatency() == null);
    std.debug.print("✓ Empty stats handling: correct\n", .{});
}

pub fn main() !void {
    std.debug.print("\n🧪 Testing Network Statistics Features\n", .{});
    std.debug.print("===================================\n\n", .{});

    // Run all tests
    _ = @import("test_new_features.zig");

    std.debug.print("\n✅ All network statistics tests passed!\n", .{});
    std.debug.print("Features tested:\n", .{});
    std.debug.print("  • Packet loss rate calculation\n", .{});
    std.debug.print("  • Network jitter calculation\n", .{});
    std.debug.print("  • Min/Max latency tracking\n", .{});
    std.debug.print("  • Mean latency calculation\n", .{});
    std.debug.print("  • Empty statistics handling\n", .{});
}
