; Finding the game's buttons on screen.
;
; The button images (templates/*.png) are crops of the game's UI from 2560x1440
; screenshots, or from the screen height in their name (server_row.1080p.png):
; the game draws small text a little differently at each height, so some
; buttons carry a crop from several. A name with another word in it
; (roles_confirm.title.png) is a crop of a different part of the same screen.
;
; Each capture is shrunk once by a whole factor f = round(height / 720), which
; averages every f x f block of pixels (StretchBlt's HALFTONE mode), giving a
; working copy about 720 pixels high. A button is only looked for around the
; spots where the game draws it. Spots are fractions of the game's menu area:
; the whole screen at 16:9, and a 16:9 area in the middle of wider screens,
; where the game keeps its menus at the size a 16:9 screen of that height gets.
;
; A match is grayscale normalised cross-correlation (TM_CCOEFF_NORMED) between
; lightly blurred pixels of the button image, scaled to the working height, and
; of the screen: first on half-size copies of both, then at full working size
; around the best few places. 1.0 is a perfect match; 0.85 counts as found.

class Vision {
    static WORK_TARGET := 720
    static MENU_ASPECT := 16 / 9
    static THRESHOLD := 0.85
    static COARSE_KEEP := 3       ; coarse candidates refined at full working size
    static COARSE_FLOOR := 0.55   ; coarse scores below this aren't refined (real buttons score 0.75+)
    static REFINE_REACH := 2      ; working pixels either way around a coarse candidate

    ; Every button the seeder needs a picture of.
    static REQUIRED := ["admin_yes", "game_menu_leave", "deploy_button", "roles_confirm", "switch_team",
        "server_row", "browser_search", "browser_refresh", "menu_enlist", "browser_join", "faction_nva",
        "infantry_create", "select_force", "force_us", "force_nva", "create_unit", "create_unit_button"]

    ; Where each button is drawn: [x, y, reach x, reach y, crop], x and reach x as
    ; fractions of the menu width, y and reach y of the height. The crop limits a
    ; spot to the images with that word in their name ("" = the plain one); unset
    ; means any image of the button.
    static SPOTS := Vision._Spots()

    static _Spots() {
        rows := []  ; the server browser's rows, at the height of their JOIN buttons
        loop 9
            rows.Push(0.2148 + (A_Index - 1) * 0.07339)
        spots := Map(
            "game_menu_leave", [[0.0948, 0.8093, 0.01, 0.01]],
            "deploy_button", [[0.8646, 0.9185, 0.01, 0.01]],
            "roles_confirm", [[0.0828, 0.0361, 0.01, 0.01, "title"], [0.1000, 0.0361, 0.01, 0.01, "select"],
                [0.1448, 0.9407, 0.01, 0.01, ""]],
            "select_force", [[0.4991, 0.2149, 0.01, 0.01]],
            "create_unit", [[0.2917, 0.3056, 0.01, 0.01]],
            "switch_team", [[0.1610, 0.8528, 0.015, 0.01]],
            "browser_search", [[0.7781, 0.1370, 0.01, 0.01]],
            "browser_refresh", [[0.1321, 0.9406, 0.01, 0.01]],
            "menu_enlist", [[0.0703, 0.6296, 0.01, 0.01]],
            "faction_nva", [[0.0500, 0.8519, 0.01, 0.01]],
            "force_us", [[0.2350, 0.4306, 0.01, 0.01]],
            "force_nva", [[0.8107, 0.4310, 0.01, 0.01]],
            "create_unit_button", [[0.7657, 0.7406, 0.01, 0.01]])
        names := [], joins := []
        for y in rows {
            names.Push([0.1896, y - 0.0055, 0.01, 0.012])
            joins.Push([0.6745, y, 0.01, 0.012])
        }
        spots["server_row"] := names
        spots["browser_join"] := joins
        plus := []  ; the + of each unit type on the Units screen
        for y in [0.163, 0.547]
            for x in [0.143, 0.411, 0.640, 0.866]
                plus.Push([x, y, 0.01, 0.01])
        spots["infantry_create"] := plus
        return spots
    }

    ; An admin message's YES: the message hugs the right edge of the screen (or
    ; of the menu area), and its height depends on the message, so YES can be
    ; anywhere in a band down the right.
    static ADMIN_FROM_RIGHT := 1 - 0.8797
    static ADMIN_REACH_X := 0.012
    static ADMIN_TOP := 0.15
    static ADMIN_BOTTOM := 0.90

    ; The force cards on Select Force are drawn a little wider or narrower on some screens.
    static SCALES := Map("force_us", [1.0, 1.05, 0.95], "force_nva", [1.0, 1.05, 0.95])

    ; crops: Map of name -> Array of {img: VisionGray, cut: screen height, tag: word in the file name}
    __New(crops) {
        this.crops := crops
        this.needles := Map()
        this.ready := false
    }

    ; Sets the frame to match against: 32-bit BGRA pixels at working size,
    ; ``ptr`` with ``stride`` bytes per row, shrunk by ``f`` from a ``fullW`` x
    ; ``fullH`` capture whose top left is at (left, top) on screen.
    SetFrame(ptr, w, h, stride, fullW, fullH, f, left := 0, top := 0) {
        this.ptr := ptr, this.fw := w, this.fh := h, this.stride := stride
        this.W := fullW, this.H := fullH, this.f := f
        this.left := left, this.top := top
        this.workH := fullH / f
        this.menuW := Min(fullW, fullH * Vision.MENU_ASPECT)
        this.menuLeft := (fullW - this.menuW) / 2
        this.ready := true
    }

    ; Whole shrink factor for a capture this tall.
    static Factor(height) => Max(1, RoundHalfEven(height / Vision.WORK_TARGET))

    ; Centre of the best match of ``name`` as [x, y] on screen, or "" if it isn't showing.
    ; ``region`` is [left, top, right, bottom] in fractions of the menu area.
    Find(name, region := "") {
        hits := this.Hits(name, region)
        return hits.Length ? this.ToScreen(hits[1]) : ""
    }

    ; Every match of ``name``, best first, as [x, y] on screen.
    FindAll(name, region := "") {
        out := []
        for hit in this.Hits(name, region)
            out.Push(this.ToScreen(hit))
        return out
    }

    ; The best score of ``name`` anywhere it's looked for, found or not (for tests and logs).
    BestScore(name, region := "") {
        best := -1.0
        for hit in this.SpotHits(name, this.SpotsPx(name, region), 2.0, true)
            best := Max(best, hit[1])
        return best
    }

    ToScreen(hit) => [this.left + RoundHalfEven(hit[2] * this.f), this.top + RoundHalfEven(hit[3] * this.f)]

    ; [score, x, y] in working pixels for each spot where ``name`` is found, best first.
    Hits(name, region := "") {
        if !this.ready
            throw Error("No screen to look at yet")
        ; The server list only shows on the browser, which always has REFRESH.
        if name = "server_row" && !this.Hits("browser_refresh").Length
            return []
        hits := this.SpotHits(name, this.SpotsPx(name, region), Vision.THRESHOLD)
        ; best first; equal scores keep their order
        loop hits.Length - 1 {
            i := A_Index + 1, hit := hits[i], j := i - 1
            while j >= 1 && hits[j][1] < hit[1] {
                hits[j + 1] := hits[j], j--
            }
            hits[j + 1] := hit
        }
        return hits
    }

    ; The spots to look at, in working pixels: [x, y, reach x, reach y, crop].
    SpotsPx(name, region := "") {
        out := []
        f := this.f
        if name = "admin_yes" {
            y0 := Vision.ADMIN_TOP * this.H / f, y1 := Vision.ADMIN_BOTTOM * this.H / f
            rx := Ceil(Vision.ADMIN_REACH_X * this.menuW / f)
            xs := [this.W - Vision.ADMIN_FROM_RIGHT * this.menuW,
                this.menuLeft + this.menuW - Vision.ADMIN_FROM_RIGHT * this.menuW]
            for x in xs {
                if A_Index > 1 && Abs(x - xs[1]) < 2 * rx * f
                    continue
                out.Push([x / f, (y0 + y1) / 2, rx, Ceil((y1 - y0) / 2)])
            }
            return out
        }
        if !Vision.SPOTS.Has(name)
            return out
        for spot in Vision.SPOTS[name] {
            if region {
                if !(region[1] <= spot[1] && spot[1] <= region[3] && region[2] <= spot[2] && spot[2] <= region[4])
                    continue
            }
            px := [(this.menuLeft + spot[1] * this.menuW) / f, spot[2] * this.H / f,
                Ceil(spot[3] * this.menuW / f), Ceil(spot[4] * this.H / f)]
            if spot.Length >= 5
                px.Push(spot[5])
            out.Push(px)
        }
        return out
    }

    ; Which images of ``name`` to try at this screen height: ones cut at this
    ; height first, then the 1440p ones; with none cut at this height, the 1440p
    ; ones, or every one if there are none of those either.
    CropIndexes(name, tag?) {
        idx := []
        for crop in this.crops[name]
            if !IsSet(tag) || crop.tag == tag
                idx.Push(A_Index)
        native := [], at1440 := []
        for i in idx {
            cut := this.crops[name][i].cut
            if cut = this.H
                native.Push(i)
            else if cut = 1440
                at1440.Push(i)
        }
        if native.Length {
            for i in at1440
                native.Push(i)
            return native
        }
        return at1440.Length ? at1440 : idx
    }

    ; ``keepAll`` also returns spots where nothing reached the threshold.
    SpotHits(name, spots, threshold, keepAll := false) {
        hits := []
        if !this.crops.Has(name)
            return hits
        scales := Vision.SCALES.Has(name) ? Vision.SCALES[name] : [1.0]
        for spot in spots {
            best := ""
            indexes := spot.Length >= 5 ? this.CropIndexes(name, spot[5]) : this.CropIndexes(name)
            for i in indexes {
                for scale in scales {
                    pair := this.NeedlePair(name, i, scale)
                    nd := pair[1], cn := pair[2]
                    x0 := RoundHalfEven(spot[1] - nd.w / 2) - spot[3]
                    y0 := RoundHalfEven(spot[2] - nd.h / 2) - spot[4]
                    x1 := x0 + nd.w + 2 * spot[3], y1 := y0 + nd.h + 2 * spot[4]
                    x0 := Max(0, x0), y0 := Max(0, y0), x1 := Min(this.fw, x1), y1 := Min(this.fh, y1)
                    if x1 - x0 < nd.w || y1 - y0 < nd.h
                        continue
                    res := Vision.BestIn(this.Window(x0, y0, x1, y1), nd, cn)
                    if !best || res[1] > best[1]
                        best := [res[1], x0 + res[2] + nd.w / 2, y0 + res[3] + nd.h / 2]
                    if best[1] >= threshold
                        break
                }
                if best && best[1] >= threshold
                    break
            }
            if best && (keepAll || best[1] >= threshold)
                hits.Push(best)
        }
        return hits
    }

    ; [full, coarse] needles for image ``i`` of ``name`` at the working height
    ; (coarse is "" for images too small to shrink further).
    NeedlePair(name, i, scale := 1.0) {
        key := name "|" i "|" Round(this.workH, 3) "|" scale
        if this.needles.Has(key)
            return this.needles[key]
        crop := this.crops[name][i]
        s := this.workH / crop.cut * scale
        w := Max(1, RoundHalfEven(crop.img.w * s)), h := Max(1, RoundHalfEven(crop.img.h * s))
        full := Vision.Blur3(Vision.AreaResize(crop.img, w, h))
        coarse := w >= 16 && h >= 8 ? VisionNeedle(Vision.Half(full)) : ""
        return this.needles[key] := [VisionNeedle(full), coarse]
    }

    ; The frame's pixels from (x0, y0) to (x1, y1), in gray and blurred. Pixels
    ; around the window are used for the blur where the frame has them; at the
    ; frame's edges it mirrors the pixels inside (like OpenCV's default border).
    Window(x0, y0, x1, y1) {
        fw := this.fw, fh := this.fh, stride := this.stride, w := x1 - x0, h := y1 - y0
        ; the columns either side of the window
        left := x0 > 0 ? x0 - 1 : (fw > 1 ? 1 : 0)
        right := x1 < fw ? x1 : (fw > 1 ? fw - 2 : 0)
        ; across: gray (as OpenCV's BGR2GRAY does it) of each pixel, its left and
        ; its right, for the rows above the window to below it
        rows := Buffer(w * (h + 2) * 4)
        rp := rows.Ptr
        loop h + 2 {
            y := y0 + A_Index - 2
            y := y < 0 ? (fh > 1 ? 1 : 0) : y >= fh ? (fh > 1 ? fh - 2 : 0) : y
            src := this.ptr + y * stride
            v := NumGet(src, left * 4, "UInt")
            a := ((v >> 16 & 255) * 4899 + (v >> 8 & 255) * 9617 + (v & 255) * 1868 + 8192) >> 14
            p := src + x0 * 4
            v := NumGet(p, "UInt")
            b := ((v >> 16 & 255) * 4899 + (v >> 8 & 255) * 9617 + (v & 255) * 1868 + 8192) >> 14
            loop w - 1 {
                p += 4
                v := NumGet(p, "UInt")
                c := ((v >> 16 & 255) * 4899 + (v >> 8 & 255) * 9617 + (v & 255) * 1868 + 8192) >> 14
                NumPut("Int", a + 2 * b + c, rp), rp += 4
                a := b, b := c
            }
            v := NumGet(src, right * 4, "UInt")
            c := ((v >> 16 & 255) * 4899 + (v >> 8 & 255) * 9617 + (v & 255) * 1868 + 8192) >> 14
            NumPut("Int", a + 2 * b + c, rp), rp += 4
        }
        return Vision._Down(rows, w, h)
    }

    ; The downward half of the blur: rows (w x (h + 2) sums across) to a w x h gray image.
    static _Down(rows, w, h) {
        out := VisionGray(w, h)
        op := out.buf.Ptr, step := w * 4
        loop w {
            p := rows.Ptr + (A_Index - 1) * 4, o := op + A_Index - 1
            a := NumGet(p, "Int"), b := NumGet(p, step, "Int"), p += 2 * step
            loop h {
                c := NumGet(p, "Int"), p += step
                NumPut("UChar", (a + 2 * b + c + 8) >> 4, o), o += w
                a := b, b := c
            }
        }
        return out
    }

    ; 3x3 blur ([1 2 1] each way) of the ``w`` x ``h`` window at (ox, oy) of a
    ; ``gw`` x ``gh`` gray image, mirroring the image's own pixels at its edges.
    static _BlurWindow(gray, gw, gh, ox, oy, w, h) {
        gp := gray.Ptr
        ; across: rows oy-1 .. oy+h of the image (mirrored at its top and bottom), columns of the window
        rows := Buffer(w * (h + 2) * 4)
        rp := rows.Ptr
        loop h + 2 {
            y := oy + A_Index - 2
            y := y < 0 ? (gh > 1 ? 1 : 0) : y >= gh ? (gh > 1 ? gh - 2 : 0) : y
            src := gp + y * gw
            loop w {
                x := ox + A_Index - 1
                l := x > 0 ? x - 1 : (gw > 1 ? 1 : 0)
                r := x + 1 < gw ? x + 1 : (gw > 1 ? gw - 2 : 0)
                NumPut("Int", NumGet(src, l, "UChar") + 2 * NumGet(src, x, "UChar") + NumGet(src, r, "UChar"), rp)
                rp += 4
            }
        }
        return Vision._Down(rows, w, h)
    }

    ; 3x3 blur of a whole gray image, mirroring at its edges.
    static Blur3(img) {
        return Vision._BlurWindow(img.buf, img.w, img.h, 0, 0, img.w, img.h)
    }

    ; 2x2 average, dropping an odd last row or column.
    static Half(img) {
        w := img.w // 2, h := img.h // 2
        out := VisionGray(w, h)
        op := out.buf.Ptr, ip := img.buf.Ptr, iw := img.w
        loop h {
            p := ip + (A_Index - 1) * 2 * iw
            loop w {
                NumPut("UChar", (NumGet(p, "UChar") + NumGet(p, 1, "UChar") + NumGet(p, iw, "UChar") + NumGet(p, iw + 1, "UChar") + 2) >> 2, op++)
                p += 2
            }
        }
        return out
    }

    ; Resizes by area averaging (each output pixel is the average of the input
    ; area it covers, like OpenCV's INTER_AREA), rounding half up.
    static AreaResize(img, outW, outH) {
        wy := Vision._AxisWeights(img.h, outH), wx := Vision._AxisWeights(img.w, outW)
        ; down first, into floats
        cols := []
        cols.Length := outH * img.w
        ip := img.buf.Ptr, iw := img.w
        for oy, weights in wy {
            base := (oy - 1) * iw
            loop iw {
                x := A_Index - 1, sum := 0.0
                for k, wt in weights[2]
                    sum += wt * NumGet(ip, (weights[1] + k - 1) * iw + x, "UChar")
                cols[base + A_Index] := sum
            }
        }
        out := VisionGray(outW, outH)
        op := out.buf.Ptr
        loop outH {
            base := (A_Index - 1) * iw
            for ox, weights in wx {
                sum := 0.0
                for k, wt in weights[2]
                    sum += wt * cols[base + weights[1] + k]
                v := Floor(sum + 0.5)
                NumPut("UChar", v < 0 ? 0 : v > 255 ? 255 : v, op++)
            }
        }
        return out
    }

    ; For each output pixel along an axis: [first input index, [weights...]].
    static _AxisWeights(nIn, nOut) {
        scale := nIn / nOut
        out := []
        loop nOut {
            a := (A_Index - 1) * scale, b := A_Index * scale
            first := Floor(a), last := Min(nIn, Ceil(b))
            weights := [], total := 0.0
            i := first
            while i < last {
                wt := Max(0.0, Min(b, i + 1) - Max(a, i))
                weights.Push(wt), total += wt
                i++
            }
            for k, wt in weights
                weights[k] := wt / total
            out.Push([first, weights])
        }
        return out
    }

    ; Running sums of a gray image's pixels and squared pixels, (w+1) x (h+1),
    ; so the sums over any rectangle take four lookups. Both sums share one
    ; 64-bit number: squares * 2^24 + pixels. A rectangle's pixel sum is under
    ; 2^24 for any button image (at most 65,000 pixels), so it comes back out
    ; as the bottom 24 bits, and the squares as the rest.
    static Integrals(img) {
        w := img.w, h := img.h, step := (w + 1) * 8
        sums := Buffer(step * (h + 1), 0)
        ip := img.buf.Ptr, p := sums.Ptr + step + 8
        loop h {
            run := 0, q := p
            loop w {
                v := NumGet(ip++, "UChar")
                run += (v * v << 24) + v
                NumPut("Int64", NumGet(q - step, "Int64") + run, q)
                q += 8
            }
            p += step
        }
        return {sums: sums, step: step}
    }

    ; Each pixel with its right-hand neighbour in one 64-bit number (the
    ; neighbour in the top 32 bits), so one multiplication by a needle pixel
    ; serves two places at once. Sums of pixel * needle pixel stay under 2^32,
    ; so the halves never mix. Spare entries at the end keep Pair's reads inside.
    static Pack(img) {
        n := img.w * img.h
        packed := Buffer((n + 8) * 8, 0)
        ip := img.buf.Ptr, op := packed.Ptr
        loop n {
            NumPut("Int64", NumGet(ip, "UChar") | NumGet(ip, 1, "UChar") << 32, op)
            ip++, op += 8
        }
        return packed
    }

    ; A gray image ready for Pair: the image, its running sums and its packed pixels.
    static Patch(img) => {img: img, ii: Vision.Integrals(img), packed: Vision.Pack(img)}

    ; Scores of ``nd`` with its top left at (x, y) and at (x + 1, y) of a patch,
    ; or just the first if the needle doesn't fit at the second.
    static Pair(p, x, y, nd) {
        step := p.ii.step, sp := p.ii.sums.Ptr, iw := p.img.w
        ; sum of pixel * needle pixel for both places, eight pixels at a time
        acc := 0, rp := p.packed.Ptr + (y * iw + x) * 8, tp := nd.v.Ptr, octs := nd.octs, tail := nd.tail, rowBytes := nd.rowBytes
        loop nd.h {
            r := rp, t := tp
            loop octs {
                acc += NumGet(r, "Int64") * NumGet(t, "UChar") + NumGet(r, 8, "Int64") * NumGet(t, 1, "UChar")
                    + NumGet(r, 16, "Int64") * NumGet(t, 2, "UChar") + NumGet(r, 24, "Int64") * NumGet(t, 3, "UChar")
                    + NumGet(r, 32, "Int64") * NumGet(t, 4, "UChar") + NumGet(r, 40, "Int64") * NumGet(t, 5, "UChar")
                    + NumGet(r, 48, "Int64") * NumGet(t, 6, "UChar") + NumGet(r, 56, "Int64") * NumGet(t, 7, "UChar")
                r += 64, t += 8
            }
            if tail
                acc += NumGet(r, "Int64") * NumGet(t, "UChar") + NumGet(r, 8, "Int64") * NumGet(t, 1, "UChar")
                    + NumGet(r, 16, "Int64") * NumGet(t, 2, "UChar") + NumGet(r, 24, "Int64") * NumGet(t, 3, "UChar")
            rp += iw * 8, tp += rowBytes
        }
        out := []
        loop (x + 1 <= p.img.w - nd.w) ? 2 : 1 {
            dot := A_Index = 1 ? acc & 0xFFFFFFFF : acc >> 32
            a := y * step + (x + A_Index - 1) * 8, b := a + nd.w * 8, c := a + nd.h * step, d := c + nd.w * 8
            both := NumGet(sp, d, "Int64") - NumGet(sp, b, "Int64") - NumGet(sp, c, "Int64") + NumGet(sp, a, "Int64")
            s := both & 0xFFFFFF
            spread := nd.n * (both >> 24) - s * s
            ; correlation with (n * needle pixel - needle sum), i.e. the needle minus its mean
            out.Push(spread <= 0 || nd.norm <= 0 ? -1.0 : nd.rootN * (nd.n * dot - nd.sum * s) / (Sqrt(spread) * nd.norm))
        }
        return out
    }

    ; Best match of ``nd`` in ``patch``: [score, x, y] of its top left. Looks on
    ; half-size copies first (``cn``), then refines the best few at full size.
    static BestIn(patch, nd, cn) {
        if patch.h < nd.h || patch.w < nd.w
            return [-1.0, 0, 0]
        small := Vision.Half(patch)
        if !cn || small.h < cn.h || small.w < cn.w {
            ; too small to shrink: every place at full size, in reading order
            return Vision._Scan(Vision.Patch(patch), nd)
        }
        nx := small.w - cn.w + 1
        cands := []
        lines := Vision._Scan(Vision.Patch(small), cn, Vision.COARSE_FLOOR)
        if lines != "" {
            ; best first; equal scores in reading order
            for line in StrSplit(Sort(RTrim(lines, "`n")), "`n") {
                k := Integer(SubStr(line, 11)), cx := Mod(k, nx), cy := k // nx
                near := false
                for c in cands
                    if Abs(cx - c[1]) <= 1 && Abs(cy - c[2]) <= 1 {
                        near := true
                        break
                    }
                if !near {
                    cands.Push([cx, cy])
                    if cands.Length = Vision.COARSE_KEEP
                        break
                }
            }
        }
        if !cands.Length
            return [-1.0, 0, 0]
        ; every place within reach of a candidate, scored two at a time along each row
        p := Vision.Patch(patch)
        maxX := patch.w - nd.w, maxY := patch.h - nd.h, reach := Vision.REFINE_REACH
        x0 := maxX, x1 := 0, y0 := maxY, y1 := 0
        for c in cands {
            x0 := Min(x0, 2 * c[1] - reach), x1 := Max(x1, 2 * c[1] + reach)
            y0 := Min(y0, 2 * c[2] - reach), y1 := Max(y1, 2 * c[2] + reach)
        }
        x0 := Max(0, x0), x1 := Min(maxX, x1), y0 := Max(0, y0), y1 := Min(maxY, y1)
        wanted(x, y) {
            for c in cands
                if Abs(x - 2 * c[1]) <= reach && Abs(y - 2 * c[2]) <= reach
                    return true
            return false
        }
        scores := Map()
        y := y0
        while y <= y1 {
            x := x0
            while x <= x1 {
                first := wanted(x, y), second := x + 1 <= x1 && wanted(x + 1, y)
                if first || second {
                    pair := Vision.Pair(p, x, y, nd)
                    if first
                        scores[x << 16 | y] := pair[1]
                    if second
                        scores[(x + 1) << 16 | y] := pair[2]
                }
                x += 2
            }
            y++
        }
        ; the best, column by column (the first of equals wins)
        best := [-2.0, 0, 0]
        x := x0
        while x <= x1 {
            y := y0
            while y <= y1 {
                key := x << 16 | y
                if scores.Has(key) && scores[key] > best[1]
                    best := [scores[key], x, y]
                y++
            }
            x++
        }
        return best[1] < -1.0 ? [-1.0, 0, 0] : best
    }

    ; Scores ``nd`` at every place in a patch, in reading order. Without
    ; ``floor``, returns the best as [score, x, y]; with it, one line per place
    ; scoring at least that: a sort key putting high scores first, then the
    ; place's number in reading order. (Pair, written out here to save a
    ; function call per two places.)
    static _Scan(p, nd, floor?) {
        step := p.ii.step, sp := p.ii.sums.Ptr, iw := p.img.w, pp := p.packed.Ptr
        n := nd.n, norm := nd.norm, rootN := nd.rootN, total := nd.sum, nh := nd.h, w8 := nd.w * 8
        tp0 := nd.v.Ptr, octs := nd.octs, tail := nd.tail, rowBytes := nd.rowBytes, hstep := nh * step
        nx := iw - nd.w + 1, ny := p.img.h - nh + 1, keep := IsSet(floor)
        best := [-2.0, 0, 0], lines := ""
        loop ny {
            y := A_Index - 1, x := 0
            while x < nx {
                acc := 0, rp := pp + (y * iw + x) * 8, tp := tp0
                loop nh {
                    r := rp, t := tp
                    loop octs {
                        acc += NumGet(r, "Int64") * NumGet(t, "UChar") + NumGet(r, 8, "Int64") * NumGet(t, 1, "UChar")
                            + NumGet(r, 16, "Int64") * NumGet(t, 2, "UChar") + NumGet(r, 24, "Int64") * NumGet(t, 3, "UChar")
                            + NumGet(r, 32, "Int64") * NumGet(t, 4, "UChar") + NumGet(r, 40, "Int64") * NumGet(t, 5, "UChar")
                            + NumGet(r, 48, "Int64") * NumGet(t, 6, "UChar") + NumGet(r, 56, "Int64") * NumGet(t, 7, "UChar")
                        r += 64, t += 8
                    }
                    if tail
                        acc += NumGet(r, "Int64") * NumGet(t, "UChar") + NumGet(r, 8, "Int64") * NumGet(t, 1, "UChar")
                            + NumGet(r, 16, "Int64") * NumGet(t, 2, "UChar") + NumGet(r, 24, "Int64") * NumGet(t, 3, "UChar")
                    rp += iw * 8, tp += rowBytes
                }
                loop (x + 1 < nx) ? 2 : 1 {
                    dot := A_Index = 1 ? acc & 0xFFFFFFFF : acc >> 32
                    a := y * step + (x + A_Index - 1) * 8
                    both := NumGet(sp, a + hstep + w8, "Int64") - NumGet(sp, a + w8, "Int64") - NumGet(sp, a + hstep, "Int64") + NumGet(sp, a, "Int64")
                    s := both & 0xFFFFFF
                    spread := n * (both >> 24) - s * s
                    score := spread <= 0 || norm <= 0 ? -1.0 : rootN * (n * dot - total * s) / (Sqrt(spread) * norm)
                    if keep {
                        if score >= floor
                            lines .= Format("{:010d}{:09d}`n", 1000000000 - Round(score * 1000000000), y * nx + x + A_Index - 1)
                    } else if score > best[1] {
                        best := [score, x + A_Index - 1, y]
                    }
                }
                x += 2
            }
        }
        return keep ? lines : (best[1] < -1.0 ? [-1.0, 0, 0] : best)
    }
}

; An 8-bit gray image, one byte per pixel, rows ``w`` bytes apart, with a few
; spare bytes at the end.
class VisionGray {
    __New(w, h) {
        this.w := w, this.h := h
        this.buf := Buffer(w * h + 8, 0)
    }
}

; A button image ready to match: its pixels, rows padded with zeros to a
; multiple of four, and the sums Vision.Pair needs.
class VisionNeedle {
    __New(img) {
        w := img.w, h := img.h, n := w * h
        this.w := w, this.h := h, this.n := n
        quads := (w + 3) // 4
        this.octs := quads // 2, this.tail := quads & 1, this.rowBytes := quads * 4
        this.v := Buffer(this.rowBytes * h, 0)
        total := 0, ip := img.buf.Ptr
        loop n
            total += NumGet(ip, A_Index - 1, "UChar")
        this.sum := total
        norm2 := 0.0
        loop h {
            row := (A_Index - 1) * w, out := (A_Index - 1) * this.rowBytes
            loop w {
                v := NumGet(ip, row + A_Index - 1, "UChar")
                NumPut("UChar", v, this.v, out + A_Index - 1)
                t := n * v - total  ; the pixel minus the mean, times n
                norm2 += t * t
            }
        }
        this.norm := Sqrt(norm2)
        this.rootN := Sqrt(n)
    }
}

; Python's round(): halves go to the even neighbour.
RoundHalfEven(x) {
    low := Floor(x)
    if x - low = 0.5
        return Mod(low, 2) ? low + 1 : low
    return Round(x)
}
