; The fonts the setup window uses: file name -> SHA-256. A built SynSeeder.exe
; downloads them from assets/fonts on GitHub (see Look.LoadFonts) and only
; uses files that match. tests/run_tests.ahk checks this list against assets\fonts.
; Inter (text) and Barlow Condensed (the title) are under the SIL Open Font
; License: assets/fonts/LICENSE-Inter and LICENSE-BarlowCondensed.
class FontFiles {
    static SHA256 := Map(
        "BarlowCondensed-SemiBold.ttf", "8bb032ba4d39503026c53568148e08e75b7f79621abda407fad2878febebce28",
        "Inter-Bold.ttf", "288316099b1e0a47a4716d159098005eef7c0066921f34e3200393dbdb01947f",
        "Inter-Regular.ttf", "40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82")
}
