; The button images as PNG files, built into the exe.
ImageExt() => ".png"

InstallImages() {
    DirCreate IMAGE_DIR
    FileInstall "..\..\templates\admin_yes.png", IMAGE_DIR "\admin_yes.png", 1
    FileInstall "..\..\templates\browser_join.png", IMAGE_DIR "\browser_join.png", 1
    FileInstall "..\..\templates\browser_refresh.png", IMAGE_DIR "\browser_refresh.png", 1
    FileInstall "..\..\templates\browser_search.png", IMAGE_DIR "\browser_search.png", 1
    FileInstall "..\..\templates\create_unit.1080p.png", IMAGE_DIR "\create_unit.1080p.png", 1
    FileInstall "..\..\templates\create_unit.png", IMAGE_DIR "\create_unit.png", 1
    FileInstall "..\..\templates\create_unit_button.png", IMAGE_DIR "\create_unit_button.png", 1
    FileInstall "..\..\templates\deploy_button.png", IMAGE_DIR "\deploy_button.png", 1
    FileInstall "..\..\templates\faction_nva.png", IMAGE_DIR "\faction_nva.png", 1
    FileInstall "..\..\templates\force_nva.png", IMAGE_DIR "\force_nva.png", 1
    FileInstall "..\..\templates\force_us.png", IMAGE_DIR "\force_us.png", 1
    FileInstall "..\..\templates\game_menu_leave.png", IMAGE_DIR "\game_menu_leave.png", 1
    FileInstall "..\..\templates\infantry_create.png", IMAGE_DIR "\infantry_create.png", 1
    FileInstall "..\..\templates\menu_enlist.png", IMAGE_DIR "\menu_enlist.png", 1
    FileInstall "..\..\templates\roles_confirm.png", IMAGE_DIR "\roles_confirm.png", 1
    FileInstall "..\..\templates\roles_confirm.select.png", IMAGE_DIR "\roles_confirm.select.png", 1
    FileInstall "..\..\templates\roles_confirm.title.png", IMAGE_DIR "\roles_confirm.title.png", 1
    FileInstall "..\..\templates\select_force.png", IMAGE_DIR "\select_force.png", 1
    FileInstall "..\..\templates\server_row.1080p.png", IMAGE_DIR "\server_row.1080p.png", 1
    FileInstall "..\..\templates\server_row.2160p.png", IMAGE_DIR "\server_row.2160p.png", 1
    FileInstall "..\..\templates\server_row.png", IMAGE_DIR "\server_row.png", 1
    FileInstall "..\..\templates\switch_team.2160p.png", IMAGE_DIR "\switch_team.2160p.png", 1
    FileInstall "..\..\templates\switch_team.png", IMAGE_DIR "\switch_team.png", 1
}
