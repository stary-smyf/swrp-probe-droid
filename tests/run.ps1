param(
    [string]$LuaDll = $env:LUA51_DLL,
    [switch]$SyntaxOnly
)

$ErrorActionPreference = 'Stop'
if (-not $LuaDll) {
    $LuaDll = 'C:\Program Files\bin\64bit\lua51.dll'
}
if (-not (Test-Path -LiteralPath $LuaDll -PathType Leaf)) {
    throw 'Pass -LuaDll with the path to a Lua 5.1/LuaJIT DLL matching PowerShell architecture, or set LUA51_DLL.'
}
$LuaDll = (Resolve-Path -LiteralPath $LuaDll).Path

if (-not ('ProbeDroidLuaTestRuntime' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ProbeDroidLuaTestRuntime {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr NewState();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void StateAction(IntPtr state);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int LoadFile(IntPtr state, [MarshalAs(UnmanagedType.LPStr)] string file);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int PCall(IntPtr state, int arguments, int results, int handler);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr LuaString(IntPtr state, int index, out UIntPtr length);

    private static IntPtr module;
    private static Delegate Export(string name, Type type) {
        IntPtr address = GetProcAddress(module, name);
        if (address == IntPtr.Zero) throw new InvalidOperationException("Missing Lua 5.1 export: " + name);
        return Marshal.GetDelegateForFunctionPointer(address, type);
    }
    public static void Initialize(string path) {
        if (module != IntPtr.Zero) return;
        module = LoadLibraryW(path);
        if (module == IntPtr.Zero) throw new InvalidOperationException("Cannot load Lua DLL; Win32 error " + Marshal.GetLastWin32Error());
    }
    public static void CheckFile(string path, bool execute) {
        var create = (NewState)Export("luaL_newstate", typeof(NewState));
        var close = (StateAction)Export("lua_close", typeof(StateAction));
        var load = (LoadFile)Export("luaL_loadfile", typeof(LoadFile));
        var call = (PCall)Export("lua_pcall", typeof(PCall));
        var asString = (LuaString)Export("lua_tolstring", typeof(LuaString));
        IntPtr state = create();
        if (state == IntPtr.Zero) throw new InvalidOperationException("Cannot allocate Lua state");
        try {
            if (execute) ((StateAction)Export("luaL_openlibs", typeof(StateAction)))(state);
            int status = load(state, path);
            if (status == 0 && execute) status = call(state, 0, 0, 0);
            if (status != 0) {
                UIntPtr length;
                IntPtr error = asString(state, -1, out length);
                throw new InvalidOperationException(Marshal.PtrToStringAnsi(error));
            }
        } finally { close(state); }
    }
}
'@
}

[ProbeDroidLuaTestRuntime]::Initialize($LuaDll)
$addonRoot = Split-Path -Parent $PSScriptRoot
$previousDirectory = Get-Location
try {
    Set-Location -LiteralPath $addonRoot
    # Lua's loadfile uses the process directory, which PowerShell does not update.
    $previousProcessDirectory = [Environment]::CurrentDirectory
    [Environment]::CurrentDirectory = $addonRoot
    $sources = @(Get-ChildItem -LiteralPath lua -Filter '*.lua' -Recurse -File)
    foreach ($source in $sources) {
        [ProbeDroidLuaTestRuntime]::CheckFile($source.FullName, $false)
    }
    Write-Output ("PASS: Lua 5.1 syntax ({0} addon files)" -f $sources.Count)
    if (-not $SyntaxOnly) {
        $tests = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*_test.lua' -File | Sort-Object Name)
        foreach ($test in $tests) {
            [ProbeDroidLuaTestRuntime]::CheckFile($test.FullName, $true)
            Write-Output ("PASS: " + $test.Name)
        }
        if ($tests.Count -eq 0) { throw 'No *_test.lua regression files found.' }
    }
} finally {
    if ($previousProcessDirectory) { [Environment]::CurrentDirectory = $previousProcessDirectory }
    Set-Location -LiteralPath $previousDirectory
}
