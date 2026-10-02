param(
    [string]$ImagesDirectory,
    [string]$Output,
    [string]$Qualities = '10,30,50,75,90,100',
    [ValidateRange(1, 1000)][int]$Repeat = 1,
    [ValidateRange(0, 1000)][int]$Warmup = 0,
    [ValidateRange(0, 100000)][int]$Limit = 0,
    [string]$CompilerPath,
    [string]$PythonPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
if (-not $ImagesDirectory) { $ImagesDirectory = Join-Path $repoRoot 'data\div2k-ppm' }
if (-not $Output) { $Output = Join-Path $repoRoot 'results\div2k-100.csv' }
if (Test-Path -LiteralPath $Output) { throw "Refusing to overwrite $Output. Choose another -Output." }

if (-not $CompilerPath) {
    $portableCompiler = Join-Path $workspaceRoot '.tools\4.14.0+mingw64c\bin\ocamlc.exe'
    if (Test-Path -LiteralPath $portableCompiler) {
        $CompilerPath = $portableCompiler
    } else {
        $availableCompiler = Get-Command ocamlc -ErrorAction SilentlyContinue
        if (-not $availableCompiler) { throw 'OCaml compiler not found. Provide -CompilerPath.' }
        $CompilerPath = $availableCompiler.Source
    }
}
if (-not $PythonPath) {
    $bundledPython = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    $availablePython = Get-Command python -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $bundledPython) {
        $PythonPath = $bundledPython
    } elseif ($availablePython) {
        $PythonPath = $availablePython.Source
    } else { throw 'Python not found. Provide -PythonPath.' }
}
$CompilerPath = (Resolve-Path -LiteralPath $CompilerPath).Path
$PythonPath = (Resolve-Path -LiteralPath $PythonPath).Path

# Convert the original dataset only when the destination has no PPM images.
# Existing conversions are preserved; conversion failures are never ignored.
$images = @(Get-ChildItem -LiteralPath $ImagesDirectory -Filter '*.ppm' -File -ErrorAction SilentlyContinue)
if ($images.Count -eq 0) {
    $sourceDirectory = Join-Path $workspaceRoot ("final\Images non compress$([char]233)es\DIV2K_valid_HR")
    if (-not (Test-Path -LiteralPath $sourceDirectory)) { throw "No PPM images in $ImagesDirectory. Prepare the dataset first." }
    & $PythonPath (Join-Path $PSScriptRoot 'prepare_dataset.py') $sourceDirectory $ImagesDirectory
    if ($LASTEXITCODE -ne 0) { throw "Dataset conversion failed (exit code $LASTEXITCODE)." }
    $images = @(Get-ChildItem -LiteralPath $ImagesDirectory -Filter '*.ppm' -File)
}

$compilerRoot = Split-Path -Parent (Split-Path -Parent $CompilerPath)
$portableLibrary = Join-Path $compilerRoot 'lib\ocaml'
$portableStubs = Join-Path $portableLibrary 'stublibs'
$previousLibrary = $env:OCAMLLIB
$previousStubs = $env:CAML_LD_LIBRARY_PATH
try {
    if (Test-Path -LiteralPath $portableLibrary) { $env:OCAMLLIB = $portableLibrary }
    if (Test-Path -LiteralPath $portableStubs) { $env:CAML_LD_LIBRARY_PATH = $portableStubs }
    & $PythonPath (Join-Path $PSScriptRoot 'build.py') --compiler $CompilerPath
    if ($LASTEXITCODE -ne 0) { throw "Build failed (exit code $LASTEXITCODE)." }
    $version = & $CompilerPath -version
    if ($LASTEXITCODE -ne 0) { throw 'Could not read compiler version.' }
    $buildType = 'bytecode'
    if ((Split-Path -Leaf $CompilerPath).StartsWith('ocamlopt')) { $buildType = 'native' }
    $executable = Join-Path $repoRoot "_build\$buildType\jpeg-like.exe"
    $runnerArguments = @((Join-Path $PSScriptRoot 'run_benchmarks.py'), $ImagesDirectory,
        '--exe', $executable, '--qualities', $Qualities, '--repeat', "$Repeat",
        '--warmup', "$Warmup", '--output', $Output,
        '--build-label', "OCaml $version Windows $buildType, compiler default optimization")
    if ($buildType -eq 'bytecode') {
        $runtime = Join-Path (Split-Path -Parent $CompilerPath) 'ocamlrun.exe'
        if (Test-Path -LiteralPath $runtime) { $runnerArguments += @('--runtime', $runtime) }
    }
    if ($Limit -gt 0) { $runnerArguments += @('--limit', "$Limit") }
    $imageCount = $images.Count
    if ($Limit -gt 0) { $imageCount = [Math]::Min($imageCount, $Limit) }
    Write-Host "Benchmarking $imageCount images; qualities $Qualities; $Repeat measured run(s), $Warmup warmup run(s)."
    & $PythonPath @runnerArguments
    if ($LASTEXITCODE -ne 0) { throw "Benchmark failed (exit code $LASTEXITCODE)." }
} finally {
    $env:OCAMLLIB = $previousLibrary
    $env:CAML_LD_LIBRARY_PATH = $previousStubs
}
