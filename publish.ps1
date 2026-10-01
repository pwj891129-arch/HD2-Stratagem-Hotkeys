param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys',
    [string]$Tag = 'stratagem-hotkeys-0.1.13-test'
)
$ErrorActionPreference = 'Stop'
$AssetPath = (Resolve-Path -LiteralPath $AssetPath).Path
$assetName = [IO.Path]::GetFileName($AssetPath)
if ($assetName -ne 'HD2-Stratagem-Hotkeys-0.1.13-test.zip') { throw 'Unexpected addon package name.' }
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
## HD2 Stratagem Hotkeys 0.1.13-test

일부 스트라타젬 아이콘이 빠지는 문제와 원형 메뉴를 닫아도 마우스 엄지버튼이 눌린 상태로 남는 문제를 수정하는 테스트 빌드입니다.

- 보급 팩 등 일부 아이콘이 이미지 조회 단계에서 누락되던 문제를 수정했습니다. 해시 버킷 수를 전체 행 수로 잘못 취급해 충돌로 뒤쪽에 배치된 아이콘을 거부하던 원인을 고쳤습니다.
- 원형 메뉴가 마우스를 잡는 동안 엄지버튼의 떼기 입력이 누락되는 경우를 처리했습니다. 메뉴 종료와 마우스 복원 후, 실제 버튼은 떼었지만 게임 동작이 계속 눌림 상태일 때 해당 버튼의 떼기 입력만 보완합니다.
- 스트라타젬을 선택하지 않고 중앙에서 닫아도 같은 해제 처리를 합니다. 취소 시 새 누르기나 커맨드 입력을 보내지 않습니다.
- 선택한 커맨드는 게임이 엄지버튼 해제를 감지한 뒤에만 같은 버튼을 다시 눌러 시작합니다. 해제 확인에 실패하면 재누르기나 방향 입력을 하지 않습니다.
- 실제로 누르고 있는 버튼은 해제하지 않고, 다른 프로그램이 활성화된 동안에도 보완 입력을 보내지 않습니다. 전송 실패 재시도는 최대 3회이며, 전송 성공 후 게임이 해제하지 않는 경우 입력을 반복하지 않습니다.
- 아이콘 조회의 순환 검사·읽기 횟수 제한·포인터와 UV 검사·반복 스냅샷 확인을 유지했습니다. 게임 메모리는 읽기 전용이며 내부 게임 함수를 호출하지 않습니다.
- 로그의 `INPUT mouse-release-replayed`와 `INPUT mouse-release-observed`로 보완 전송과 게임 해제 확인을 구분할 수 있습니다.
- **게임의 스트라타젬 열기 동작은 누르고 있기(Hold)로 설정해야 합니다.** Press/토글, 휠, 다른 마우스 버튼, 마우스 방향키와 컨트롤러 입력은 지원하지 않습니다.
- 기존 키보드/엄지버튼 + 숫자열 1~4, 개인 슬롯 번호, 채팅·캐릭터 메뉴 상태 검사와 별도 자동재장전 모드는 유지했습니다. Lua-only 패키지이며 게임 이미지·재질·셰이더·글꼴을 포함하지 않습니다.

방향 입력은 기존 키보드 설정(방향키/WASD 등)을 그대로 사용합니다. 조준과 투척은 수동입니다.

### 설치

게임을 종료하고 Arsenal에서 이전 버전을 교체한 뒤 **원형 오버레이 ON/OFF를 체크**하고 반드시 Purge / Deploy 하세요. 이전 옵션 파일과 Icons 파일이 남지 않도록 해야 합니다. Bingus Shared Loader v18 / API 1과 함께 재시작하세요. 기본 우선순위에서는 Shared Loader를 맨 아래에 놓으세요.
인게임 설정 메뉴는 추가하지 않았습니다. Mod Options Menu와 Mod Bindings Menu는 필요하지 않습니다.
자동재장전은 기존 HD2 Auto Reload 0.3.28-test를 유지하면 됩니다. 이번 수정으로 자동재장전 모드를 교체할 필요는 없습니다. 헬퍼의 동일 기능을 동시에 켜지 마세요.
로그: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\hd2_helper_stratagem_hotkeys.log`

3,955개 LuaJIT 검사와 최소 크기·Lua-only 패키지 검사를 통과했습니다. 양쪽 엄지버튼의 선택·중앙 취소, 누락된 해제, 포커스 해제, 전송 실패, 게임이 해제를 감지하지 않는 경우와 읽기 실패를 검사했습니다. 로컬 게임 코드 참조로 해시 버킷 계산과 충돌 링크 탐색도 독립 검증했습니다. 조사 중 게임이 종료되어 새 실행 중 스냅샷은 확보하지 못했으며, 이 빌드의 실제 아이콘 표시와 엄지버튼 동작은 인게임 확인이 필요합니다. 게임 입력을 보내거나 설치된 모드 파일을 변경하지 않았습니다.
'@
try {
    $releases = Invoke-RestMethod -Uri ($api + '?per_page=100') -Headers $headers
    $release = $releases | Where-Object tag_name -eq $Tag | Select-Object -First 1
    if (-not $release) {
        $body = @{ tag_name = $Tag; target_commitish = $Commit; name = 'HD2 Stratagem Hotkeys 0.1.13-test (missing icons and thumb release)';
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
