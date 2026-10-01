param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys',
    [string]$Tag = 'stratagem-hotkeys-0.1.6-test'
)
$ErrorActionPreference = 'Stop'
$AssetPath = (Resolve-Path -LiteralPath $AssetPath).Path
$assetName = [IO.Path]::GetFileName($AssetPath)
if ($assetName -ne 'HD2-Stratagem-Hotkeys-0.1.6-test.zip') { throw 'Unexpected addon package name.' }
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
## HD2 Stratagem Hotkeys 0.1.6-test

원형 메뉴는 표시되지만 커맨드가 작동하지 않는 문제를 조사하고, 선택 확정과 목록 재진입의 입력 순서를 수정했습니다.

- 키를 놓는 순간 마우스 위치를 다시 읽지 않고, 누르고 있는 동안 마지막으로 강조된 항목을 확정합니다. 키를 놓을 때 커서가 중앙으로 돌아가 선택이 사라지는 흐름을 방지했습니다.
- 중앙 취소는 유지합니다. 키를 누른 채 중앙으로 이동한 뒤 놓으면 입력하지 않습니다.
- 마우스 제어를 복원한 뒤 기존 게임 목록이 닫히고 안정되는 것을 확인하고 목록 키를 다시 누릅니다. 물리 키를 놓은 프레임에서 바로 다시 누르지 않습니다.
- 목록 키를 새로 누른 후 게임 목록이 여러 프레임에 걸쳐 활성화된 것을 확인한 다음 방향키를 전송합니다.
- 대기 중 장비·키 설정 변경, 새 목록 키 누름, 발사·채팅·포커스 상실이 발생하면 취소하고 모드가 누른 키를 해제합니다.
- 선택 강조/확정/중앙 취소/사용 불가, 발사·채팅·포커스 취소, 목록 닫힘 대기, 목록 키 재입력 및 실제 방향키 값을 로그에 기록합니다.
- 입력 완료는 `command-sent; game-result-unverified`로 기록합니다. OS 입력 전송 완료를 게임의 호출 성공으로 간주하지 않습니다.
- 화면 API 수정, 안전한 옵션 패키지 크기, 게임 설정의 목록 키 및 숫자열 1~4 단축키를 유지했습니다. 조준·투척은 수동입니다.

0.1.5-test에서 인터페이스 표시는 사용자 테스트로 확인됐습니다. 로그에는 메뉴 열림 33회, 커맨드 전송 기록 2회와 목록 활성화 대기 실패 1회가 있었습니다. 이번 수정의 선택 보존과 입력 순서는 오프라인에서 검사했으며, 실제 게임에서 커맨드가 받아들여지는지는 새 빌드로 확인해야 합니다.

### 설치

게임을 종료하고 Arsenal에서 이전 버전을 교체한 뒤 **원형 오버레이 ON/OFF를 체크**하고 반드시 Purge / Deploy 하세요. 이전 옵션 파일과 Icons 파일이 남지 않도록 해야 합니다. Bingus Shared Loader v18 / API 1과 함께 재시작하세요. 기본 우선순위에서는 Shared Loader를 맨 아래에 놓으세요.
인게임 설정 메뉴는 추가하지 않았습니다. Mod Options Menu와 Mod Bindings Menu는 필요하지 않습니다.
자동재장전은 기존 HD2 Auto Reload 0.3.27-test 이상을 유지하면 됩니다. 이번 수정으로 자동재장전 모드를 교체할 필요는 없습니다. 헬퍼의 동일 기능을 동시에 켜지 마세요.
로그: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\hd2_helper_stratagem_hotkeys.log`

463개 LuaJIT 기능 검사와 최소 크기·Lua-only 패키지 검사를 통과했습니다. 키를 놓을 때 커서가 중앙으로 돌아가는 상황, 목록 닫힘 지연, 일시적인 목록 활성화, 대기 중 장비/키 설정 변경과 포커스 상실, 좌클릭 취소를 검사했습니다. 실제 커맨드 수신은 인게임 검증이 필요합니다. 설치된 게임 모드 파일을 자동 변경하거나 게임에 입력을 보내지 않았습니다.
'@
try {
    $releases = Invoke-RestMethod -Uri ($api + '?per_page=100') -Headers $headers
    $release = $releases | Where-Object tag_name -eq $Tag | Select-Object -First 1
    if (-not $release) {
        $body = @{ tag_name = $Tag; target_commitish = $Commit; name = 'HD2 Stratagem Hotkeys 0.1.6-test (radial command dispatch fix)';
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
