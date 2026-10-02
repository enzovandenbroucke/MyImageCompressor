#!/usr/bin/env python3
"""Run codec benchmarks and record machine/build metadata alongside the CSV."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import time

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('images', type=Path, nargs='+', help='PPM files or directories')
    p.add_argument('--exe', type=Path, default=Path('_build/default/bin/main.exe'))
    p.add_argument('--runtime', type=Path, help='Optional ocamlrun for bytecode executable')
    p.add_argument('--qualities', default='10,30,50,75,90,100')
    p.add_argument('--repeat', type=int, default=1, help='Measured runs per quality (default: 1)')
    p.add_argument('--warmup', type=int, default=0, help='Unmeasured warmup runs per quality (default: 0)')
    p.add_argument('--limit', type=int)
    p.add_argument('--output', type=Path, default=Path('results/benchmark.csv'))
    p.add_argument('--build-label', required=True, help='e.g. OCaml 4.14.0 bytecode or OCaml 5.3 native')
    p.add_argument('--label', default='Local benchmark')
    args = p.parse_args()
    if args.repeat < 1 or (args.limit is not None and args.limit < 1): p.error('Repeat/limit must be positive')
    if args.warmup < 0: p.error('Warmup must be nonnegative')
    qualities = [int(x) for x in args.qualities.split(',')]
    if not qualities or any(not 1 <= x <= 100 for x in qualities): p.error('Quality must be in [1,100]')
    files = []
    for source in args.images:
        files.extend(sorted(source.glob('*.ppm')) if source.is_dir() else [source])
    files = sorted(set(path.resolve() for path in files))
    if args.limit: files = files[:args.limit]
    if not files: p.error('No PPM images found')
    if args.output.exists(): p.error(f'Refusing to overwrite {args.output}')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    exe = args.exe.resolve()
    command = ([str(args.runtime.resolve())] if args.runtime else []) + [str(exe), 'benchmark']
    command += [str(path) for path in files]
    command += ['--qualities', args.qualities, '--repeat', str(args.repeat),
                '--warmup', str(args.warmup), '--csv', str(args.output)]
    # Stable names and hashes identify inputs; machine-specific absolute paths
    # are unnecessary in the shareable metadata and are stripped from the CSV.
    import csv
    metadata = {
        'label':args.label, 'created_utc':datetime.now(timezone.utc).isoformat(),
        'platform':platform.platform(), 'machine':platform.machine(),
        'processor':platform.processor(), 'logical_cpu_count':os.cpu_count(),
        'build':args.build_label, 'executable_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),
        'qualities':qualities, 'repeats':args.repeat, 'warmup_runs':args.warmup,
        'timing':'single measured pass when repeats=1, otherwise median per image/quality; codec only; parsing and disk I/O excluded',
        'mb_definition':'1000000 bytes of original uncompressed 8-bit RGB raster',
        'inputs':[{'name':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()} for path in files]
    }
    start = time.perf_counter()
    subprocess.run(command, check=True)
    metadata['total_runner_wall_s'] = time.perf_counter()-start
    with args.output.open(newline='', encoding='utf-8') as f:
        rows = list(csv.DictReader(f)); fields = rows[0].keys()
    for row in rows: row['image'] = Path(row['image']).name
    with args.output.open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fields); writer.writeheader(); writer.writerows(rows)
    args.output.with_suffix('.json').write_text(json.dumps(metadata, indent=2)+'\n', encoding='utf-8')
    print(args.output)

if __name__ == '__main__': main()
