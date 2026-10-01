param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys',
    [string]$Tag = 'stratagem-hotkeys-0.1.8-test'
)
$ErrorActionPreference = 'Stop'
$AssetPath = (Resolve-Path -LiteralPath $AssetPath).Path
$assetName = [IO.Path]::GetFileName($AssetPath)
if ($assetName -ne 'HD2-Stratagem-Hotkeys-0.1.8-test.zip') { throw 'Unexpected addon package name.' }
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
## HD2 Stratagem Hotkeys 0.1.8-test

캐릭터의 실제 스트라타젬 메뉴 활성 상태로 원형 오버레이를 제한하고, 원형 메뉴의 번호를 개인 장착 슬롯 핫키와 맞춘 테스트 빌드입니다.

- 목록 열기 키를 눌렀다는 사실만으로 오버레이를 열지 않습니다. 캐릭터의 실제 게임 메뉴가 활성화된 것을 확인한 뒤 표시합니다.
- 게임 메뉴 활성화 확인은 최대 350ms만 기다립니다. 확인되지 않거나 읽을 수 없으면 원형 메뉴와 마우스 제어를 활성화하지 않습니다.
- 키를 누르는 중 실제 메뉴가 닫히거나 캐릭터가 교체되면 선택을 취소합니다. 입력 중에도 메뉴 비활성화·캐릭터 변경이 확인되면 남은 커맨드를 중단하고 모드가 누른 키를 해제합니다.
- 정상적으로 목록 키를 놓을 때는 마지막 선택을 유지합니다. 실제 메뉴 닫힘과 재활성화를 확인한 뒤 커맨드를 전송합니다.
- 숫자열 1~4 핫키는 개인 장착 슬롯 1~4와 매칭됩니다. 공용/임무 항목이 섞여도 원형 메뉴의 개인 번호는 변하지 않습니다.
- 공용/임무 스트라타젬에는 숫자 핫키 번호를 표시하지 않습니다. 사용 가능 상태일 때 원형 메뉴에서 마우스로 선택할 수 있습니다.
- 숫자 핫키도 실제 캐릭터 메뉴가 활성화된 경우에만 방향 커맨드를 보냅니다. 기존 게임 설정 키 매핑, 방향 입력 감지 확인, 15/30ms 설정과 조준·투척 수동 방식을 유지합니다.

고정 해시로 검증하는 게임 버전의 실제 메뉴 활성 조회 코드를 확인해 읽기 전용 판독에 연결했습니다. 게임의 사용 가능 조건을 임의로 재현하거나 내부 함수를 호출하지 않습니다. 실제 커맨드 호출 성공은 별도 인게임 확인이 필요합니다.

### 설치

게임을 종료하고 Arsenal에서 이전 버전을 교체한 뒤 **원형 오버레이 ON/OFF를 체크**하고 반드시 Purge / Deploy 하세요. 이전 옵션 파일과 Icons 파일이 남지 않도록 해야 합니다. Bingus Shared Loader v18 / API 1과 함께 재시작하세요. 기본 우선순위에서는 Shared Loader를 맨 아래에 놓으세요.
인게임 설정 메뉴는 추가하지 않았습니다. Mod Options Menu와 Mod Bindings Menu는 필요하지 않습니다.
자동재장전은 기존 HD2 Auto Reload 0.3.28-test를 유지하면 됩니다. 이번 수정으로 자동재장전 모드를 교체할 필요는 없습니다. 헬퍼의 동일 기능을 동시에 켜지 마세요.
로그: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\hd2_helper_stratagem_hotkeys.log`

903개 LuaJIT 검사와 최소 크기·Lua-only 패키지 검사를 통과했습니다. 공용 항목이 섞인 번호 매칭, 실제 메뉴가 비활성인데 Alt 입력만 있는 상태, 지연 활성화, 시간 제한, 캐릭터 없음/교체, 입력 중 메뉴 닫힘과 기존 입력 경로를 모의 검사했습니다. 메뉴 상태의 실제 게임 판독 및 커맨드 수신은 인게임 검증이 필요합니다. 설치된 게임 모드 파일을 자동 변경하거나 게임에 입력을 보내지 않았습니다.
'@
try {
    $releases = Invoke-RestMethod -Uri ($api + '?per_page=100') -Headers $headers
    $release = $releases | Where-Object tag_name -eq $Tag | Select-Object -First 1
    if (-not $release) {
        $body = @{ tag_name = $Tag; target_commitish = $Commit; name = 'HD2 Stratagem Hotkeys 0.1.8-test (native menu gate and slot numbers)';
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
