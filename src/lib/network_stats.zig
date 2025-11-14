const std = @import("std");
const testing = std.testing;

pub const NetworkStats = struct {
    allocator: std.mem.Allocator,
    latencies: std.ArrayList(f64),
    packet_count: u32 = 0,
    successful_packets: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) NetworkStats {
        return NetworkStats{
            .allocator = allocator,
            .latencies = std.ArrayList(f64).init(allocator),
        };
    }

    pub fn deinit(self: *NetworkStats) void {
        self.latencies.deinit();
    }

    pub fn addMeasurement(self: *NetworkStats, success: bool, latency_ms: f64) !void {
        self.packet_count += 1;
        if (success) {
            self.successful_packets += 1;
            try self.latencies.append(latency_ms);
        }
    }

    pub fn packetLossRate(self: *const NetworkStats) f64 {
        if (self.packet_count == 0) return 0.0;
        const lost_packets = self.packet_count - self.successful_packets;
        return (@as(f64, @floatFromInt(lost_packets)) / @as(f64, @floatFromInt(self.packet_count))) * 100.0;
    }

    pub fn jitter(self: *const NetworkStats) f64 {
        if (self.latencies.items.len < 2) return 0.0;

        var jitter_sum: f64 = 0.0;
        var count: u32 = 0;

        // Calculate mean latency first
        const mean_latency = self.meanLatency() orelse 0.0;

        // Calculate jitter as mean deviation from mean latency
        for (self.latencies.items) |latency| {
            jitter_sum += @abs(latency - mean_latency);
            count += 1;
        }

        return if (count > 0) jitter_sum / @as(f64, @floatFromInt(count)) else 0.0;
    }

    pub fn meanLatency(self: *const NetworkStats) ?f64 {
        if (self.latencies.items.len == 0) return null;

        var sum: f64 = 0.0;
        for (self.latencies.items) |latency| {
            sum += latency;
        }
        return sum / @as(f64, @floatFromInt(self.latencies.items.len));
    }

    pub fn minLatency(self: *const NetworkStats) ?f64 {
        if (self.latencies.items.len == 0) return null;

        var min = self.latencies.items[0];
        for (self.latencies.items[1..]) |latency| {
            if (latency < min) min = latency;
        }
        return min;
    }

    pub fn maxLatency(self: *const NetworkStats) ?f64 {
        if (self.latencies.items.len == 0) return null;

        var max = self.latencies.items[0];
        for (self.latencies.items[1..]) |latency| {
            if (latency > max) max = latency;
        }
        return max;
    }

    pub fn latencyDistribution(self: *const NetworkStats, allocator: std.mem.Allocator) !std.ArrayList(f64) {
        if (self.latencies.items.len == 0) {
            return std.ArrayList(f64).init(allocator);
        }

        // Copy and sort latencies for percentile calculation
        const sorted = try allocator.dupe(f64, self.latencies.items);
        defer allocator.free(sorted);
        std.mem.sort(f64, sorted, {}, std.sort.asc(f64));

        // Calculate percentiles: 5th, 25th, 50th (median), 75th, 95th
        var percentiles = std.ArrayList(f64).init(allocator);
        const percentiles_to_calc = [_]f64{ 0.05, 0.25, 0.5, 0.75, 0.95 };

        for (percentiles_to_calc) |percentile| {
            const index = @as(usize, @intFromFloat(percentile * @as(f64, @floatFromInt(sorted.len - 1))));
            try percentiles.append(sorted[index]);
        }

        return percentiles;
    }
};

test "NetworkStats basic functionality" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    // Test empty stats
    try testing.expectEqual(@as(f64, 0.0), stats.packetLossRate());
    try testing.expectEqual(@as(f64, 0.0), stats.jitter());
    try testing.expect(stats.meanLatency() == null);

    // Add some measurements
    try stats.addMeasurement(true, 10.0);
    try stats.addMeasurement(true, 20.0);
    try stats.addMeasurement(false, 0.0); // Failed measurement

    // Test calculations
    try testing.expectApproxEqAbs(@as(f64, 33.33), stats.packetLossRate(), 0.01);
    try testing.expectApproxEqAbs(@as(f64, 15.0), stats.meanLatency().?, 0.01);
    try testing.expectApproxEqAbs(@as(f64, 5.0), stats.jitter(), 0.01);
}

test "NetworkStats jitter calculation" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    // Add consistent latencies (low jitter)
    try stats.addMeasurement(true, 10.0);
    try stats.addMeasurement(true, 11.0);
    try stats.addMeasurement(true, 10.5);
    try stats.addMeasurement(true, 10.2);

    const jitter = stats.jitter();
    try testing.expect(jitter < 1.0); // Should be low jitter

    // Add varying latencies (high jitter)
    var stats2 = NetworkStats.init(testing.allocator);
    defer stats2.deinit();

    try stats2.addMeasurement(true, 10.0);
    try stats2.addMeasurement(true, 50.0);
    try stats2.addMeasurement(true, 100.0);
    try stats2.addMeasurement(true, 30.0);

    const jitter2 = stats2.jitter();
    try testing.expect(jitter2 > 20.0); // Should be high jitter
}

test "NetworkStats latency distribution" {
    var stats = NetworkStats.init(testing.allocator);
    defer stats.deinit();

    // Add sample latencies
    for (0..100) |i| {
        try stats.addMeasurement(true, @as(f64, @floatFromInt(i + 1))); // 1 to 100 ms
    }

    const distribution = try stats.latencyDistribution(testing.allocator);
    defer distribution.deinit();

    // Should have 5 percentiles
    try testing.expectEqual(@as(usize, 5), distribution.items.len);

    // Verify approximate percentile values
    try testing.expectApproxEqAbs(@as(f64, 5.0), distribution.items[0], 2.0); // 5th percentile
    try testing.expectApproxEqAbs(@as(f64, 25.0), distribution.items[1], 2.0); // 25th percentile
    try testing.expectApproxEqAbs(@as(f64, 50.0), distribution.items[2], 2.0); // 50th percentile (median)
    try testing.expectApproxEqAbs(@as(f64, 75.0), distribution.items[3], 2.0); // 75th percentile
    try testing.expectApproxEqAbs(@as(f64, 95.0), distribution.items[4], 2.0); // 95th percentile
}
