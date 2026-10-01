param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys',
    [string]$Tag = 'stratagem-hotkeys-0.1.7-test'
)
$ErrorActionPreference = 'Stop'
$AssetPath = (Resolve-Path -LiteralPath $AssetPath).Path
$assetName = [IO.Path]::GetFileName($AssetPath)
if ($assetName -ne 'HD2-Stratagem-Hotkeys-0.1.7-test.zip') { throw 'Unexpected addon package name.' }
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
## HD2 Stratagem Hotkeys 0.1.7-test

수동 Alt + 방향키 입력은 정상인데 모드의 자동 커맨드는 작동하지 않는 문제를 대상으로, 방향키 전송 경로와 게임 입력 확인 과정을 변경한 테스트 빌드입니다. 실제 원인과 인게임 작동 여부는 새 빌드로 확인해야 합니다.

- 목록 열기 키의 기존 전송 방식은 유지하고, 커맨드 방향키는 게임 설정에서 읽은 가상 키값으로 명시적으로 전송합니다. 방향키·숫자패드·숫자열을 구분하며 WASD로 강제하지 않습니다.
- 방향키를 보낸 뒤 게임 내부에서 해당 방향 입력이 감지된 것을 확인해야 다음 키로 넘어갑니다. Windows 전송 성공만으로 완료 처리하지 않습니다.
- 같은 방향을 연속 입력할 때 이전 입력 상태가 해제된 것을 확인하고 다시 누릅니다. 한 프레임만 감지되는 입력도 보존합니다.
- 누르기/떼기의 기존 최소 15ms 또는 30ms 설정을 유지합니다. 입력 감지나 해제 확인이 250ms 안에 되지 않으면 나머지 키를 보내지 않고 중단합니다. 불확실한 커맨드를 자동 재전송하지 않습니다.
- 게임 입력 객체 교체, 다른 방향 입력 충돌, 읽기 실패, 장비/키 설정 변경, 발사·채팅·포커스 상실 시 취소하고 모드가 누른 키를 해제합니다.
- 각 방향의 게임 감지와 실패한 단계·방향·실제 키값을 로그에 기록합니다. `command-input-observed; game-result-unverified`는 방향 입력이 감지됐다는 뜻이며 실제 호출 성공을 뜻하지 않습니다.
- 원형 메뉴의 선택 보존, 목록 닫힘 대기, 목록 키 재진입, 숫자열 1~4 단축키와 안전한 Lua-only 패키지를 유지했습니다. 조준·투척은 수동입니다.

기존 로그에는 방향키 값 37·38·39·40의 Windows 전송 기록이 있었습니다. 이 기록만으로 게임 수신을 확정할 수 없어 전송 호환성 변경과 읽기 전용 게임 입력 확인을 함께 적용했습니다. 실제 게임 메모리를 변경하거나 내부 입력 함수를 직접 호출하지 않습니다.

### 설치

게임을 종료하고 Arsenal에서 이전 버전을 교체한 뒤 **원형 오버레이 ON/OFF를 체크**하고 반드시 Purge / Deploy 하세요. 이전 옵션 파일과 Icons 파일이 남지 않도록 해야 합니다. Bingus Shared Loader v18 / API 1과 함께 재시작하세요. 기본 우선순위에서는 Shared Loader를 맨 아래에 놓으세요.
인게임 설정 메뉴는 추가하지 않았습니다. Mod Options Menu와 Mod Bindings Menu는 필요하지 않습니다.
자동재장전은 기존 HD2 Auto Reload 0.3.28-test를 유지하면 됩니다. 이번 수정으로 자동재장전 모드를 교체할 필요는 없습니다. 헬퍼의 동일 기능을 동시에 켜지 마세요.
로그: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\hd2_helper_stratagem_hotkeys.log`

624개 LuaJIT 검사와 최소 크기·Lua-only 패키지 검사를 통과했습니다. Windows 입력 필드, 입력 지연/누락/한 프레임 감지, 같은 방향 반복, 30FPS의 12단계 입력, 키 해제 실패, 게임 입력 객체 교체와 기존 안전 취소를 검사했습니다. 실제 커맨드 수신은 인게임 검증이 필요합니다. 설치된 게임 모드 파일을 자동 변경하거나 게임에 입력을 보내지 않았습니다.
'@
try {
    $releases = Invoke-RestMethod -Uri ($api + '?per_page=100') -Headers $headers
    $release = $releases | Where-Object tag_name -eq $Tag | Select-Object -First 1
    if (-not $release) {
        $body = @{ tag_name = $Tag; target_commitish = $Commit; name = 'HD2 Stratagem Hotkeys 0.1.7-test (direction input and game observation)';
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
