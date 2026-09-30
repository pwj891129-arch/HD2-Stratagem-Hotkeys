param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys',
    [string]$Tag = 'stratagem-hotkeys-0.1.4-test'
)
$ErrorActionPreference = 'Stop'
$AssetPath = (Resolve-Path -LiteralPath $AssetPath).Path
$assetName = [IO.Path]::GetFileName($AssetPath)
if ($assetName -ne 'HD2-Stratagem-Hotkeys-0.1.4-test.zip') { throw 'Unexpected addon package name.' }
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
## HD2 Stratagem Hotkeys 0.1.4-test

오버레이를 게임에 설정된 스트라타젬 목록 열기 키로 통일하고, 장착 목록 판독 위치를 수정했습니다.

- 게임에 저장된 스트라타젬 목록 열기 키를 누르고 있으면 원형 메뉴를 엽니다. 마우스로 방향을 고르고 키를 놓으면 해당 커맨드를 입력합니다. 중앙에서 놓으면 취소합니다.
- F6·마우스 버튼을 별도 오버레이 키로 쓰는 설정을 제거했습니다. 목록 열기 키는 고정 Alt가 아니라 각 사용자의 게임 설정을 읽습니다.
- 장착 스트라타젬 기록에서 내부 데이터 시작점인 56바이트 오프셋이 누락되어 장착 4개를 확인하지 못하던 문제를 수정했습니다. 기존 실제 게임 캡처의 목록도 정상 판독되는지 검사했습니다.
- 목록 열기 키 + 숫자열 1~4도 유지합니다. 두 기능을 함께 켜면 숫자 조합키가 우선하며, 이미 열린 원형 메뉴를 닫고 해당 슬롯 커맨드를 한 번만 입력합니다.
- 커맨드 입력을 위해 모드가 누른 목록 키가 다시 오버레이를 열지 않도록 했습니다. 메뉴가 열린 동안 키 설정이 바뀌면 선택을 취소합니다.
- 옵션 상태와 목록 키, 목록 판독 실패를 구분할 수 있는 로그를 추가했습니다.
- 원형 메뉴는 계속 이름·슬롯 번호·상태로 표시합니다. 커맨드 입력만 자동이며 조준·투척은 수동입니다.
- 시작 충돌을 해결한 옵션 패키지 최소 크기 규칙을 유지했습니다.

0.1.3-test에서 게임 시작 정상화가 사용자 테스트로 확인됐습니다. 이번 수정은 단축키 통합과 목록 판독에 대한 것으로, 실제 게임의 원형 메뉴 렌더링과 호출 공 준비는 추가 검증이 필요합니다.

### 설치

게임을 종료하고 Arsenal에서 이전 버전을 교체한 뒤 **원형 오버레이 ON/OFF를 체크**하고 반드시 Purge / Deploy 하세요. 이전 옵션 파일과 Icons 파일이 남지 않도록 해야 합니다. Bingus Shared Loader v18 / API 1과 함께 재시작하세요. 기본 우선순위에서는 Shared Loader를 맨 아래에 놓으세요.
인게임 설정 메뉴는 추가하지 않았습니다. Mod Options Menu와 Mod Bindings Menu는 필요하지 않습니다.
자동재장전은 HD2 Auto Reload 0.3.27-test 이상을 유지하세요. 이전 버전의 작은 옵션 파일은 시작 오류를 다시 일으킬 수 있습니다. 헬퍼의 동일 기능을 동시에 켜지 마세요.
로그: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\hd2_helper_stratagem_hotkeys.log`

338개 LuaJIT 기능 검사와 최소 크기·Lua-only 패키지 검사를 통과했습니다. 실제 오버레이 동작은 인게임 검증이 필요합니다. 이름은 게임의 디버그 명칭을 사용합니다. 설치된 게임 모드 파일을 자동 변경하거나 게임에 입력을 보내지 않았습니다.
'@
try {
    $releases = Invoke-RestMethod -Uri ($api + '?per_page=100') -Headers $headers
    $release = $releases | Where-Object tag_name -eq $Tag | Select-Object -First 1
    if (-not $release) {
        $body = @{ tag_name = $Tag; target_commitish = $Commit; name = 'HD2 Stratagem Hotkeys 0.1.4-test (list-key overlay and loadout fix)';
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
