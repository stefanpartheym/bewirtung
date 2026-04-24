const std = @import("std");
const Io = std.Io;
const bew = @import("bewirtung");

const usage =
    \\bewirtung - Deductible calc for German Bewirtungsbeleg (SKR04)
    \\
    \\Usage:
    \\  bewirtung --vat7 <EUR> --vat19 <EUR> --tip <EUR> [--total <EUR>]
    \\
    \\Flags:
    \\  --vat7   Gross amount taxed at 7%  VAT (food)
    \\  --vat19  Gross amount taxed at 19% VAT (beverages/other)
    \\  --tip    Tip amount (no VAT)
    \\  --total  Optional gross total for cross-validation
    \\  -h, --help  Show this help
    \\
    \\Amounts in EUR with up to 2 decimals (e.g. 42.17).
    \\
;

fn dieUsage(w: *Io.Writer, comptime fmt: []const u8, args: anytype) noreturn {
    w.print("error: " ++ fmt ++ "\n\n", args) catch {};
    w.writeAll(usage) catch {};
    w.flush() catch {};
    std.process.exit(2);
}

const spaces: [64]u8 = [_]u8{' '} ** 64;

fn writePad(w: *Io.Writer, n: usize) !void {
    var remaining = n;
    while (remaining > 0) {
        const take = @min(remaining, spaces.len);
        try w.writeAll(spaces[0..take]);
        remaining -= take;
    }
}

fn printRow(w: *Io.Writer, label: []const u8, cents: i64) !void {
    var buf: [32]u8 = undefined;
    const s = try bew.fmtEur(&buf, cents);
    const label_w: usize = 42;
    const amount_w: usize = 12;
    try w.writeAll("  ");
    try w.writeAll(label);
    if (label.len < label_w) try writePad(w, label_w - label.len);
    try w.writeAll(" ");
    if (s.len < amount_w) try writePad(w, amount_w - s.len);
    try w.writeAll(s);
    try w.writeAll(" EUR\n");
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;
    defer stdout.flush() catch {};

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;
    defer stderr.flush() catch {};

    var vat7: ?i64 = null;
    var vat19: ?i64 = null;
    var tip: ?i64 = null;
    var total: ?i64 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            try stdout.writeAll(usage);
            return;
        }
        const flag = a;
        if (i + 1 >= args.len) dieUsage(stderr, "flag '{s}' needs a value", .{flag});
        const val = args[i + 1];
        i += 1;
        const cents = bew.parseCents(val) catch dieUsage(
            stderr,
            "bad number for {s}: '{s}'",
            .{ flag, val },
        );
        if (std.mem.eql(u8, flag, "--vat7")) {
            vat7 = cents;
        } else if (std.mem.eql(u8, flag, "--vat19")) {
            vat19 = cents;
        } else if (std.mem.eql(u8, flag, "--tip")) {
            tip = cents;
        } else if (std.mem.eql(u8, flag, "--total")) {
            total = cents;
        } else {
            dieUsage(stderr, "unknown flag '{s}'", .{flag});
        }
    }

    const g7 = vat7 orelse dieUsage(stderr, "missing --vat7", .{});
    const g19 = vat19 orelse dieUsage(stderr, "missing --vat19", .{});
    const gt = tip orelse dieUsage(stderr, "missing --tip", .{});

    if (g7 < 0 or g19 < 0 or gt < 0) dieUsage(stderr, "amounts must be non-negative", .{});

    // Net / VAT per rate
    const n7 = bew.netFromGross(g7, 7);
    const v7 = g7 - n7;
    const n19 = bew.netFromGross(g19, 19);
    const v19 = g19 - n19;

    const gross_total = g7 + g19 + gt;

    // 70/30 splits on gross (for headline numbers)
    const meals_split = bew.split7030(g7 + g19);
    const tip_split = bew.split7030(gt);

    // Per-rate splits for SKR04 rows (on net and on VAT)
    const n7_split = bew.split7030(n7);
    const n19_split = bew.split7030(n19);
    const v7_split = bew.split7030(v7); // 1571 Vorsteuer 7%  uses .ded
    const v19_split = bew.split7030(v19); // 1401 Vorsteuer 19% uses .ded

    try stdout.writeAll("BEWIRTUNG - Deductible calc (SKR04)\n");
    try stdout.writeAll("=" ** 80 ++ "\n\n");

    try stdout.writeAll("Gross input\n");
    try printRow(stdout, "7%  VAT (food)  gross", g7);
    try printRow(stdout, "19% VAT (bev.)  gross", g19);
    try printRow(stdout, "Tip             gross", gt);
    try printRow(stdout, "Gross total", gross_total);

    try stdout.writeAll("\nNet / VAT breakdown\n");
    try printRow(stdout, "7%  net", n7);
    try printRow(stdout, "7%  VAT", v7);
    try printRow(stdout, "19% net", n19);
    try printRow(stdout, "19% VAT", v19);
    try printRow(stdout, "Tip (no VAT)", gt);

    try stdout.writeAll("\n70 / 30 split\n");
    try printRow(stdout, "Meals 70% deductible (net+VAT)", meals_split.ded);
    try printRow(stdout, "Meals 30% non-deductible", meals_split.non);
    try printRow(stdout, "Tip   70% deductible", tip_split.ded);
    try printRow(stdout, "Tip   30% non-deductible", tip_split.non);

    try stdout.writeAll("\nSKR04 bookings\n");
    try printRow(stdout, "6640 Meals 70% ded. (7%  net)", n7_split.ded);
    try printRow(stdout, "6640 Meals 70% ded. (19% net)", n19_split.ded);
    try printRow(stdout, "6644 Meals 30% non-ded. (7%  net)", n7_split.non);
    try printRow(stdout, "6644 Meals 30% non-ded. (19% net)", n19_split.non);
    try printRow(stdout, "6640 Tip 70% ded. (no VAT)", tip_split.ded);
    try printRow(stdout, "6644 Tip 30% non-ded. (no VAT)", tip_split.non);
    try printRow(stdout, "1571 Vorsteuer  7% (70% ded.)", v7_split.ded);
    try printRow(stdout, "1401 Vorsteuer 19% (70% ded.)", v19_split.ded);

    if (total) |t| {
        try stdout.writeAll("\nCross-check\n");
        try printRow(stdout, "Provided total", t);
        try printRow(stdout, "Computed gross", gross_total);
        if (t == gross_total) {
            try stdout.writeAll("  Result: OK\n");
        } else {
            var bd: [32]u8 = undefined;
            const diff = try bew.fmtEur(&bd, gross_total - t);
            try stdout.print("  WARNING: MISMATCH (computed - total = {s} EUR)\n", .{diff});
        }
    }
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const testing = std.testing;

test "module wiring: parseCents reachable" {
    try testing.expectEqual(@as(i64, 4217), try bew.parseCents("42.17"));
}

test "scenario 42.50 / 23.80 / 5.00 totals" {
    const g7 = try bew.parseCents("42.50");
    const g19 = try bew.parseCents("23.80");
    const gt = try bew.parseCents("5.00");
    try testing.expectEqual(@as(i64, 7130), g7 + g19 + gt);

    const meals = bew.split7030(g7 + g19);
    try testing.expectEqual(g7 + g19, meals.ded + meals.non);

    const tip = bew.split7030(gt);
    try testing.expectEqual(gt, tip.ded + tip.non);
    try testing.expectEqual(@as(i64, 350), tip.ded);
    try testing.expectEqual(@as(i64, 150), tip.non);
}

test "cross-check mismatch detects" {
    const g7: i64 = 4250;
    const g19: i64 = 2380;
    const gt: i64 = 500;
    const gross_total = g7 + g19 + gt;
    const claimed: i64 = 7100;
    try testing.expect(gross_total != claimed);
    try testing.expectEqual(@as(i64, 30), gross_total - claimed);
}
