; Checks that the header's seedling is whole: a stem down to the title's
; baseline, and a leaf on each side of it. SynSeeder 1.0.0 drew it on
; Windows without its stem, and nothing looked.

class SeedlingCheck {
    ; What's wrong with the seedling on the header picture ``canvas``: [] if nothing.
    static Problems(canvas) {
        s := Look.scale, u := Look.MARK_UNIT * s, top := Look.MARK_Y * s
        if Floor(top + 54 * u) >= canvas.h  ; rows past the bottom would be read outside the picture
            return ["the picture is too small for the header at " Round(s * 100) "% scaling"]
        problems := []
        ; Only the stem crosses these rows: below the leaves, above its foot
        ; at 56 units in the seedling's 64-unit box.
        bare := []
        y := Ceil(top + 36 * u)
        while y <= Floor(top + 54 * u) {
            if !SeedlingCheck.Green(canvas, y, y)
                bare.Push(y)
            y++
        }
        if bare.Length
            problems.Push("the seedling has no stem on " bare.Length " rows, y " bare[1] " to " bare[bare.Length])
        ; The leaves, from their tips at 11 units to where they meet the stem:
        ; one on each side of the stem, or both together if there's no stem.
        y0 := Ceil(top + 12 * u), y1 := Floor(top + 30 * u)
        x := SeedlingCheck.StemX(canvas)
        if x = "" {
            leaves := SeedlingCheck.Green(canvas, y0, y1)
            if leaves < 40 * s * s
                problems.Push("the seedling's leaves have only " leaves " green pixels")
        } else {
            for side in [["left", 0, Floor(x - 2 * u)], ["right", Ceil(x + 2 * u), canvas.w // 2]] {
                leaf := SeedlingCheck.Green(canvas, y0, y1, side[2], side[3])
                if leaf < 20 * s * s
                    problems.Push("the seedling's " side[1] " leaf has only " leaf " green pixels")
            }
        }
        return problems
    }

    ; Where the middle of the stem is across the picture, from its rows 40 to
    ; 50 units down the seedling's box, or "" if there's no stem there.
    static StemX(canvas) {
        s := Look.scale, u := Look.MARK_UNIT * s, top := Look.MARK_Y * s
        y0 := Ceil(top + 40 * u), sum := 0, count := 0
        loop Floor(top + 50 * u) - y0 + 1 {
            y := y0 + A_Index - 1
            loop canvas.w // 2 {
                if SeedlingCheck.IsGreen(canvas.Pixel(A_Index - 1, y))
                    sum += A_Index - 0.5, count += 1
            }
        }
        return count ? sum / count : ""
    }

    ; How many pixels in rows ``y0`` to ``y1``, from column ``x0`` up to
    ; ``x1`` (the left half of ``canvas`` unless given), are the seedling's green.
    static Green(canvas, y0, y1, x0 := 0, x1 := "") {
        x1 := x1 = "" ? canvas.w // 2 : Min(x1, canvas.w), count := 0
        loop y1 - y0 + 1 {
            y := y0 + A_Index - 1
            loop x1 - x0
                count += SeedlingCheck.IsGreen(canvas.Pixel(x0 + A_Index - 1, y))
        }
        return count
    }

    ; The seedling's green, or nearly: its smoothed edges count from about 80% cover.
    static IsGreen(c) {
        g := Look.SPROUT_GREEN
        return Abs((c >> 16) - (g >> 16)) + Abs((c >> 8 & 0xFF) - (g >> 8 & 0xFF)) + Abs((c & 0xFF) - (g & 0xFF)) <= 60
    }
}
