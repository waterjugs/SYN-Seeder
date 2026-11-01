; The button images as uncompressed BMP files (made from templates/ by the
; workflow into build/bmp), built into the exe.
ImageExt() => ".bmp"

InstallImages() {
    DirCreate IMAGE_DIR
    FileInstall "..\..\build\bmp\admin_yes.bmp", IMAGE_DIR "\admin_yes.bmp", 1
    FileInstall "..\..\build\bmp\browser_join.bmp", IMAGE_DIR "\browser_join.bmp", 1
    FileInstall "..\..\build\bmp\browser_refresh.bmp", IMAGE_DIR "\browser_refresh.bmp", 1
    FileInstall "..\..\build\bmp\browser_search.bmp", IMAGE_DIR "\browser_search.bmp", 1
    FileInstall "..\..\build\bmp\create_unit.1080p.bmp", IMAGE_DIR "\create_unit.1080p.bmp", 1
    FileInstall "..\..\build\bmp\create_unit.bmp", IMAGE_DIR "\create_unit.bmp", 1
    FileInstall "..\..\build\bmp\create_unit_button.bmp", IMAGE_DIR "\create_unit_button.bmp", 1
    FileInstall "..\..\build\bmp\deploy_button.bmp", IMAGE_DIR "\deploy_button.bmp", 1
    FileInstall "..\..\build\bmp\faction_nva.bmp", IMAGE_DIR "\faction_nva.bmp", 1
    FileInstall "..\..\build\bmp\force_nva.bmp", IMAGE_DIR "\force_nva.bmp", 1
    FileInstall "..\..\build\bmp\force_us.bmp", IMAGE_DIR "\force_us.bmp", 1
    FileInstall "..\..\build\bmp\game_menu_leave.bmp", IMAGE_DIR "\game_menu_leave.bmp", 1
    FileInstall "..\..\build\bmp\infantry_create.bmp", IMAGE_DIR "\infantry_create.bmp", 1
    FileInstall "..\..\build\bmp\menu_enlist.bmp", IMAGE_DIR "\menu_enlist.bmp", 1
    FileInstall "..\..\build\bmp\roles_confirm.bmp", IMAGE_DIR "\roles_confirm.bmp", 1
    FileInstall "..\..\build\bmp\roles_confirm.select.bmp", IMAGE_DIR "\roles_confirm.select.bmp", 1
    FileInstall "..\..\build\bmp\roles_confirm.title.bmp", IMAGE_DIR "\roles_confirm.title.bmp", 1
    FileInstall "..\..\build\bmp\select_force.bmp", IMAGE_DIR "\select_force.bmp", 1
    FileInstall "..\..\build\bmp\server_row.1080p.bmp", IMAGE_DIR "\server_row.1080p.bmp", 1
    FileInstall "..\..\build\bmp\server_row.2160p.bmp", IMAGE_DIR "\server_row.2160p.bmp", 1
    FileInstall "..\..\build\bmp\server_row.bmp", IMAGE_DIR "\server_row.bmp", 1
    FileInstall "..\..\build\bmp\switch_team.2160p.bmp", IMAGE_DIR "\switch_team.2160p.bmp", 1
    FileInstall "..\..\build\bmp\switch_team.bmp", IMAGE_DIR "\switch_team.bmp", 1
}
