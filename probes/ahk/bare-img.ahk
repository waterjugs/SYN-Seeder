#Requires AutoHotkey v2.0
;@Ahk2Exe-SetName SynSeeder
;@Ahk2Exe-SetDescription SynSeeder
;@Ahk2Exe-SetVersion 0.9.0
;@Ahk2Exe-SetCompanyName waterjugs
;@Ahk2Exe-SetCopyright Copyright (c) waterjugs
;@Ahk2Exe-SetOrigFilename SynSeeder.exe
;@Ahk2Exe-SetMainIcon ..\..\assets\synseeder.ico
; The bare window plus the button images (PNG), unpacked at start.
IMAGE_DIR := EnvGet("LOCALAPPDATA") "\SynSeeder\images"
InstallImages()
#Include bare-body.ahk
#Include images.ahk
