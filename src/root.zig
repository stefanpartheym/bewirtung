const std = @import("std");
const Split = @import("Split.zig");
const Splits = @import("Splits.zig");
pub const Amounts = @import("Amounts.zig");
pub const conversion = @import("conversion.zig");

pub const ParseError = error{BadNumber};

/// Parse decimal EUR string into integer cents.
/// Accepts: "12", "12.5", "12.50", "0.07", "+5", "-1.23".
/// Rejects: empty, >2 fractional digits, non-digit chars, lone "." / "-".
pub fn parseCents(s: []const u8) ParseError!i64 {
    if (s.len == 0) return error.BadNumber;
    var i: usize = 0;
    var neg = false;
    if (s[0] == '-') {
        neg = true;
        i = 1;
    } else if (s[0] == '+') {
        i = 1;
    }

    var int_part: i64 = 0;
    var saw_digit = false;
    while (i < s.len and s[i] != '.') : (i += 1) {
        const c = s[i];
        if (c < '0' or c > '9') return error.BadNumber;
        int_part = int_part * 10 + @as(i64, c - '0');
        saw_digit = true;
    }

    var frac: i64 = 0;
    var frac_n: usize = 0;
    if (i < s.len and s[i] == '.') {
        i += 1;
        while (i < s.len) : (i += 1) {
            const c = s[i];
            if (c < '0' or c > '9') return error.BadNumber;
            if (frac_n >= 2) return error.BadNumber;
            frac = frac * 10 + @as(i64, c - '0');
            frac_n += 1;
            saw_digit = true;
        }
    }
    if (!saw_digit) return error.BadNumber;
    while (frac_n < 2) : (frac_n += 1) frac *= 10;

    var cents = int_part * 100 + frac;
    if (neg) cents = -cents;
    return cents;
}

/// 70/30 split with half-up rounding on the 70% part.
/// `ded + non == amount` always (non is derived by subtraction).
pub fn split7030(amount: i64) Split {
    const ded = @divTrunc(amount * 70 + 50, 100);
    return .{ .ded = ded, .non = amount - ded };
}

/// Perform 70/30 split for all amounts.
pub fn splitAmounts(amounts: Amounts) Splits {
    return .{
        // 70/30 splits on gross (for headline numbers)
        .meals = split7030(amounts.g7 + amounts.g19),
        .tip = split7030(amounts.tip),
        // Per-rate splits for SKR04 rows (on net and on VAT)
        .net7 = split7030(amounts.n7),
        .net19 = split7030(amounts.n19),
        .vat7 = split7030(amounts.v7), // 1571 Vorsteuer 7%  uses .ded
        .vat19 = split7030(amounts.v19), // 1401 Vorsteuer 19% uses .ded
    };
}

/// Format cents as "D.CC" (always 2 decimals) into `buf`.
pub fn fmtEur(buf: []u8, cent_amount: i64) ![]u8 {
    const neg = cent_amount < 0;
    const abs: i64 = if (neg) -cent_amount else cent_amount;
    const euros = @divTrunc(abs, 100);
    const cents: u8 = @intCast(@mod(abs, 100));
    const high: u8 = '0' + (cents / 10);
    const low: u8 = '0' + (cents % 10);
    return if (neg)
        std.fmt.bufPrint(buf, "-{d}.{c}{c}", .{ euros, high, low })
    else
        std.fmt.bufPrint(buf, "{d}.{c}{c}", .{ euros, high, low });
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const testing = std.testing;

test "parseCents accepts common forms" {
    try testing.expectEqual(@as(i64, 1250), try parseCents("12.50"));
    try testing.expectEqual(@as(i64, 1250), try parseCents("12.5"));
    try testing.expectEqual(@as(i64, 1200), try parseCents("12"));
    try testing.expectEqual(@as(i64, 0), try parseCents("0"));
    try testing.expectEqual(@as(i64, 0), try parseCents("0.00"));
    try testing.expectEqual(@as(i64, 7), try parseCents("0.07"));
    try testing.expectEqual(@as(i64, 500), try parseCents("+5"));
    try testing.expectEqual(@as(i64, -123), try parseCents("-1.23"));
    try testing.expectEqual(@as(i64, 100000), try parseCents("1000"));
}

test "parseCents rejects garbage" {
    try testing.expectError(error.BadNumber, parseCents(""));
    try testing.expectError(error.BadNumber, parseCents("abc"));
    try testing.expectError(error.BadNumber, parseCents("12.345"));
    try testing.expectError(error.BadNumber, parseCents("12.a"));
    try testing.expectError(error.BadNumber, parseCents("."));
    try testing.expectError(error.BadNumber, parseCents("-"));
    try testing.expectError(error.BadNumber, parseCents("1,50"));
    try testing.expectError(error.BadNumber, parseCents(" 12"));
}

test "split7030 sum preserved" {
    const cases = [_]i64{ 0, 1, 2, 3, 100, 333, 1000, 12345, 99999, 1 };
    for (cases) |c| {
        const s = split7030(c);
        try testing.expectEqual(c, s.ded + s.non);
    }
}

test "split7030 round values" {
    {
        const s = split7030(10000); // 100.00 -> 70.00 / 30.00
        try testing.expectEqual(@as(i64, 7000), s.ded);
        try testing.expectEqual(@as(i64, 3000), s.non);
    }
    {
        const s = split7030(100); // 1.00 -> 0.70 / 0.30
        try testing.expectEqual(@as(i64, 70), s.ded);
        try testing.expectEqual(@as(i64, 30), s.non);
    }
    {
        // 333 * 70 = 23310; +50 = 23360; /100 = 233
        const s = split7030(333);
        try testing.expectEqual(@as(i64, 233), s.ded);
        try testing.expectEqual(@as(i64, 100), s.non);
    }
}

test "fmtEur formats" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("12.50", try fmtEur(&buf, 1250));
    try testing.expectEqualStrings("0.07", try fmtEur(&buf, 7));
    try testing.expectEqualStrings("0.00", try fmtEur(&buf, 0));
    try testing.expectEqualStrings("-1.23", try fmtEur(&buf, -123));
    try testing.expectEqualStrings("1000.00", try fmtEur(&buf, 100000));
    try testing.expectEqualStrings("9.09", try fmtEur(&buf, 909));
}

test "e2e scenario" {
    const g7: i64 = 4250;
    const g19: i64 = 2380;
    const gt: i64 = 500;

    const n7 = conversion.netFromGross(g7, 7);
    const n19 = conversion.netFromGross(g19, 19);
    const v7 = g7 - n7;
    const v19 = g19 - n19;

    try testing.expectEqual(@as(i64, 3972), n7);
    try testing.expectEqual(@as(i64, 278), v7);
    try testing.expectEqual(@as(i64, 2000), n19);
    try testing.expectEqual(@as(i64, 380), v19);

    const gross_total = g7 + g19 + gt;
    try testing.expectEqual(@as(i64, 7130), gross_total);

    const meals = split7030(g7 + g19);
    const tip = split7030(gt);
    try testing.expectEqual(g7 + g19, meals.ded + meals.non);
    try testing.expectEqual(gt, tip.ded + tip.non);

    const v7_70 = split7030(v7);
    const v19_70 = split7030(v19);
    try testing.expectEqual(v7, v7_70.ded + v7_70.non);
    try testing.expectEqual(v19, v19_70.ded + v19_70.non);
}
