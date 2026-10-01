param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys',
    [string]$Tag = 'stratagem-hotkeys-0.1.11-test'
)
$ErrorActionPreference = 'Stop'
$AssetPath = (Resolve-Path -LiteralPath $AssetPath).Path
$assetName = [IO.Path]::GetFileName($AssetPath)
if ($assetName -ne 'HD2-Stratagem-Hotkeys-0.1.11-test.zip') { throw 'Unexpected addon package name.' }
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
## HD2 Stratagem Hotkeys 0.1.11-test

아이콘 그리기 호출은 성공하지만 화면에서는 보이지 않던 문제에 대응하는 테스트 빌드입니다.

- 게임의 원본 아이콘 색상 마스크와 이미지 묶음(아틀라스)의 영역을 반영하도록 표시 방식을 변경했습니다. 이미지 영역과 게임 팔레트를 함께 적용합니다.
- 아틀라스 좌표는 읽기 전용 메모리 조회로 확인합니다. 게임 내부 함수를 직접 호출하거나 메모리를 수정하지 않습니다. 잘못된 좌표, 읽기 실패, 자원 교체가 감지되면 이름 표시를 유지합니다.
- 아이콘별로 모드 소유 GUI와 재질 인스턴스를 분리해 같은 이미지 묶음에서도 영역과 색상이 서로 덮어써지지 않도록 했습니다. HUD+나 게임의 기존 재질은 변경하지 않습니다.
- 마우스 이동 시 기존 이미지 바인딩을 재사용하며 메뉴 종료와 자원 소실 시 모드 소유 아이콘 GUI를 정리합니다.
- 아이콘별 종류, 개인 슬롯, 이미지 묶음과 영역을 로그에 남깁니다. 표시 실패 원인은 같은 오류를 매 프레임 반복하지 않고 기록합니다.
- 개인 슬롯 번호, 메뉴 활성 조건과 커맨드 입력은 유지합니다. 커맨드 전송 시에는 이미지 판독을 생략합니다. 자동재장전 모드는 변경하지 않았습니다.
- 이름은 현재 게임의 개발용 영문 표기를 유지합니다. 이번에는 현지화 기능을 추가하지 않았습니다.
- Lua-only 패키지입니다. 게임의 이미지, 재질, 글꼴, 셰이더 또는 바이너리 GUI 리소스를 포함하지 않습니다.

로그의 `OVERLAY icons=4/4`는 그리기 호출이 도형 ID를 반환했다는 뜻이며 실제 화면 표시를 보장하지 않습니다. `OVERLAY icon-source ... atlas=... uv=...`는 적용한 이미지 영역을, `OVERLAY icon-fallback ... reason=...`는 실패 원인을 나타냅니다.

### 설치

게임을 종료하고 Arsenal에서 이전 버전을 교체한 뒤 **원형 오버레이 ON/OFF를 체크**하고 반드시 Purge / Deploy 하세요. 이전 옵션 파일과 Icons 파일이 남지 않도록 해야 합니다. Bingus Shared Loader v18 / API 1과 함께 재시작하세요. 기본 우선순위에서는 Shared Loader를 맨 아래에 놓으세요.
인게임 설정 메뉴는 추가하지 않았습니다. Mod Options Menu와 Mod Bindings Menu는 필요하지 않습니다.
자동재장전은 기존 HD2 Auto Reload 0.3.28-test를 유지하면 됩니다. 이번 수정으로 자동재장전 모드를 교체할 필요는 없습니다. 헬퍼의 동일 기능을 동시에 켜지 마세요.
로그: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\hd2_helper_stratagem_hotkeys.log`

3,713개 LuaJIT 검사와 최소 크기·Lua-only 패키지 검사를 통과했습니다. 게임의 130개 정의/110개 이미지 자원, 색상 마스크 재질, 팔레트와 아틀라스 조회 코드를 읽기 전용으로 검증했습니다. 아틀라스 충돌/잘못된 연결/좌표/교체 상태, 공용 아틀라스의 이미지별 영역·색상 분리, 표시 실패 시 이름 유지, GUI 정리와 기존 입력 동작을 검사했습니다. 320x240·1280x720·3840x2160에서 1~16개 아이콘의 배치를 검사했습니다. 게임 종료로 실제 아틀라스 데이터와 화면 표시는 아직 검증하지 못했습니다. 설치된 모드 파일을 자동 변경하거나 게임에 입력을 보내지 않았습니다.
'@
try {
    $releases = Invoke-RestMethod -Uri ($api + '?per_page=100') -Headers $headers
    $release = $releases | Where-Object tag_name -eq $Tag | Select-Object -First 1
    if (-not $release) {
        $body = @{ tag_name = $Tag; target_commitish = $Commit; name = 'HD2 Stratagem Hotkeys 0.1.11-test (atlas and RGB-mask icons)';
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
