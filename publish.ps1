param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys',
    [string]$Tag = 'stratagem-hotkeys-0.1.0-test'
)
$ErrorActionPreference = 'Stop'
$AssetPath = (Resolve-Path -LiteralPath $AssetPath).Path
$assetName = [IO.Path]::GetFileName($AssetPath)
if ($assetName -ne 'HD2-Stratagem-Hotkeys-0.1.0-test.zip') { throw 'Unexpected addon package name.' }
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
## HD2 Stratagem Hotkeys 0.1.0-test

목록 열기 키 + 숫자열 1~4로 장착한 스트라타젬의 커맨드만 자동 입력하는 첫 테스트 버전입니다.

- 게임에 저장된 목록 열기 키와 방향 입력 키를 읽습니다. 키를 별도로 맞출 필요가 없습니다.
- 본인의 장착 4칸과 각 스트라타젬 커맨드를 게임 데이터에서 읽습니다. HUD+나 헬퍼 프리셋을 사용하지 않습니다.
- 커맨드 입력만 자동입니다. 조준과 투척은 직접 하세요.
- 목록 열기 키를 커맨드 완료까지 누르고 있어야 합니다. 키를 떼면 입력을 중단합니다.
- 숫자를 계속 눌러도 반복 호출하지 않으며, 숫자패드는 숫자열과 구분합니다.
- 방향 입력은 누르기/떼기 각각 최소 15ms 및 1프레임을 유지합니다.
- 키 설정·장착값을 확인하지 못하면 추측하지 않고 입력을 보류합니다. 게임 메모리는 읽기만 하며 쿨다운이나 재머 제한을 해제하지 않습니다.

현재는 키보드의 목록 열기 Hold(누르고 있기), 방향 Press(누르기) 설정을 지원합니다. 토글/다른 트리거, 조합 방향키, 마우스·컨트롤러 전용 설정은 입력을 보류합니다.

### 설치

게임을 종료하고 Arsenal에 ZIP을 가져온 뒤 Bingus Shared Loader v18 / API 1과 함께 활성화하여 Purge / Deploy 하세요. 기본 우선순위에서는 Shared Loader를 맨 아래에 놓으세요. Mod Bindings Menu는 필수가 아닙니다.
자동재장전 모드도 함께 사용한다면 HD2 Auto Reload 0.3.24-test 이상으로 교체하세요. 헬퍼의 같은 스트라타젬 조합키 기능을 동시에 켜지 마세요.
로그: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\hd2_helper_stratagem_hotkeys.log`

현재 게임 빌드의 커맨드 정의 149개와 오프라인 검사 60개를 확인했습니다. 실제 임무의 장착 순서, 호출 공 준비, 멀티플레이는 직접 테스트가 필요합니다. 실행 중인 게임에 자동 설치하거나 입력을 보내지 않았습니다.
'@
try {
    $releases = Invoke-RestMethod -Uri ($api + '?per_page=100') -Headers $headers
    $release = $releases | Where-Object tag_name -eq $Tag | Select-Object -First 1
    if (-not $release) {
        $body = @{ tag_name = $Tag; target_commitish = $Commit; name = 'HD2 Stratagem Hotkeys 0.1.0-test';
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
