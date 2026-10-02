#!/usr/bin/env python3
"""Small no-Dune fallback, including bytecode builds on Windows."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MODULES = ['image', 'bits', 'dct', 'tables', 'entropy', 'codec', 'container', 'reference']

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', default='ocamlc')
    p.add_argument('--test', action='store_true')
    args = p.parse_args()
    compiler = shutil.which(args.compiler) or args.compiler
    compiler = str(Path(compiler).resolve()) if Path(compiler).exists() else compiler
    native = Path(compiler).name.startswith('ocamlopt')
    build = ROOT / '_build' / ('native' if native else 'bytecode')
    build.mkdir(parents=True, exist_ok=True)
    sources = [ROOT/'src'/f'{n}.ml' for n in MODULES]
    sources += [ROOT/'bin/main.ml', ROOT/'test/test_codec.ml']
    for source in sources:
        shutil.copyfile(source, build/source.name)
    def run(*cmd):
        subprocess.run([compiler, *cmd], cwd=build, check=True)
    for name in MODULES:
        run('-g', '-w', '+a-4-40-42-70', '-c', name+'.ml')
    suffix = '.cmx' if native else '.cmo'
    objects = [n+suffix for n in MODULES]
    run('-g', '-o', 'jpeg-like.exe', 'unix.cmxa' if native else 'unix.cma', *objects, 'main.ml')
    run('-g', '-o', 'test-codec.exe', *objects, 'test_codec.ml')
    print(build/'jpeg-like.exe')
    if args.test:
        executable = build/'test-codec.exe'
        # Bytecode launchers may retain the compiler distribution's original path.
        runtime = Path(compiler).parent/'ocamlrun.exe'
        command = [str(runtime), str(executable)] if not native and runtime.exists() else [str(executable)]
        subprocess.run(command, check=True, cwd=ROOT)

if __name__ == '__main__':
    main()
