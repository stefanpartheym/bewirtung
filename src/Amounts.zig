const conversion = @import("conversion.zig");

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
    MissingTipOrTotal,
    NegativeAmounts,
};

const Self = @This();

/// Tracks which amounts were provided as inputs.
input: InputFlags = .{},

/// Net amount (7% VAT)
n7: i64,
/// Net amount (19% VAT)
n19: i64,

/// Gross amount (7% VAT)
g7: i64,
/// Gross amount (19% VAT)
g19: i64,

/// VAT amount (7% VAT)
v7: i64,
/// Gross amount (19% VAT)
v19: i64,

/// Tip amount (no VAT)
tip: i64,

/// total amount (gross)
total: i64,

pub fn new(input: Input) Errors!Self {
    var result: Self = .{
        .input = .{},
        .n7 = undefined,
        .n19 = undefined,
        .g7 = undefined,
        .g19 = undefined,
        .v7 = undefined,
        .v19 = undefined,
        .tip = undefined,
        .total = undefined,
    };

    // Handle 7% VAT inputs.
    if (input.net7 != null and input.gross7 != null) {
        return Errors.CannotProvideBoth7;
    } else if (input.net7) |n7| {
        result.input.n7 = true;
        result.n7 = n7;
        result.g7 = conversion.grossFromNet(n7, 7);
    } else if (input.gross7) |g7| {
        result.input.g7 = true;
        result.n7 = conversion.netFromGross(g7, 7);
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
        result.g19 = conversion.grossFromNet(n19, 19);
    } else if (input.gross19) |g19| {
        result.input.g19 = true;
        result.n19 = conversion.netFromGross(g19, 19);
        result.g19 = g19;
    } else {
        return Errors.MissingAmount19;
    }

    // Handle tip / total inputs. At least one must be provided;
    // the missing one is derived so that g7 + g19 + tip == total.
    result.input.tip = input.tip != null;
    result.input.total = input.total != null;
    if (!result.input.tip and !result.input.total) {
        return Errors.MissingTipOrTotal;
    }

    if (input.tip) |t| result.tip = t;
    if (input.total) |tot| result.total = tot;

    if (!result.input.tip) {
        result.tip = result.total - result.g7 - result.g19;
    } else if (!result.input.total) {
        result.total = result.g7 + result.g19 + result.tip;
    }

    if (result.g7 < 0 or result.g19 < 0 or result.tip < 0) {
        return Errors.NegativeAmounts;
    }

    result.v7 = result.g7 - result.n7;
    result.v19 = result.g19 - result.n19;

    return result;
}
