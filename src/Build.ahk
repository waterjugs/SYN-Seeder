; What kind of build this is. CI rewrites this file when it builds: RELEASE is
; true for a v* tag, and COMMIT names the commit the button images are
; downloaded from. As they are here, a build is a test build: it doesn't update
; itself, and gets the button images from the main branch.
class Build {
    static RELEASE := false
    static COMMIT := ""
}
