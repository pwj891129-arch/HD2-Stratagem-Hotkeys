$ErrorActionPreference = 'Stop'
$repository = 'pwj891129-arch/HD2-Stratagem-Hotkeys'
$credentialLines = "protocol=https`nhost=github.com`n`n" | git credential fill
if ($LASTEXITCODE -ne 0) { throw 'GitHub authentication is unavailable.' }
$credential = @{}
foreach ($line in $credentialLines) {
    $parts = $line.Split('=', 2)
    if ($parts.Length -eq 2) { $credential[$parts[0]] = $parts[1] }
}
if (!$credential['password']) { throw 'GitHub authentication is unavailable.' }
$headers = @{ Authorization = 'Bearer ' + $credential['password']; Accept = 'application/vnd.github+json';
    'User-Agent' = 'HD2-Stratagem-Hotkeys-Publish'; 'X-GitHub-Api-Version' = '2022-11-28' }
try {
    $user = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $headers
    if ($user.login -ne 'pwj891129-arch') { throw 'Authenticated GitHub account differs from the target owner.' }
    $repo = $null
    try { $repo = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository" -Headers $headers }
    catch { if ([int]$_.Exception.Response.StatusCode -ne 404) { throw } }
    if (!$repo) {
        $body = @{name = 'HD2-Stratagem-Hotkeys'; private = $false; auto_init = $false;
            description = 'Experimental Helldivers 2 equipped-slot command hotkeys for Bingus Shared Loader.'} | ConvertTo-Json
        $repo = Invoke-RestMethod -Method Post -Uri 'https://api.github.com/user/repos' -Headers $headers -ContentType 'application/json' -Body $body
    }
    if ($repo.full_name -ne $repository) { throw 'Unexpected repository identity.' }
    Write-Output $repo.html_url
} finally {
    $headers.Clear(); $credential.Clear(); $credentialLines = $null
}
