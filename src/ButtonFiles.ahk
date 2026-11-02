; The button images this version uses: file name -> SHA-256. A built
; SynSeeder.exe downloads them from GitHub (see Buttons.Fetch) and only uses
; files that match. tests/run_tests.ahk checks this list against templates/.
class ButtonFiles {
    static SHA256 := Map(
        "admin_yes.png", "386464e94c233cf06dfd9c88aeebc043f67507300c62cf2a7c5eb645804bddc8",
        "browser_join.png", "f5daffe59d73ffc40146d8d2cbef62e7a431390a7d647abfebad182674dbc3fb",
        "browser_refresh.png", "4980253270b70ab13476daf9e58d228bdda6a49248223c8febbc0ecbc9c09c7f",
        "browser_search.png", "eadd57b989eb76d447e2800a7bcbfeeb42f02b0cd095df5ffc474f8a1d647e36",
        "create_unit.1080p.png", "006db33d6ac1876d4a8a4da71795cc039018d5a8dbf94bd15887ca936ebe1bd2",
        "create_unit.png", "85b87d85d5a714cd4a7d5d17265aed3320dbe0c6f17eb74ef29355537e364e93",
        "create_unit_button.png", "bf1e542ff5d5cf4204688bfeff4f6367ea3d8730ccdef8e6633083a18b98a4a6",
        "deploy_button.png", "6b97653cdb22431d69d3bac0bc5b86833044ca6b4b184519bf447c07cc930c0d",
        "faction_nva.png", "1329581a9fed6f954915c2d8e20ee57ce3f2f8046abcdad75fb417f58d482718",
        "force_nva.png", "5c7c068c14741a12191283d73cd72c94a5b364c76ab85fcab69df8b24d35b40d",
        "force_us.png", "4301190a77e10e5991f2571109e5305a9869c88254d26b1ef5efb289b333508d",
        "game_menu_leave.png", "9491d475c556683a69a7b837f416aa1a845371d3e7a9b4a40e2708973b562f6f",
        "infantry_create.png", "d647972a24413e113c766ac72df8c69ae5c1b37c7de245d972436c653634d7ba",
        "menu_enlist.png", "1fc4c18ce534e076f8245fe80a2c29d1116f5f4618b1ac51d27b3ce3668d68da",
        "roles_confirm.png", "061a8c8b99ff9189aba1447f4dfcd7826166d23cbc4dce3c0c5708ac2da3adbb",
        "roles_confirm.select.png", "61c4d4ca9f9015846656765782fe3d7e61776e23dbc45e4c44c5ec19a8500abb",
        "roles_confirm.title.png", "c1f214cbf488395c566ab50237ba8f37d935dae74f49430ee168b348b57650ac",
        "select_force.png", "64c3d512b6d76053eda0ad9c1de7586ba8d3338858df66fe2fde8482955a7e3d",
        "server_row.1080p.png", "307dffcdf2caa9363e041ba71f2c7efeee194203cc0d41f0b5d71e6951f47761",
        "server_row.2160p.png", "0f45fd63f16f7c3f3cfa80152c121dfae0c6a0f337a8333e93f99e187387a0fb",
        "server_row.png", "c2c588cb17cc7b347be3ce7f71f3d98b40cc4f47f8817aa2727658bf45adc707",
        "switch_team.2160p.png", "9caa3453c14759b8638cf215eefe3daf9ee5cf473065184d9edba37f92530388",
        "switch_team.png", "5b563b6f86fc14ce43cb70a8090035a3c622c687752e19d9de737dc112aaf7dd")
}
