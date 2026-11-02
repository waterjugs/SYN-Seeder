; Reading and writing JSON (settings, the stats page, GitHub's release list).
;
; Objects become Maps and arrays become Arrays. true and false become 1 and 0,
; and null becomes "" (AutoHotkey has no separate values for them); write
; booleans with Json.Bool(value) to get true and false back out.

class Json {
    static Load(text) {
        pos := 1
        value := Json._Value(text, &pos)
        Json._Space(text, &pos)
        if pos <= StrLen(text)
            throw ValueError("Unexpected text after the JSON at character " pos)
        return value
    }

    ; JSON text for ``value``. Maps are written with their keys in the order given
    ; by ``order`` where it names them, then the rest in the Map's own order.
    static Dump(value, indent := "", order := "", level := 0) {
        if value is JsonBool
            return value.value ? "true" : "false"
        if value is Map || value is Array {
            items := []
            if value is Map {
                keys := []
                if order is Array
                    for key in order
                        if value.Has(key)
                            keys.Push(key)
                for key in value {
                    if order is Array {
                        named := false
                        for k in order
                            if k == key {
                                named := true
                                break
                            }
                        if named
                            continue
                    }
                    keys.Push(key)
                }
                for key in keys
                    items.Push(Json._Quote(String(key)) (indent = "" ? ":" : ": ") Json.Dump(value[key], indent, "", level + 1))
                open := "{", close := "}"
            } else {
                for item in value
                    items.Push(Json.Dump(item ?? "", indent, "", level + 1))
                open := "[", close := "]"
            }
            if !items.Length
                return open close
            if indent = "" {
                text := ""
                for item in items
                    text .= (A_Index > 1 ? "," : "") item
                return open text close
            }
            pad := "", inner := ""
            loop level
                pad .= indent
            inner := pad indent
            text := ""
            for item in items
                text .= (A_Index > 1 ? ",`n" : "") inner item
            return open "`n" text "`n" pad close
        }
        if IsObject(value)
            throw TypeError("Can't write a " Type(value) " as JSON")
        if value is Integer
            return String(value)
        if value is Float
            return Json._Float(value)
        return Json._Quote(value)
    }

    ; Marks a value to be written as true or false.
    static Bool(value) => JsonBool(value)

    static _Float(value) {
        if value != value || Abs(value) = Abs(value) + 1  ; NaN or infinite
            throw ValueError("Can't write " value " as JSON")
        text := Format("{:.17g}", value)
        ; the shortest text that reads back as the same number
        loop 17 {
            short := Format("{:." A_Index "g}", value)
            if Float(short) = value {
                text := short
                break
            }
        }
        return InStr(text, ".") || InStr(text, "e") ? text : text ".0"
    }

    static _Quote(text) {
        text := StrReplace(text, "\", "\\")
        text := StrReplace(text, '"', '\"')
        text := StrReplace(text, "`n", "\n")
        text := StrReplace(text, "`r", "\r")
        text := StrReplace(text, "`t", "\t")
        text := StrReplace(text, "`b", "\b")
        text := StrReplace(text, "`f", "\f")
        out := ""
        loop parse text {  ; control characters, and surrogates so a broken pair still reads back
            code := Ord(A_LoopField)
            out .= code < 0x20 || (code >= 0xD800 && code <= 0xDFFF) ? Format("\u{:04x}", code) : A_LoopField
        }
        return '"' out '"'
    }

    static _Space(text, &pos) {
        if RegExMatch(text, "\G[ \t\r\n]+", &m, pos)
            pos += m.Len
    }

    static _Value(text, &pos) {
        Json._Space(text, &pos)
        ch := SubStr(text, pos, 1)
        switch ch {
            case "{":
                obj := Map()
                pos++
                Json._Space(text, &pos)
                if SubStr(text, pos, 1) = "}" {
                    pos++
                    return obj
                }
                loop {
                    Json._Space(text, &pos)
                    if SubStr(text, pos, 1) != '"'
                        throw ValueError("Expected a name in quotes at character " pos)
                    key := Json._String(text, &pos)
                    Json._Space(text, &pos)
                    if SubStr(text, pos, 1) != ":"
                        throw ValueError("Expected : at character " pos)
                    pos++
                    obj[key] := Json._Value(text, &pos)
                    Json._Space(text, &pos)
                    ch := SubStr(text, pos++, 1)
                    if ch = "}"
                        return obj
                    if ch != ","
                        throw ValueError("Expected , or } at character " (pos - 1))
                }
            case "[":
                arr := []
                pos++
                Json._Space(text, &pos)
                if SubStr(text, pos, 1) = "]" {
                    pos++
                    return arr
                }
                loop {
                    arr.Push(Json._Value(text, &pos))
                    Json._Space(text, &pos)
                    ch := SubStr(text, pos++, 1)
                    if ch = "]"
                        return arr
                    if ch != ","
                        throw ValueError("Expected , or ] at character " (pos - 1))
                }
            case '"':
                return Json._String(text, &pos)
        }
        if RegExMatch(text, "\G-?(?:0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?", &m, pos) {
            pos += m.Len
            return m[1] != "" || m[2] != "" ? Float(m[0]) : Integer(m[0])
        }
        for word, value in Map("true", 1, "false", 0, "null", "") {
            if SubStr(text, pos, StrLen(word)) == word {
                pos += StrLen(word)
                return value
            }
        }
        throw ValueError("Unexpected " (ch = "" ? "end of text" : "'" ch "'") " at character " pos)
    }

    ; The string whose opening quote is at ``pos``. Scanned with InStr rather
    ; than one regular expression, which would hit PCRE's recursion limit on
    ; strings of a few thousand characters (such as long release notes).
    static _String(text, &pos) {
        start := pos + 1, from := start
        loop {
            close := InStr(text, '"', true, from)
            if !close
                throw ValueError("Broken text in quotes at character " pos)
            slashes := 0  ; a quote after an odd number of backslashes is part of the text
            while close - slashes - 1 >= start && SubStr(text, close - slashes - 1, 1) = "\"
                slashes++
            if !(slashes & 1)
                break
            from := close + 1
        }
        raw := SubStr(text, start, close - start)
        if RegExMatch(raw, "[\x00-\x1F]")
            throw ValueError("Broken text in quotes at character " pos)
        pos := close + 1
        if !InStr(raw, "\")
            return raw
        out := "", i := 1
        while j := InStr(raw, "\", true, i) {
            out .= SubStr(raw, i, j - i)
            esc := SubStr(raw, j + 1, 1)
            i := j + 2
            switch esc, true {
                case '"', "\", "/": out .= esc
                case "b": out .= "`b"
                case "f": out .= "`f"
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "u":
                    hex := SubStr(raw, i, 4)
                    if !RegExMatch(hex, "^[0-9A-Fa-f]{4}$")
                        throw ValueError("Broken \u escape at character " (start + j - 1))
                    out .= Chr(Integer("0x" hex))
                    i += 4
                default:
                    throw ValueError("Unknown escape \" esc " at character " (start + j - 1))
            }
        }
        return out SubStr(raw, i)
    }
}

class JsonBool {
    __New(value) => this.value := !!value
}
