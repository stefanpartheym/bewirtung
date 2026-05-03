/// Net cents derived from gross cents at whole-percent VAT rate.
/// Uses half-up rounding for non-negative values. VAT = gross - net.
pub fn netFromGross(gross: i64, rate_pct: i64) i64 {
    const div: i64 = 100 + rate_pct;
    const num = gross * 100;
    return @divTrunc(num + @divTrunc(div, 2), div);
}

/// Gross cents derived from net cents at whole-percent VAT rate.
/// Uses half-up rounding for non-negative values.
pub fn grossFromNet(net: i64, rate_pct: i64) i64 {
    const mul: i64 = 100 + rate_pct;
    return @divTrunc(net * mul + 50, 100);
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const testing = @import("std").testing;

test "netFromGross exact 19%" {
    // 119.00 gross -> 100.00 net, 19.00 VAT
    try testing.expectEqual(@as(i64, 10000), netFromGross(11900, 19));
    try testing.expectEqual(@as(i64, 11900) - @as(i64, 10000), @as(i64, 1900));
}

test "netFromGross exact 7%" {
    // 107.00 gross -> 100.00 net
    try testing.expectEqual(@as(i64, 10000), netFromGross(10700, 7));
}

test "netFromGross rounds half up" {
    // 23.80 at 19% -> 23.80 / 1.19 = 20.0000 -> 2000
    try testing.expectEqual(@as(i64, 2000), netFromGross(2380, 19));
    // 42.50 at 7%  -> 42.50 / 1.07 = 39.7196... -> 3972 cents
    try testing.expectEqual(@as(i64, 3972), netFromGross(4250, 7));
}

test "netFromGross zero" {
    try testing.expectEqual(@as(i64, 0), netFromGross(0, 7));
    try testing.expectEqual(@as(i64, 0), netFromGross(0, 19));
}

test "grossFromNet exact" {
    // 100.00 net -> 107.00 / 119.00 gross
    try testing.expectEqual(@as(i64, 10700), grossFromNet(10000, 7));
    try testing.expectEqual(@as(i64, 11900), grossFromNet(10000, 19));
}

test "grossFromNet rounds half up" {
    // 109.81 @ 7%  -> 109.81 * 1.07 = 117.4967 -> 11750 cents (117.50)
    try testing.expectEqual(@as(i64, 11750), grossFromNet(10981, 7));
    // 34.20  @ 19% -> 34.20 * 1.19 = 40.698  -> 4070 cents (40.70)
    try testing.expectEqual(@as(i64, 4070), grossFromNet(3420, 19));
}

test "grossFromNet zero" {
    try testing.expectEqual(@as(i64, 0), grossFromNet(0, 7));
    try testing.expectEqual(@as(i64, 0), grossFromNet(0, 19));
}

test "grossFromNet / netFromGross round-trip on exact cases" {
    // Cases where net*mul is exactly divisible by 100 — round-trip is exact.
    const cases = [_]struct { net: i64, rate: i64 }{
        .{ .net = 10000, .rate = 7 },
        .{ .net = 10000, .rate = 19 },
        .{ .net = 2000, .rate = 19 },
    };
    for (cases) |c| {
        const g = grossFromNet(c.net, c.rate);
        try testing.expectEqual(c.net, netFromGross(g, c.rate));
    }
}
