param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys',
    [string]$Tag = 'stratagem-hotkeys-0.1.9-test'
)
$ErrorActionPreference = 'Stop'
$AssetPath = (Resolve-Path -LiteralPath $AssetPath).Path
$assetName = [IO.Path]::GetFileName($AssetPath)
if ($assetName -ne 'HD2-Stratagem-Hotkeys-0.1.9-test.zip') { throw 'Unexpected addon package name.' }
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
## HD2 Stratagem Hotkeys 0.1.9-test

원형 스트라타젬 메뉴에 게임 원본 아이콘을 표시하는 테스트 빌드입니다.

- 게임의 스트라타젬 정의에서 읽은 아이콘을 원형 메뉴에 표시합니다. 번호는 위쪽, 이름과 사용 가능 상태/대기시간은 아래쪽에 표시합니다.
- 사용할 수 없는 스트라타젬은 아이콘을 어둡게 표시합니다. 공용/임무 스트라타젬도 해당 아이콘을 표시합니다.
- 이미 게임에 로드된 기본 이미지 재질과 텍스처만 사용합니다. 별도의 아이콘 파일, 복사된 재질, 셰이더 또는 바이너리 GUI 리소스를 패키지에 추가하지 않습니다.
- 아이콘마다 독립된 모드 소유 GUI와 재질 인스턴스를 사용해 다른 아이콘이나 HUD+의 이미지를 덮어쓰지 않도록 구성했습니다.
- 마우스 이동에 따른 다시 그리기는 GUI와 변경되지 않은 이미지 바인딩을 재사용합니다. 메뉴 종료와 이미지 자원 소실 시 아이콘 GUI를 해제해 오래된 핸들이 남지 않도록 했습니다.
- 아이콘 자원이나 표시 API를 사용할 수 없으면 이름 표시로 돌아갑니다. 실제 메뉴 활성 상태 확인, 개인 슬롯 1~4 번호 매칭과 기존 커맨드 입력 동작은 유지합니다.
- 1~16개 항목과 작은 화면/큰 메뉴 설정에서도 아이콘의 가로세로 비율을 유지하고 서로 겹치지 않도록 크기를 제한했습니다.

로그의 `OVERLAY icons=4/4`는 아이콘 그리기 호출이 네 개 모두 완료됐다는 뜻입니다. 일부만 표시되거나 0/4라면 이미지 자원/API 확인이 필요합니다. 이 로그만으로 실제 화면 렌더링이나 스트라타젬 호출 성공을 확정할 수는 없습니다.

### 설치

게임을 종료하고 Arsenal에서 이전 버전을 교체한 뒤 **원형 오버레이 ON/OFF를 체크**하고 반드시 Purge / Deploy 하세요. 이전 옵션 파일과 Icons 파일이 남지 않도록 해야 합니다. Bingus Shared Loader v18 / API 1과 함께 재시작하세요. 기본 우선순위에서는 Shared Loader를 맨 아래에 놓으세요.
인게임 설정 메뉴는 추가하지 않았습니다. Mod Options Menu와 Mod Bindings Menu는 필요하지 않습니다.
자동재장전은 기존 HD2 Auto Reload 0.3.28-test를 유지하면 됩니다. 이번 수정으로 자동재장전 모드를 교체할 필요는 없습니다. 헬퍼의 동일 기능을 동시에 켜지 마세요.
로그: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\hd2_helper_stratagem_hotkeys.log`

3,524개 LuaJIT 검사와 최소 크기·Lua-only 패키지 검사를 통과했습니다. 아이콘별 독립 이미지, 이미지 교체/자원 소실/복구, GUI·재질·바인딩·그리기 실패 시 이름 표시, 메뉴 종료/월드 교체 정리와 기존 입력 동작을 모의 검사했습니다. 320x240·1280x720·3840x2160에서 1~16개 아이콘의 화면 범위와 서로 겹치지 않는 배치를 검사했습니다. 실제 게임 아이콘 표시와 커맨드 수신은 인게임 검증이 필요합니다. 설치된 모드 파일을 자동 변경하거나 게임에 입력을 보내지 않았습니다.
'@
try {
    $releases = Invoke-RestMethod -Uri ($api + '?per_page=100') -Headers $headers
    $release = $releases | Where-Object tag_name -eq $Tag | Select-Object -First 1
    if (-not $release) {
        $body = @{ tag_name = $Tag; target_commitish = $Commit; name = 'HD2 Stratagem Hotkeys 0.1.9-test (native stratagem icons)';
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
