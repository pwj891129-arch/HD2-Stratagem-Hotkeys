param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../scratch')
)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HD2SHReference {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint rights, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadProcessMemory(IntPtr process, IntPtr address,
        byte[] buffer, UIntPtr size, out UIntPtr actual);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);
}
'@
$game = Get-Process -Name helldivers2 | Select-Object -First 1
$module = $game.Modules | Where-Object { $_.ModuleName -eq 'game.dll' }
if (!$module) { throw 'game.dll is unavailable.' }
$process = [HD2SHReference]::OpenProcess(0x410, $false, $game.Id)
if ($process -eq [IntPtr]::Zero) {
    throw "Read-only process access denied: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}
try {
    $image = New-Object byte[] $module.ModuleMemorySize
    $total = 0
    for ($offset = 0; $offset -lt $image.Length; $offset += 65536) {
        $size = [Math]::Min(65536, $image.Length - $offset)
        $part = New-Object byte[] $size
        $actual = [UIntPtr]::Zero
        $ok = [HD2SHReference]::ReadProcessMemory($process,
            [IntPtr]($module.BaseAddress.ToInt64() + $offset), $part, [UIntPtr]$size, [ref]$actual)
        if ($ok -and $actual.ToUInt64() -eq $size) {
            [Array]::Copy($part, 0, $image, $offset, $size)
            $total += $size
        }
    }
    if ($total -eq 0) {
        throw "No module bytes readable: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'game-module.bin'), $image)
    [pscustomobject]@{
        Base = $module.BaseAddress.ToInt64()
        Size = $image.Length
        Readable = $total
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'reference.json') -Encoding UTF8
    foreach ($range in @(
        @{ Name = 'stratagem-settings'; Rva = 0x348e8f8; Size = 80280 },
        @{ Name = 'loadouts'; Rva = 0x347ce50; Size = 0x2d204 },
        @{ Name = 'players'; Rva = 0x3326468; Size = 0x500 },
        @{ Name = 'ui'; Rva = 0x347ce28; Size = 17080 }
    )) {
        $address = [BitConverter]::ToInt64($image, $range.Rva)
        if ($address -lt 65536) { continue }
        $bytes = New-Object byte[] $range.Size
        $actual = [UIntPtr]::Zero
        if ([HD2SHReference]::ReadProcessMemory($process, [IntPtr]$address,
            $bytes, [UIntPtr]$bytes.Length, [ref]$actual) -and $actual.ToUInt64() -eq $bytes.Length) {
            [IO.File]::WriteAllBytes((Join-Path $OutputDirectory "$($range.Name).bin"), $bytes)
            Write-Output "Reference $($range.Name): $($bytes.Length) bytes"
        }
    }
    $ownerAddress = [BitConverter]::ToInt64($image, 0x347cf18)
    $owner = New-Object byte[] 686824
    $actual = [UIntPtr]::Zero
    if ($ownerAddress -ge 65536 -and [HD2SHReference]::ReadProcessMemory($process,
        [IntPtr]$ownerAddress, $owner, [UIntPtr]$owner.Length, [ref]$actual)) {
        $bindingsAddress = [BitConverter]::ToInt64($owner, 686800)
        $capacity = [BitConverter]::ToUInt32($owner, 686808)
        if ($capacity -eq 256 -and $bindingsAddress -ge 65536) {
            $bindings = New-Object byte[] (328 * 256)
            if ([HD2SHReference]::ReadProcessMemory($process, [IntPtr]$bindingsAddress,
                $bindings, [UIntPtr]$bindings.Length, [ref]$actual)) {
                [IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'bindings.bin'), $bindings)
                Write-Output "Reference live input bindings: $($bindings.Length) bytes"
            }
        }
    }
    Write-Output "Read-only module reference: $total / $($image.Length) bytes. No game state was changed."
} finally {
    [HD2SHReference]::CloseHandle($process) | Out-Null
}
