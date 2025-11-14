const std = @import("std");
const http = std.http;
const NetworkStats = @import("network_stats.zig").NetworkStats;

pub const HttpLatencyTester = struct {
    allocator: std.mem.Allocator,
    test_count: u32 = 10, // Default number of latency tests
    timeout_ms: u32 = 2000, // Timeout per test in milliseconds

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Configure number of latency tests to perform
    pub fn setTestCount(self: *Self, count: u32) void {
        self.test_count = count;
    }

    /// Configure timeout per test in milliseconds
    pub fn setTimeout(self: *Self, timeout_ms: u32) void {
        self.timeout_ms = timeout_ms;
    }

    /// Measure latency to multiple URLs using HEAD requests
    /// Returns NetworkStats containing latency distribution, packet loss and jitter
    pub fn measureLatencyStats(self: *Self, urls: []const []const u8) !NetworkStats {
        if (urls.len == 0) return error.NoUrlsProvided;

        var stats = NetworkStats.init(self.allocator);
        errdefer stats.deinit();

        // Test each URL multiple times
        for (urls) |url| {
            for (0..self.test_count) |_| {
                const result = self.measureSingleUrl(url) catch {
                    try stats.addMeasurement(false, 0.0);
                    continue;
                };
                try stats.addMeasurement(true, result);
            }
        }

        return stats;
    }

    /// Legacy method - returns median latency for backward compatibility
    pub fn measureLatency(self: *Self, urls: []const []const u8) !?f64 {
        var stats = try self.measureLatencyStats(urls);
        defer stats.deinit();

        return stats.meanLatency();
    }

    /// Measure latency to a single URL using connection reuse method
    /// First request establishes HTTPS connection, second request measures pure RTT
    fn measureSingleUrl(self: *Self, url: []const u8) !f64 {
        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Parse URL
        const uri = try std.Uri.parse(url);

        // First request: Establish HTTPS connection (ignore timing)
        {
            const server_header_buffer = try self.allocator.alloc(u8, 4096);
            defer self.allocator.free(server_header_buffer);

            var req = try client.open(.HEAD, uri, .{
                .server_header_buffer = server_header_buffer,
            });
            defer req.deinit();

            try req.send();
            try req.finish();
            try req.wait();
        }

        // Second request: Reuse connection and measure pure HTTP RTT
        const start_time = std.time.nanoTimestamp();

        {
            const server_header_buffer = try self.allocator.alloc(u8, 4096);
            defer self.allocator.free(server_header_buffer);

            var req = try client.open(.HEAD, uri, .{
                .server_header_buffer = server_header_buffer,
            });
            defer req.deinit();

            try req.send();
            try req.finish();
            try req.wait();
        }

        const end_time = std.time.nanoTimestamp();

        // Check for timeout - if request took longer than timeout, consider it failed
        const latency_ns = end_time - start_time;
        const latency_ms = @as(f64, @floatFromInt(latency_ns)) / std.time.ns_per_ms;

        if (latency_ms > @as(f64, @floatFromInt(self.timeout_ms))) {
            return error.ConnectionTimeout;
        }

        return latency_ms;
    }

    /// Legacy method - kept for backward compatibility
    fn calculateMedian(self: *Self, latencies: []f64) f64 {
        _ = self;

        if (latencies.len == 0) return 0;
        if (latencies.len == 1) return latencies[0];

        // Sort latencies
        std.mem.sort(f64, latencies, {}, std.sort.asc(f64));

        const mid = latencies.len / 2;
        if (latencies.len % 2 == 0) {
            // Even number of elements - average of two middle values
            return (latencies[mid - 1] + latencies[mid]) / 2.0;
        } else {
            // Odd number of elements - middle value
            return latencies[mid];
        }
    }
};

const testing = std.testing;

test "HttpLatencyTester init/deinit" {
    var tester = HttpLatencyTester.init(testing.allocator);
    defer tester.deinit();

    // Test with empty URLs
    const result = try tester.measureLatency(&[_][]const u8{});
    try testing.expect(result == null);
}

test "calculateMedian" {
    var tester = HttpLatencyTester.init(testing.allocator);
    defer tester.deinit();

    // Test odd number of elements
    var latencies_odd = [_]f64{ 10.0, 20.0, 30.0 };
    const median_odd = tester.calculateMedian(&latencies_odd);
    try testing.expectEqual(@as(f64, 20.0), median_odd);

    // Test even number of elements
    var latencies_even = [_]f64{ 10.0, 20.0, 30.0, 40.0 };
    const median_even = tester.calculateMedian(&latencies_even);
    try testing.expectEqual(@as(f64, 25.0), median_even);

    // Test single element
    var latencies_single = [_]f64{15.0};
    const median_single = tester.calculateMedian(&latencies_single);
    try testing.expectEqual(@as(f64, 15.0), median_single);
}

test "HttpLatencyTester integration with example.com" {
    var tester = HttpLatencyTester.init(testing.allocator);
    defer tester.deinit();

    // Test with real HTTP endpoint
    const urls = [_][]const u8{"https://example.com"};
    const result = tester.measureLatency(&urls) catch |err| {
        // Allow network errors in CI environments
        std.log.warn("Network error in integration test (expected in CI): {}", .{err});
        return;
    };

    if (result) |latency_ms| {
        // Reasonable latency bounds (1ms to 5000ms)
        try testing.expect(latency_ms >= 1.0);
        try testing.expect(latency_ms <= 5000.0);
        std.log.info("example.com latency: {d:.1}ms", .{latency_ms});
    }
}
