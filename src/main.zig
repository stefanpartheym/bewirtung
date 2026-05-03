const std = @import("std");
const Io = std.Io;
const bew = @import("bewirtung");

const usage =
    \\bewirtung - Deductible calc for German Bewirtungsbeleg (SKR04)
    \\
    \\Input amounts for 7% and 19% VAT can be provided as gross or net amounts.
    \\At least one of --tip or --total must be provided; the other is derived.
    \\Amounts in EUR with up to 2 decimals (e.g. 42.17).
    \\
    \\Usage:
    \\  bewirtung --gross7 <EUR> --gross19 <EUR> --tip <EUR>   [--total <EUR>]
    \\  bewirtung --gross7 <EUR> --gross19 <EUR> --total <EUR> [--tip <EUR>]
    \\  (--net7 / --net19 may be substituted for the gross variants)
    \\
    \\Flags:
    \\  --gross7    Gross amount taxed at 7%  VAT (food)
    \\  --gross19   Gross amount taxed at 19% VAT (beverages/other)
    \\  --net7      Net amount taxed at 7%  VAT (food)
    \\  --net19     Net amount taxed at 19% VAT (beverages/other)
    \\  --tip       Tip amount (no VAT) — derived from --total if omitted
    \\  --total     Gross total — derived from gross7+gross19+tip if omitted
    \\              When both --tip and --total are given, they are cross-checked.
    \\  -h, --help  Show this help
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

    var gross7: ?i64 = null;
    var gross19: ?i64 = null;
    var net7: ?i64 = null;
    var net19: ?i64 = null;
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
        if (std.mem.eql(u8, flag, "--gross7")) {
            gross7 = cents;
        } else if (std.mem.eql(u8, flag, "--gross19")) {
            gross19 = cents;
        } else if (std.mem.eql(u8, flag, "--net7")) {
            net7 = cents;
        } else if (std.mem.eql(u8, flag, "--net19")) {
            net19 = cents;
        } else if (std.mem.eql(u8, flag, "--tip")) {
            tip = cents;
        } else if (std.mem.eql(u8, flag, "--total")) {
            total = cents;
        } else {
            dieUsage(stderr, "unknown flag '{s}'", .{flag});
        }
    }

    const amounts = bew.Amounts.new(.{
        .net7 = net7,
        .net19 = net19,
        .gross7 = gross7,
        .gross19 = gross19,
        .tip = tip,
        .total = total,
    }) catch |err| switch (err) {
        error.CannotProvideBoth7 => dieUsage(stderr, "cannot provide both --net7 and --gross7", .{}),
        error.CannotProvideBoth19 => dieUsage(stderr, "cannot provide both --net19 and --gross19", .{}),
        error.MissingAmount7 => dieUsage(stderr, "missing --net7 or --gross7", .{}),
        error.MissingAmount19 => dieUsage(stderr, "missing --net19 or --gross19", .{}),
        error.MissingTipOrTotal => dieUsage(stderr, "provide at least one of --tip or --total", .{}),
        error.NegativeAmounts => dieUsage(stderr, "amounts must be non-negative (check that --total >= gross7 + gross19)", .{}),
    };

    const splits = bew.splitAmounts(amounts);

    try stdout.writeAll("BEWIRTUNG - Deductible calc (SKR04)\n");
    try stdout.writeAll("=" ** 80 ++ "\n\n");

    try stdout.writeAll("Input\n");
    if (amounts.input.n7) {
        try printRow(stdout, "7%  VAT (food)  net", amounts.n7);
    } else {
        try printRow(stdout, "7%  VAT (food)  gross", amounts.g7);
    }
    if (amounts.input.n19) {
        try printRow(stdout, "19% VAT (bev.)  net", amounts.n19);
    } else {
        try printRow(stdout, "19% VAT (bev.)  gross", amounts.g19);
    }
    if (amounts.input.tip) {
        try printRow(stdout, "Tip", amounts.tip);
    } else {
        try printRow(stdout, "Tip (computed)", amounts.tip);
    }
    if (amounts.input.total) {
        try printRow(stdout, "Gross total", amounts.total);
    } else {
        try printRow(stdout, "Gross total (computed)", amounts.total);
    }

    try stdout.writeAll("\nNet / VAT breakdown\n");
    try printRow(stdout, "7%  net", amounts.n7);
    try printRow(stdout, "7%  VAT", amounts.v7);
    try printRow(stdout, "19% net", amounts.n19);
    try printRow(stdout, "19% VAT", amounts.v19);
    try printRow(stdout, "Tip (no VAT)", amounts.tip);

    try stdout.writeAll("\n70 / 30 split\n");
    try printRow(stdout, "Meals 70% deductible (net+VAT)", splits.meals.ded);
    try printRow(stdout, "Meals 30% non-deductible", splits.meals.non);
    try printRow(stdout, "Tip   70% deductible", splits.tip.ded);
    try printRow(stdout, "Tip   30% non-deductible", splits.tip.non);

    try stdout.writeAll("\nSKR04 bookings (classic, 8 rows: explicit Vorsteuer)\n");
    try printRow(stdout, "6640 Meals 70% ded. (7%  net)", splits.net7.ded);
    try printRow(stdout, "6640 Meals 70% ded. (19% net)", splits.net19.ded);
    try printRow(stdout, "6644 Meals 30% non-ded. (7%  net+VAT)", splits.net7.non);
    try printRow(stdout, "6644 Meals 30% non-ded. (19% net+VAT)", splits.net19.non);
    try printRow(stdout, "6640 Tip 70% ded. (no VAT)", splits.tip.ded);
    try printRow(stdout, "6644 Tip 30% non-ded. (no VAT)", splits.tip.non);
    try printRow(stdout, "1571 Vorsteuer  7% (70% ded.)", splits.vat7.ded);
    try printRow(stdout, "1401 Vorsteuer 19% (70% ded.)", splits.vat19.ded);

    try stdout.writeAll("\nSKR04 bookings (Lexware, 6 rows: account auto-extracts Vorsteuer)\n");
    try printRow(stdout, "6640 Meals 70% ded. (7%  gross)", splits.gross7.ded);
    try printRow(stdout, "6640 Meals 70% ded. (19% gross)", splits.gross19.ded);
    try printRow(stdout, "6644 Meals 30% non-ded. (7%)", splits.gross7.non);
    try printRow(stdout, "6644 Meals 30% non-ded. (19%)", splits.gross19.non);
    try printRow(stdout, "6640 Tip 70% ded. (no VAT)", splits.tip.ded);
    try printRow(stdout, "6644 Tip 30% non-ded. (no VAT)", splits.tip.non);

    // Only meaningful when BOTH tip and total were provided; otherwise
    // the missing one was derived from the other and equality is trivial.
    if (amounts.input.tip and amounts.input.total) {
        const computed = amounts.g7 + amounts.g19 + amounts.tip;
        try stdout.writeAll("\nCross-check\n");
        try printRow(stdout, "Provided total", amounts.total);
        try printRow(stdout, "Computed gross (g7+g19+tip)", computed);
        if (computed == amounts.total) {
            try stdout.writeAll("  Result: OK\n");
        } else {
            var bd: [32]u8 = undefined;
            const diff = try bew.fmtEur(&bd, computed - amounts.total);
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
