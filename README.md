# bewirtung

CLI calculator for the deductible portions of a German _Bewirtungsbeleg_
(business meal receipt), with SKR04 booking lines.

For a meal receipt with 7% and 19% VAT items plus a tip, it produces:

- the net / VAT split per rate
- the 70 / 30 deductible and non-deductible split
- the SKR04 booking rows (6640, 6644)
- a cross-check when both tip and total are provided

All amounts are handled as integer cents internally; rounding is half-up.

## Build

Requires Zig `0.16.0`.

```sh
zig build      # produces zig-out/bin/bewirtung
zig build test # runs the unit tests
```

## Usage

You provide each VAT-bearing line as either gross or net, plus at least one
of `--tip` / `--total`. The other is derived so that
`gross7 + gross19 + tip == total`.

```sh
bewirtung --gross7 42.50 --gross19 23.80 --tip 5.00
bewirtung --net7   39.72 --net19   20.00 --total 71.30
bewirtung --gross7 42.50 --gross19 23.80 --tip 5.00 --total 71.30   # cross-checked
```

Run `bewirtung --help` for the full flag list.

## Example

```
$ bewirtung --net7 109.81 --gross19 40.7 --total 170
BEWIRTUNG - Deductible calc (SKR04)
================================================================================

Input
  7%  VAT (food)  net                              109.81 EUR
  19% VAT (bev.)  gross                             40.70 EUR
  Tip (computed)                                    11.80 EUR
  Gross total                                      170.00 EUR

Net / VAT breakdown
  7%  net                                          109.81 EUR
  7%  VAT                                            7.69 EUR
  19% net                                           34.20 EUR
  19% VAT                                            6.50 EUR
  Tip (no VAT)                                      11.80 EUR

70 / 30 split
  Meals 70% deductible (net+VAT)                   110.74 EUR
  Meals 30% non-deductible                          47.46 EUR
  Tip   70% deductible                               8.26 EUR
  Tip   30% non-deductible                           3.54 EUR

SKR04 bookings
  6640 Meals 70% ded. (7%  net)                     76.87 EUR
  6640 Meals 70% ded. (19% net)                     23.94 EUR
  6644 Meals 30% non-ded. (7%  net)                 32.94 EUR
  6644 Meals 30% non-ded. (19% net)                 10.26 EUR
  6640 Tip 70% ded. (no VAT)                         8.26 EUR
  6644 Tip 30% non-ded. (no VAT)                     3.54 EUR
  1571 Vorsteuer  7% (70% ded.)                      5.38 EUR
  1401 Vorsteuer 19% (70% ded.)                      4.55 EUR
```

## Notes

- The SKR04 account numbers and the 70 / 30 split reflect the German tax
  treatment of business meal expenses. Verify with your accountant before
  relying on the booking suggestions.
- This tool does not file or transmit anything; it only does the arithmetic
  and prints rows you can copy into your bookkeeping.
