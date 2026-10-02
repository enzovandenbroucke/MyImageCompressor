param(
    [string]$CompilerPath,
    [string]$PythonPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot

if (-not $CompilerPath) {
    $portableCompiler = Join-Path $workspaceRoot '.tools\4.14.0+mingw64c\bin\ocamlc.exe'
    if (Test-Path -LiteralPath $portableCompiler) {
        $CompilerPath = $portableCompiler
    } else {
        $availableCompiler = Get-Command ocamlc -ErrorAction SilentlyContinue
        if (-not $availableCompiler) {
            throw 'OCaml compiler not found. Install OCaml or provide -CompilerPath.'
        }
        $CompilerPath = $availableCompiler.Source
    }
}
if (-not $PythonPath) {
    $availablePython = Get-Command python -ErrorAction SilentlyContinue
    $bundledPython = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    if (Test-Path -LiteralPath $bundledPython) {
        $PythonPath = $bundledPython
    } elseif ($availablePython) {
        $PythonPath = $availablePython.Source
    } else {
        throw 'Python not found. Install Python 3 or provide -PythonPath.'
    }
}

$CompilerPath = (Resolve-Path -LiteralPath $CompilerPath).Path
$PythonPath = (Resolve-Path -LiteralPath $PythonPath).Path
$compilerRoot = Split-Path -Parent (Split-Path -Parent $CompilerPath)
$portableLibrary = Join-Path $compilerRoot 'lib\ocaml'
$portableStubs = Join-Path $portableLibrary 'stublibs'
$previousLibrary = $env:OCAMLLIB
$previousStubs = $env:CAML_LD_LIBRARY_PATH
try {
    if (Test-Path -LiteralPath $portableLibrary) { $env:OCAMLLIB = $portableLibrary }
    if (Test-Path -LiteralPath $portableStubs) { $env:CAML_LD_LIBRARY_PATH = $portableStubs }
    & $PythonPath (Join-Path $PSScriptRoot 'build.py') --compiler $CompilerPath --test
    if ($LASTEXITCODE -ne 0) { throw "Build or tests failed (exit code $LASTEXITCODE)." }
} finally {
    $env:OCAMLLIB = $previousLibrary
    $env:CAML_LD_LIBRARY_PATH = $previousStubs
}
