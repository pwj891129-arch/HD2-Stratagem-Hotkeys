param([string]$OutputDirectory = (Join-Path $PSScriptRoot '../scratch/icon-reference'))
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HD2SHIconReference {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint rights, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr actual);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);
}
'@
$game = Get-Process -Name helldivers2 | Select-Object -First 1
$modules = @($game.Modules)
$module = $modules | Where-Object ModuleName -eq 'game.dll'
$exe = $modules | Where-Object ModuleName -eq 'helldivers2.exe'
if (!$module -or (Get-FileHash -LiteralPath $module.FileName -Algorithm SHA256).Hash.ToLowerInvariant() -ne
    '2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e') { throw 'Unsupported game module.' }
if (!$exe -or (Get-FileHash -LiteralPath $exe.FileName -Algorithm SHA256).Hash.ToLowerInvariant() -ne
    'f5fee03dcfdb2e553a4752c283590950ac13316b376d8196aa556ff0400d5f06') { throw 'Unsupported executable.' }
$process = [HD2SHIconReference]::OpenProcess(0x410, $false, $game.Id)
if ($process -eq [IntPtr]::Zero) { throw 'Read-only process access denied.' }
function Read-Bytes([long]$Address, [int]$Size) {
    if ($Address -lt 65536 -or $Address -ge 140737488355328 -or $Size -lt 1 -or $Size -gt 262144) { throw 'Invalid read range.' }
    $bytes = New-Object byte[] $Size
    $actual = [UIntPtr]::Zero
    if (-not [HD2SHIconReference]::ReadProcessMemory($process, [IntPtr]$Address, $bytes,
        [UIntPtr]$Size, [ref]$actual) -or $actual.ToUInt64() -ne $Size) { throw 'Incomplete read-only capture.' }
    return ,$bytes
}
function Read-Pointer([long]$Address) { [BitConverter]::ToInt64((Read-Bytes $Address 8), 0) }
try {
    $base = $module.BaseAddress.ToInt64()
    $root = Read-Pointer ($base + 0x3326308)
    $gui = Read-Pointer ($root + 0xd0)
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $out = [ordered]@{gameBase = $base; modules = @($modules | ForEach-Object {
        @{name = $_.ModuleName; base = $_.BaseAddress.ToInt64(); size = $_.ModuleMemorySize}
    }); queries = @()}
    foreach ($item in @(@{name = 'texture'; offset = 0x348}, @{name = 'material'; offset = 0x350})) {
        $address = Read-Pointer ($gui + $item.offset)
        [IO.File]::WriteAllBytes((Join-Path $OutputDirectory ($item.name + '.bin')), (Read-Bytes $address 1024))
        $owner = $modules | Where-Object { $address -ge $_.BaseAddress.ToInt64() -and
            $address -lt $_.BaseAddress.ToInt64() + $_.ModuleMemorySize } | Select-Object -First 1
        $query = @{name = $item.name; address = $address; module = $owner.ModuleName;
            rva = $address - $owner.BaseAddress.ToInt64()}
        $out.queries += $query
        $query | ConvertTo-Json -Compress
    }
    foreach ($item in @(@{name = 'primary-colors'; address = $base + 0x331b610; size = 5 * 16},
        @{name = 'secondary-color'; address = $base + 0x21e89e0; size = 16},
        @{name = 'tertiary-color'; address = $base + 0x21e8a10; size = 16})) {
        [IO.File]::WriteAllBytes((Join-Path $OutputDirectory ($item.name + '.bin')), (Read-Bytes $item.address $item.size))
    }
    $engine = Read-Pointer ($exe.BaseAddress.ToInt64() + 0x1a10238)
    $manager = Read-Pointer ($engine + 0x3f8)
    $header = Read-Bytes ($manager + 0x2a0) 32
    $rows = [BitConverter]::ToInt64($header, 0)
    $capacity = [BitConverter]::ToUInt32($header, 20)
    if ($capacity -lt 1 -or $capacity -gt 10922) { throw 'Atlas capture capacity out of bounds.' }
    [IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'atlas-rows.bin'), (Read-Bytes $rows ($capacity * 24)))
    $out.atlas = @{engine = $engine; manager = $manager; rows = $rows; capacity = $capacity;
        count = [BitConverter]::ToUInt32($header, 16)}
    $settings = Read-Pointer ($base + 0x348e8f8)
    [IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'settings.bin'), (Read-Bytes $settings 80280))
    $definitions = Read-Bytes ($base + 0x37cb600) 1200
    [IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'definitions.bin'), $definitions)
    $out.settings = $settings
    $out.samples = @()
    foreach ($kind in @(1, 28, 50, 56, 88, 101, 113, 121, 124, 126, 145)) {
        $descriptor = Read-Pointer ($base + 0x37cb600 + $kind * 8)
        $resource = Read-Bytes ($descriptor + 176) 8
        $key = [BitConverter]::ToUInt64($resource, 0)
        $node = [BitConverter]::ToUInt32($resource, 4) % $capacity
        for ($probe = 0; $probe -lt 128; $probe++) {
            if ($node -ge 1048576) { break }
            $entry = Read-Bytes ($rows + $node * 24) 24
            if ([BitConverter]::ToUInt32($entry, 16) -eq 0xfffffffe) { break }
            if ([BitConverter]::ToUInt64($entry, 0) -eq $key) {
                $payload = Read-Pointer ($rows + $node * 24 + 8)
                $bytes = Read-Bytes $payload 40
                [IO.File]::WriteAllBytes((Join-Path $OutputDirectory ("atlas-payload-$node.bin")), $bytes)
                $sample = @{kind = $kind; node = $node; payload = $payload;
                    texture = $key.ToString('x16'); atlas = ([BitConverter]::ToUInt64($bytes, 8)).ToString('x16');
                    uv = @([BitConverter]::ToSingle($bytes, 24), [BitConverter]::ToSingle($bytes, 28),
                        [BitConverter]::ToSingle($bytes, 32), [BitConverter]::ToSingle($bytes, 36))}
                $out.samples += $sample
                $sample | ConvertTo-Json -Compress
                break
            }
            $node = [BitConverter]::ToUInt32($entry, 16)
        }
    }
    $out | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'reference.json') -Encoding UTF8
    'Read-only icon code/data capture complete. No native game function invoked.'
} finally { [HD2SHIconReference]::CloseHandle($process) | Out-Null }
