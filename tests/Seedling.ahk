; Checks that the header's seedling is whole: two leaves, and a stem down to
; the title's baseline. SynSeeder 1.0.0 drew it on Windows without its stem,
; and nothing looked.

class SeedlingCheck {
    ; What's wrong with the seedling on the header picture ``canvas``: [] if nothing.
    static Problems(canvas) {
        s := Look.scale, u := Look.MARK_UNIT * s, top := Look.MARK_Y * s
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
        ; The leaves, from their tips at 11 units to where they meet the stem.
        leaves := SeedlingCheck.Green(canvas, Ceil(top + 12 * u), Floor(top + 30 * u))
        if leaves < 40 * s * s
            problems.Push("the seedling's leaves have only " leaves " green pixels")
        return problems
    }

    ; How many pixels in rows ``y0`` to ``y1`` of the left half of ``canvas``
    ; are the seedling's green, or nearly (its smoothed edges are less).
    static Green(canvas, y0, y1) {
        g := Look.SPROUT_GREEN, count := 0
        loop y1 - y0 + 1 {
            y := y0 + A_Index - 1
            loop canvas.w // 2 {
                c := canvas.Pixel(A_Index - 1, y)
                count += Abs((c >> 16) - (g >> 16)) + Abs((c >> 8 & 0xFF) - (g >> 8 & 0xFF)) + Abs((c & 0xFF) - (g & 0xFF)) <= 60
            }
        }
        return count
    }
}
