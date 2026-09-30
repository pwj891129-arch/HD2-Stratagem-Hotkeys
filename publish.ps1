param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys',
    [string]$Tag = 'stratagem-hotkeys-0.1.1-test'
)
$ErrorActionPreference = 'Stop'
$AssetPath = (Resolve-Path -LiteralPath $AssetPath).Path
$assetName = [IO.Path]::GetFileName($AssetPath)
if ($assetName -ne 'HD2-Stratagem-Hotkeys-0.1.1-test.zip') { throw 'Unexpected addon package name.' }
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
## HD2 Stratagem Hotkeys 0.1.1-test

원형 스트라타젬 메뉴와 아스날 전용 옵션을 추가한 테스트 버전입니다.

- 마우스 4번 버튼을 누르고 아이콘 방향으로 이동한 뒤 놓으면 커맨드를 입력합니다. 중앙에서 놓으면 취소합니다.
- 장착 아이콘, 잔여 횟수와 쿨다운을 게임에서 읽어 사용할 수 없는 항목을 어둡게 표시합니다. 확정 직전에 상태를 다시 확인합니다.
- 아스날에서 원형 메뉴와 숫자열 조합키를 각각 켜고 끌 수 있습니다.
- 아스날에서 F6 키 사용, 공용/임무 스트라타젬 포함, 메뉴 크기 100%/130%, 입력 간격 15ms/30ms를 설정할 수 있습니다.
- 게임에 저장된 목록 열기 키와 방향 입력 키를 읽습니다. HUD+나 헬퍼 프리셋은 필요하지 않습니다.
- 커맨드 입력만 자동입니다. 조준과 투척은 직접 하세요.
- 기존 목록 열기 키 + 숫자열 1~4도 별도 옵션으로 유지합니다. 이 방식에서는 목록 열기 키를 완료까지 누르세요.
- 숫자를 계속 눌러도 반복 호출하지 않으며, 숫자패드는 숫자열과 구분합니다.
- 방향 입력은 누르기/떼기 각각 선택한 간격 및 최소 1프레임을 유지합니다.
- 키 설정·장착값을 확인하지 못하면 추측하지 않고 입력을 보류합니다. 게임 메모리는 읽기만 하며 쿨다운이나 재머 제한을 해제하지 않습니다.

현재는 키보드의 목록 열기 Hold(누르고 있기), 방향 Press(누르기) 설정을 지원합니다. 토글/다른 트리거, 조합 방향키, 마우스·컨트롤러 전용 설정은 입력을 보류합니다.

### 설치

게임을 종료하고 Arsenal에 ZIP을 가져온 뒤 필요한 기능의 체크박스를 확인하고 Bingus Shared Loader v18 / API 1과 함께 Purge / Deploy 하세요. 옵션 변경 후에는 재배포와 게임 재시작이 필요합니다. 기본 우선순위에서는 Shared Loader를 맨 아래에 놓으세요.
인게임 설정 메뉴는 추가하지 않았습니다. Mod Options Menu와 Mod Bindings Menu는 필요하지 않습니다.
자동재장전 모드도 함께 사용한다면 HD2 Auto Reload 0.3.25-test로 교체하세요. 헬퍼의 동일 기능을 동시에 켜지 마세요.
로그: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\hd2_helper_stratagem_hotkeys.log`

현재 게임 빌드의 커맨드 정의 149개와 오프라인 검사를 확인했습니다. 실제 아이콘 렌더링, 카메라/커서 제어, 호출 공 준비, 멀티플레이는 인게임 검증이 필요합니다. 이름은 첫 버전에서 게임의 디버그 명칭을 사용합니다. 실행 중인 게임에 자동 설치하거나 입력을 보내지 않았습니다.
'@
try {
    $releases = Invoke-RestMethod -Uri ($api + '?per_page=100') -Headers $headers
    $release = $releases | Where-Object tag_name -eq $Tag | Select-Object -First 1
    if (-not $release) {
        $body = @{ tag_name = $Tag; target_commitish = $Commit; name = 'HD2 Stratagem Hotkeys 0.1.1-test';
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
