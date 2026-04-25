const std = @import("std");
const Io = std.Io;
const bew = @import("bewirtung");

const Amounts = struct {
    const Input = struct {
        net7: ?i64,
        gross7: ?i64,
        net19: ?i64,
        gross19: ?i64,
        tip: ?i64,
        total: ?i64,
    };

    const InputFlags = struct {
        n7: bool = false,
        g7: bool = false,
        n19: bool = false,
        g19: bool = false,
        tip: bool = false,
        total: bool = false,
    };

    const Errors = error{
        CannotProvideBoth7,
        CannotProvideBoth19,
        MissingAmount7,
        MissingAmount19,
        MissingTip,
        NegativeAmounts,
    };

    const Self = @This();

    /// Tracks which amounts were provided as inputs.
    input: InputFlags = .{},

    /// Net amount (7% VAT)
    n7: i64 = 0,
    /// Net amount (19% VAT)
    n19: i64 = 0,

    /// Gross amount (7% VAT)
    g7: i64 = 0,
    /// Gross amount (19% VAT)
    g19: i64 = 0,

    /// VAT amount (7% VAT)
    v7: i64 = 0,
    /// Gross amount (19% VAT)
    v19: i64 = 0,

    /// Tip amount (no VAT)
    tip: i64 = 0,

    /// total amount (gross)
    total: i64 = 0,

    pub fn new(input: Input) Errors!Self {
        var result: Self = .{};

        // Handle 7% VAT inputs.
        if (input.net7 != null and input.gross7 != null) {
            return Errors.CannotProvideBoth7;
        } else if (input.net7) |n7| {
            result.input.n7 = true;
            result.n7 = n7;
            result.g7 = bew.grossFromNet(n7, 7);
        } else if (input.gross7) |g7| {
            result.input.g7 = true;
            result.n7 = bew.netFromGross(g7, 7);
            result.g7 = g7;
        } else {
            return Errors.MissingAmount7;
        }

        // Handle 19% VAT inputs.
        if (input.net19 != null and input.gross19 != null) {
            return Errors.CannotProvideBoth19;
        } else if (input.net19) |n19| {
            result.input.n19 = true;
            result.n19 = n19;
            result.g19 = bew.grossFromNet(n19, 19);
        } else if (input.gross19) |g19| {
            result.input.g19 = true;
            result.n19 = bew.netFromGross(g19, 19);
            result.g19 = g19;
        } else {
            return Errors.MissingAmount19;
        }

        // Handle tip input.
        result.tip = input.tip orelse return Errors.MissingTip;

        // Handle total amount input.
        if (input.total) |total| {
            result.input.total = true;
            result.total = total;
        } else {
            result.total = result.g7 + result.g19 + result.tip;
        }

        if (result.g7 < 0 or result.g19 < 0 or result.tip < 0) {
            return Errors.NegativeAmounts;
        }

        result.v7 = result.g7 - result.n7;
        result.v19 = result.g19 - result.n19;

        return result;
    }
};

const usage =
    \\bewirtung - Deductible calc for German Bewirtungsbeleg (SKR04)
    \\
    \\Input amounts for 7% and 19% VAT can be provided as gross or net amounts.
    \\Amounts in EUR with up to 2 decimals (e.g. 42.17).
    \\
    \\Usage:
    \\  bewirtung --gross7 <EUR> --gross19 <EUR> --tip <EUR> [--total <EUR>]
    \\  bewirtung --net7 <EUR> --net19 <EUR> --tip <EUR> [--total <EUR>]
    \\
    \\Flags:
    \\  --gross7    Gross amount taxed at 7%  VAT (food)
    \\  --gross19   Gross amount taxed at 19% VAT (beverages/other)
    \\  --net7      Net amount taxed at 7%  VAT (food)
    \\  --net19     Net amount taxed at 19% VAT (beverages/other)
    \\  --tip       Tip amount (no VAT)
    \\  --total     Optional gross total for cross-validation
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

    const amounts = Amounts.new(.{
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
        error.MissingTip => dieUsage(stderr, "missing --tip", .{}),
        error.NegativeAmounts => dieUsage(stderr, "amounts must be non-negative", .{}),
    };

    // 70/30 splits on gross (for headline numbers)
    const meals_split = bew.split7030(amounts.g7 + amounts.g19);
    const tip_split = bew.split7030(amounts.tip);

    // Per-rate splits for SKR04 rows (on net and on VAT)
    const n7_split = bew.split7030(amounts.n7);
    const n19_split = bew.split7030(amounts.n19);
    const v7_split = bew.split7030(amounts.v7); // 1571 Vorsteuer 7%  uses .ded
    const v19_split = bew.split7030(amounts.v19); // 1401 Vorsteuer 19% uses .ded

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
    try printRow(stdout, "Tip", amounts.tip);
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
        try printRow(stdout, "Computed gross", amounts.total);
        if (t == amounts.total) {
            try stdout.writeAll("  Result: OK\n");
        } else {
            var bd: [32]u8 = undefined;
            const diff = try bew.fmtEur(&bd, amounts.total - t);
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
