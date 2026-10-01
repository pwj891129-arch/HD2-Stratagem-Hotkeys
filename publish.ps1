param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys',
    [string]$Tag = 'stratagem-hotkeys-0.1.12-test'
)
$ErrorActionPreference = 'Stop'
$AssetPath = (Resolve-Path -LiteralPath $AssetPath).Path
$assetName = [IO.Path]::GetFileName($AssetPath)
if ($assetName -ne 'HD2-Stratagem-Hotkeys-0.1.12-test.zip') { throw 'Unexpected addon package name.' }
if ($Commit -notmatch '^[0-9a-f]{40}$') { throw 'A full source commit hash is required.' }
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid repository name.' }
$credentialLines = "protocol=https`nhost=github.com`n`n" | git -c "safe.directory=$PSScriptRoot" credential fill
if ($LASTEXITCODE -ne 0) { throw 'GitHub Git authentication is unavailable.' }
$credential = @{}
foreach ($line in $credentialLines) {
    $parts = $line.Split('=', 2)
    if ($parts.Length -eq 2) { $credential[$parts[0]] = $parts[1] }
}
if (-not $credential['password']) { throw 'GitHub Git authentication is unavailable.' }
$headers = @{ Authorization = 'Bearer ' + $credential['password']; Accept = 'application/vnd.github+json';
    'User-Agent' = 'HD2-Helper-Addon-Release'; 'X-GitHub-Api-Version' = '2022-11-28' }
$api = "https://api.github.com/repos/$Repository/releases"
$notes = @'
## HD2 Stratagem Hotkeys 0.1.12-test

스트라타젬 열기 버튼을 마우스 엄지버튼에 할당하면 원형 메뉴가 열리지 않던 문제를 수정하는 테스트 빌드입니다.

- 게임에 설정한 앞·뒤 엄지버튼(마우스 4/5, XBUTTON1/2)으로 스트라타젬 원형 메뉴를 열 수 있도록 했습니다. 기존에는 키보드 열기 설정만 허용했습니다.
- 게임의 마우스 API에서 실제 엄지버튼 번호를 확인합니다. 버튼 번호를 임의로 추측하지 않으며, 읽을 수 없거나 설정이 일치하지 않으면 입력하지 않습니다.
- 엄지버튼을 놓아 항목을 선택한 뒤 같은 버튼을 다시 누르는 입력을 보내 메뉴를 활성화하고, 게임에 저장된 방향키로 커맨드를 입력하도록 했습니다. 합성 입력으로 원형 메뉴가 다시 열리지 않습니다.
- 엄지버튼 + 숫자열 1~4 조합도 개인 슬롯 번호와 매칭됩니다. 캐릭터의 실제 스트라타젬 메뉴 활성 여부, 설정 변경, 채팅과 포커스 해제 시 취소 조건을 유지했습니다.
- 마우스 버튼과 키보드 입력을 번갈아 보낼 때 입력 구조를 올바르게 전환하도록 했습니다. 좌·우클릭이나 자동 투척 입력은 보내지 않습니다.
- 로그에서 `BINDING list-key vk=5 device=mouse-thumb` 또는 `vk=6`으로 감지한 엄지버튼을 확인할 수 있습니다.
- **게임의 스트라타젬 열기 동작은 누르고 있기(Hold)로 설정해야 합니다.** Press/토글, 휠, 다른 마우스 버튼, 마우스 방향키와 컨트롤러 입력은 지원하지 않습니다.
- 0.1.11-test의 아이콘 표시 방식과 별도 자동재장전 모드는 변경하지 않았습니다. Lua-only 패키지이며 게임 이미지·재질·셰이더·글꼴을 포함하지 않습니다.

방향 입력은 기존 키보드 설정(방향키/WASD 등)을 그대로 사용합니다. 조준과 투척은 수동입니다.

### 설치

게임을 종료하고 Arsenal에서 이전 버전을 교체한 뒤 **원형 오버레이 ON/OFF를 체크**하고 반드시 Purge / Deploy 하세요. 이전 옵션 파일과 Icons 파일이 남지 않도록 해야 합니다. Bingus Shared Loader v18 / API 1과 함께 재시작하세요. 기본 우선순위에서는 Shared Loader를 맨 아래에 놓으세요.
인게임 설정 메뉴는 추가하지 않았습니다. Mod Options Menu와 Mod Bindings Menu는 필요하지 않습니다.
자동재장전은 기존 HD2 Auto Reload 0.3.28-test를 유지하면 됩니다. 이번 수정으로 자동재장전 모드를 교체할 필요는 없습니다. 헬퍼의 동일 기능을 동시에 켜지 마세요.
로그: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\hd2_helper_stratagem_hotkeys.log`

3,862개 LuaJIT 검사와 최소 크기·Lua-only 패키지 검사를 통과했습니다. 양쪽 엄지버튼의 저장 설정, 게임 버튼 번호 조회, Hold 조건, 잘못된 설정과 API 실패, 마우스 누르기·떼기, 마우스/키보드 입력 구조 전환, 메뉴 선택과 숫자 조합, 누른 상태에서 설정 변경, 포커스 해제 시 소유 버튼 해제와 기존 메뉴 활성 조건을 검사했습니다. 실제 게임을 실행하거나 입력을 보내지 않았으므로 엄지버튼 할당 상태의 인게임 동작 확인이 필요합니다. 설치된 모드 파일은 변경하지 않았습니다.
'@
try {
    $releases = Invoke-RestMethod -Uri ($api + '?per_page=100') -Headers $headers
    $release = $releases | Where-Object tag_name -eq $Tag | Select-Object -First 1
    if (-not $release) {
        $body = @{ tag_name = $Tag; target_commitish = $Commit; name = 'HD2 Stratagem Hotkeys 0.1.12-test (mouse thumb list binding)';
            body = $notes; draft = $true; prerelease = $true } | ConvertTo-Json
        $release = Invoke-RestMethod -Method Post -Uri $api -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
    }
    $expectedHash = (Get-FileHash -LiteralPath $AssetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $existing = $release.assets | Where-Object name -eq $assetName | Select-Object -First 1
    if ($existing) {
        if ($existing.digest -ne "sha256:$expectedHash") { throw 'Existing package differs; not replacing it.' }
    } else {
        $uri = $release.upload_url.Split('{')[0] + '?name=' + [Uri]::EscapeDataString($assetName)
        $uploaded = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/zip' -InFile $AssetPath
        if ($uploaded.state -ne 'uploaded' -or $uploaded.digest -ne "sha256:$expectedHash") {
            throw 'Asset upload verification failed; leaving draft unpublished.'
        }
    }
    if ($release.draft) {
        $body = @{ draft = $false; prerelease = $true; make_latest = 'false' } | ConvertTo-Json
        $release = Invoke-RestMethod -Method Patch -Uri ($api + '/' + $release.id) -Headers $headers -ContentType 'application/json' -Body $body
    }
    $verified = Invoke-RestMethod -Uri ($api + '/tags/' + $Tag) -Headers $headers
    $asset = $verified.assets | Where-Object name -eq $assetName | Select-Object -First 1
    if ($verified.draft -or -not $verified.prerelease -or $asset.digest -ne "sha256:$expectedHash") {
        throw 'Published release verification failed.'
    }
    [ordered]@{ url = $verified.html_url; prerelease = $verified.prerelease; asset = $asset.name;
        sha256 = $expectedHash; sourceCommit = $Commit } | ConvertTo-Json
} finally {
    $headers.Clear(); $credential.Clear(); $credentialLines = $null
}
