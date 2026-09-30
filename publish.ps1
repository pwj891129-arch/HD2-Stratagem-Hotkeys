param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys',
    [string]$Tag = 'stratagem-hotkeys-0.1.2-test'
)
$ErrorActionPreference = 'Stop'
$AssetPath = (Resolve-Path -LiteralPath $AssetPath).Path
$assetName = [IO.Path]::GetFileName($AssetPath)
if ($assetName -ne 'HD2-Stratagem-Hotkeys-0.1.2-test.zip') { throw 'Unexpected addon package name.' }
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
## HD2 Stratagem Hotkeys 0.1.2-test

게임 시작 충돌의 의심 리소스를 제외한 진단용 테스트 버전입니다.

- 0.1.1-test에 추가한 아이콘용 재질 패키지를 제거했습니다. 이번 배포에는 Lua 리소스만 포함합니다.
- 원형 메뉴는 임시로 아이콘 대신 이름·슬롯 번호·사용 가능 상태를 표시합니다. 마우스 방향 선택과 버튼 해제 시 커맨드 입력은 유지했습니다.
- 게임 시작 단계의 `BOOT platform-init`, `BOOT platform-ready`, `START` 로그를 추가했습니다.
- 원형 메뉴와 숫자열 조합키를 각각 켜고 끄는 아스날 옵션, F6 선택, 공용/임무 표시, 메뉴 크기와 입력 간격 옵션을 유지했습니다.
- 게임에 저장된 목록 열기 키와 방향키를 읽는 기존 방식은 유지합니다. 커맨드 입력만 자동이고 조준·투척은 수동입니다.

최근 충돌 덤프 두 개는 같은 메모리 접근 오류를 기록했으며, 새 모드 로그가 생성되지 않았습니다. 아이콘 재질이 유력한 의심 대상이지만 네이티브 호출 경로가 완전히 확인되지 않아 원인을 확정한 것은 아닙니다. 실제 게임에서 시작 충돌이 해결됐는지는 재검증이 필요합니다.

### 설치

게임을 종료하고 Arsenal에서 기존 0.1.1-test를 교체한 뒤 반드시 Purge / Deploy 하세요. Purge를 생략하면 이전 Icons 패키지가 남을 수 있습니다. 필요한 기능의 체크박스를 확인하고 Bingus Shared Loader v18 / API 1과 함께 재시작하세요. 기본 우선순위에서는 Shared Loader를 맨 아래에 놓으세요.
인게임 설정 메뉴는 추가하지 않았습니다. Mod Options Menu와 Mod Bindings Menu는 필요하지 않습니다.
자동재장전 모드도 함께 사용한다면 HD2 Auto Reload 0.3.25-test 이상을 사용하세요. 헬퍼의 동일 기능을 동시에 켜지 마세요.
로그: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\hd2_helper_stratagem_hotkeys.log`

319개 LuaJIT 기능 검사와 Lua-only 패키지 검사를 통과했습니다. 실제 게임 시작, 텍스트 렌더링, 카메라/커서 제어, 호출 공 준비 및 멀티플레이는 인게임 검증이 필요합니다. 이름은 게임의 디버그 명칭을 사용합니다. 설치된 게임 모드 파일을 자동 변경하거나 게임에 입력을 보내지 않았습니다.
'@
try {
    $releases = Invoke-RestMethod -Uri ($api + '?per_page=100') -Headers $headers
    $release = $releases | Where-Object tag_name -eq $Tag | Select-Object -First 1
    if (-not $release) {
        $body = @{ tag_name = $Tag; target_commitish = $Commit; name = 'HD2 Stratagem Hotkeys 0.1.2-test (startup isolation)';
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
