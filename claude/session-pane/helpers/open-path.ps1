# 폴더나 파일을 기본 프로그램으로 열고 그 창을 보이게 하고 앞으로 가져온다.
# 왜 이런 게 필요한가: Claude Code가 뒤에서 명령을 돌리면 "창 숨김" 시작 설정이
# 물려 내려가 탐색기·일부 프로그램이 창을 만들고도 보여 주지 않고, Windows의 앞 창
# 잠금 때문에 앞으로도 못 온다. 폴더는 이미 열린 창이 있으면 그 창을 쓴다.
param([Parameter(Mandatory = $true)][string]$Path)

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint c);
  public static List<IntPtr> TopWindows() {
    var list = new List<IntPtr>();
    EnumWindows((h, l) => { if (GetWindow(h, 4) == IntPtr.Zero) list.Add(h); return true; }, IntPtr.Zero);
    return list;
  }
  public static string Title(IntPtr h) {
    int n = GetWindowTextLength(h); var sb = new StringBuilder(n + 1); GetWindowText(h, sb, n + 1); return sb.ToString();
  }
  public static uint Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return p; }
}
"@

function Bring-Front([IntPtr]$h) {
  if (-not [W]::IsWindowVisible($h)) {
    [W]::ShowWindow($h, 5) | Out-Null
    [W]::ShowWindow($h, 1) | Out-Null
    Start-Sleep -Milliseconds 200
  }
  if ([W]::IsIconic($h)) { [W]::ShowWindow($h, 9) | Out-Null }
  [W]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
  [W]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  $fg = [W]::GetForegroundWindow()
  $fgThread = [W]::GetWindowThreadProcessId($fg, [ref]([uint32]0))
  $me = [W]::GetCurrentThreadId()
  $attached = $false
  if ($fgThread -ne 0 -and $fgThread -ne $me) { $attached = [W]::AttachThreadInput($me, $fgThread, $true) }
  [W]::BringWindowToTop($h) | Out-Null
  [W]::SetForegroundWindow($h) | Out-Null
  if ($attached) { [W]::AttachThreadInput($me, $fgThread, $false) | Out-Null }
  Start-Sleep -Milliseconds 150
  Write-Output ("hwnd={0} title='{1}' visible={2} foreground={3}" -f $h, [W]::Title($h), [W]::IsWindowVisible($h), ([W]::GetForegroundWindow() -eq $h))
}

$target = ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\')
if (-not (Test-Path -LiteralPath $target)) { Write-Output "not-found"; exit 3 }

if (Test-Path -LiteralPath $target -PathType Container) {
  # ---- 폴더: 탐색기 ----
  $sh = New-Object -ComObject Shell.Application
  function Find-Win {
    foreach ($w in @($sh.Windows())) {
      try {
        $u = $w.LocationURL
        if ($u) {
          $p = [Uri]::UnescapeDataString(([Uri]$u).LocalPath).TrimEnd('\')
          if ($p -ieq $target) { return $w }
        }
      } catch {}
    }
    return $null
  }
  $w = Find-Win
  if (-not $w) {
    $sh.Open($target)
    for ($i = 0; $i -lt 40 -and -not $w; $i++) { Start-Sleep -Milliseconds 100; $w = Find-Win }
  }
  if (-not $w) { Write-Output "no-window"; exit 2 }
  $h = [IntPtr]$w.HWND
  if (-not [W]::IsWindowVisible($h)) { try { $w.Visible = $true } catch {} }
  Bring-Front $h
  exit 0
}

# ---- 파일: 기본 프로그램 ----
$name = [System.IO.Path]::GetFileNameWithoutExtension($target)
$before = @{}
foreach ($h in [W]::TopWindows()) { $before[[string]$h] = $true }
Start-Process -FilePath $target -WindowStyle Normal
# 제목에 파일 이름이 들어간 창, 없으면 새로 생긴 창을 3초까지 기다림
$found = [IntPtr]::Zero
for ($i = 0; $i -lt 30 -and $found -eq [IntPtr]::Zero; $i++) {
  Start-Sleep -Milliseconds 100
  $new = [IntPtr]::Zero
  foreach ($h in [W]::TopWindows()) {
    $t = [W]::Title($h)
    if ($t -and $t.IndexOf($name, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $found = $h; break }
    if ($t -and -not $before.ContainsKey([string]$h) -and $new -eq [IntPtr]::Zero) { $new = $h }
  }
  if ($found -eq [IntPtr]::Zero -and $new -ne [IntPtr]::Zero -and $i -ge 10) { $found = $new }
}
if ($found -eq [IntPtr]::Zero) { Write-Output "opened (window not found)"; exit 0 }
Bring-Front $found
