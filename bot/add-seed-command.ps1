# Adds the /seed command to the SYNDICATE Discord server (discord.gg/syn-hll),
# the only server the bot works in. Run it once, after the SynSeeder bot has
# been invited to that server (README.md, step 7).
#
# To run it (README.md, step 8): open the folder this file is in, type
# powershell in File Explorer's address bar and press Enter, then paste this
# line and press Enter:
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\add-seed-command.ps1
#
# It asks for two things: the Application ID and the bot token. The token
# stays hidden while you paste it and is never saved. When
# it finishes, whether it worked or not, press "Reset Token" on the Bot page
# of the Developer Portal, so the token you pasted stops working.
#
# Keep this file plain ASCII: Windows PowerShell 5.1 misreads other characters.

$ErrorActionPreference = 'Stop'

# What /seed looks like in Discord. Who can see it is set afterwards in Server
# Settings > Integrations (README.md, step 9): @everyone off, Syngineers on.
# It has no "default_member_permissions", because Discord would keep that
# limit even for roles allowed there. Until step 9 everyone sees /seed, and
# the bot itself still refuses anyone without the Syngineers role.
$command = @'
[
  {
    "name": "seed",
    "type": 1,
    "description": "Call a seed: PCs with Seed when pinged ticked start joining the game server"
  }
]
'@

# The SYNDICATE server. The bot itself refuses /seed from any other server.
$serverId = '1117120667490455713'

$api = 'https://discord.com/api/v10'
$userAgent = 'DiscordBot (https://github.com/waterjugs/SYN-Seeder, 1.0)'

function Read-DiscordId([string]$prompt) {
    while ($true) {
        $text = (Read-Host $prompt).Trim()
        if ($text -match '^[0-9]{17,20}$') { return $text }
        Write-Host '  That should be a number of 17 to 20 digits. Copy it again and paste it here.' -ForegroundColor Yellow
    }
}

function Read-Secret([string]$prompt) {
    $secure = Read-Host $prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $text = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer).Trim()
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
    if ($text.StartsWith('Bot ')) { $text = $text.Substring(4).Trim() }
    return $text
}

# Explains a failed request. Only the status and Discord's own message are
# shown, never the request itself, which holds the token.
function Show-Failure($err, [string]$step) {
    $status = 0
    if ($err.Exception.Response) { $status = [int]$err.Exception.Response.StatusCode }
    Write-Host ''
    Write-Host "That didn't work while $step." -ForegroundColor Red
    switch ($status) {
        401 { Write-Host 'Discord says the bot token is wrong. On the Bot page, press Reset Token, copy the new one and run this again.' }
        403 { Write-Host "Discord says the bot can't add commands to the SYNDICATE server. Check that you invited it there with the link in README.md, step 7." }
        404 { Write-Host 'Discord says that Application ID is wrong. Copy it again and run this again.' }
        429 { Write-Host 'Discord says to slow down. Wait a minute and run this again.' }
        0 { Write-Host ('Discord could not be reached: ' + $err.Exception.Message) }
        default { Write-Host ('Discord answered with status ' + $status + '.') }
    }
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) {
        Write-Host ('Discord said: ' + $err.ErrorDetails.Message)
    }
}

try {
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        Write-Host 'Windows is running PowerShell in a locked-down mode on this PC, so this script cannot work here.' -ForegroundColor Red
        Write-Host 'Ask Claude for another way to add /seed.'
        return
    }

    # Windows PowerShell 5.1 sometimes doesn't offer TLS 1.2, which Discord needs.
    # This adds it only when the PC hasn't left the choice to Windows.
    $protocols = [Net.ServicePointManager]::SecurityProtocol
    if ([int]$protocols -ne 0 -and ([int]$protocols -band 3072) -eq 0) {
        [Net.ServicePointManager]::SecurityProtocol = $protocols -bor [Net.SecurityProtocolType]::Tls12
    }

    Write-Host 'This adds the /seed command to the SYNDICATE Discord server.'
    Write-Host 'Paste each answer with a right-click, then press Enter.'
    Write-Host ''
    $applicationId = Read-DiscordId 'Application ID (Developer Portal > General Information)'
    $token = ''
    while ($token -eq '') {
        $token = Read-Secret 'Bot token (Developer Portal > Bot > Reset Token > Copy). It stays hidden'
    }
    $headers = @{ Authorization = "Bot $token" }

    $done = $false
    $step = 'checking the token'
    try {
        # The token must belong to this Application ID, or the command would
        # go to some other app.
        $app = Invoke-RestMethod -Method Get -Uri "$api/applications/@me" -Headers $headers -UserAgent $userAgent -TimeoutSec 30
        if ([string]$app.id -ne $applicationId) {
            Write-Host ''
            Write-Host 'That bot token belongs to a different app than that Application ID.' -ForegroundColor Red
            Write-Host 'Copy both again from the same app in the Developer Portal and run this again.'
        } else {
            $step = 'adding /seed'
            $response = Invoke-RestMethod -Method Put `
                -Uri "$api/applications/$applicationId/guilds/$serverId/commands" `
                -Headers $headers `
                -UserAgent $userAgent `
                -ContentType 'application/json; charset=utf-8' `
                -Body $command `
                -TimeoutSec 30
            $names = @($response | ForEach-Object { '/' + $_.name }) -join ', '
            Write-Host ''
            Write-Host "Done. Your server now has: $names" -ForegroundColor Green
            $done = $true
        }
    } catch {
        Show-Failure $_ $step
    } finally {
        $token = $null
        $headers = $null
        Remove-Variable token, headers -ErrorAction SilentlyContinue
    }

    # A token was pasted either way, and it works until it's reset.
    Write-Host ''
    if ($done) {
        Write-Host 'Now go to the Developer Portal > Bot, press Reset Token, and close the page without copying the new token.'
        Write-Host 'The bot never needs a token, so this leaves no working token anywhere.'
    } else {
        Write-Host 'Before you stop, go to the Developer Portal > Bot and press Reset Token, so the token you pasted stops working.'
        Write-Host 'To try again, press Reset Token and Copy there for a fresh one, and run this again.'
    }
} finally {
    Read-Host 'Press Enter to close'
}
