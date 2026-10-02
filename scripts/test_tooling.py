#!/usr/bin/env python3
"""Independent file-size/PSNR checks through Pillow and the actual CLI."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--exe', type=Path, default=Path('_build/default/bin/main.exe'))
    p.add_argument('--runtime', type=Path)
    args = p.parse_args()
    command = ([str(args.runtime.resolve())] if args.runtime else [])+[str(args.exe.resolve())]
    def call(*arguments):
        return subprocess.run(command+list(map(str,arguments)),capture_output=True,text=True,check=True)
    with tempfile.TemporaryDirectory(prefix='jpeg-like-tooling-') as temp:
        temp = Path(temp)
        source = temp/'source'; source.mkdir()
        png = source/'odd.png'
        original = Image.new('RGB',(19,17))
        original.putdata([(x*11%256,y*13%256,(x+y)*7%256) for y in range(17) for x in range(19)])
        original.save(png)
        ppms = temp/'ppm'
        subprocess.run([sys.executable,str(ROOT/'scripts/prepare_dataset.py'),str(source),str(ppms)],check=True)
        ppm = ppms/'odd.ppm'
        with Image.open(ppm) as reread:
            assert reread.size == original.size and reread.tobytes() == original.tobytes()
        manifest = json.loads((ppms/'conversion-manifest.json').read_text())['images'][0]
        assert manifest['source_sha256'] == hashlib.sha256(png.read_bytes()).hexdigest()
        assert manifest['ppm_sha256'] == hashlib.sha256(ppm.read_bytes()).hexdigest()
        output = temp/'metrics.csv'
        call('benchmark',ppm,'--qualities','10,50,90,100','--repeat','2','--csv',output)
        with output.open(newline='') as f: rows=list(csv.DictReader(f))
        assert len(rows)==4
        assert all(int(row['repeats'])==2 and int(row['warmup_runs'])==0 for row in rows)
        for row in rows:
            compressed = temp/'test.ojpg'; decoded = temp/'reconstructed.ppm'
            call('compress',ppm,compressed,'--quality',row['quality'])
            call('decompress',compressed,decoded)
            blob = compressed.read_bytes()
            assert blob[:4] == b'OJPG' and len(blob) == int(row['file_bytes'])
            lengths = [int.from_bytes(blob[i:i+4],'big') for i in (16,20,24)]
            assert sum(lengths) == int(row['payload_bits'])
            assert len(blob) == 28 + sum((n+7)//8 for n in lengths)
            assert math.isclose(float(row['file_bpp']),len(blob)*8/(19*17),abs_tol=1e-8)
            assert math.isclose(float(row['compression_ratio']),19*17*3/len(blob),abs_tol=1e-8)
            with Image.open(decoded) as img:
                assert img.size == original.size
                expected = original.tobytes(); actual = img.tobytes()
            mse = sum((a-b)**2 for a,b in zip(expected,actual))/len(expected)
            psnr = math.inf if mse==0 else 10*math.log10(255**2/mse)
            assert math.isclose(float(row['psnr_db']),psnr,abs_tol=1e-8)
            for direction in ['encode','decode']:
                assert math.isclose(float(row[f'{direction}_wall_s_per_mb']),
                    float(row[f'{direction}_wall_s'])/(19*17*3/1e6),rel_tol=1e-3,abs_tol=.002)
        for quality in ['0','101']:
            result = subprocess.run(command+['compress',str(ppm),str(temp/'bad.ojpg'),'--quality',quality],capture_output=True)
            assert result.returncode==2 and not (temp/'bad.ojpg').exists()
        warm_csv = temp/'warmup.csv'
        call('benchmark',ppm,'--qualities','10,50,90,100','--warmup','1','--csv',warm_csv)
        with warm_csv.open(newline='') as f: warm_rows=list(csv.DictReader(f))
        for cold, warm in zip(rows, warm_rows):
            assert int(warm['repeats'])==1 and int(warm['warmup_runs'])==1
            for field in ['payload_bits','file_bytes','file_bpp','compression_ratio','psnr_db']:
                assert cold[field]==warm[field]
        invalid = subprocess.run(command+['benchmark',str(ppm),'--warmup','-1'],capture_output=True)
        assert invalid.returncode==2
        # Runner writes sanitized metadata and supports spaces/CSV delimiters.
        tricky = temp/'space and,comma.ppm'; tricky.write_bytes(ppm.read_bytes())
        runner_csv = temp/'runner.csv'
        runner = [sys.executable,str(ROOT/'scripts/run_benchmarks.py'),str(tricky),
                  '--exe',str(args.exe.resolve()),'--qualities','75',
                  '--build-label','Integration test','--output',str(runner_csv)]
        if args.runtime: runner += ['--runtime',str(args.runtime.resolve())]
        subprocess.run(runner,check=True)
        metadata = json.loads(runner_csv.with_suffix('.json').read_text())
        assert metadata['inputs'][0]['name']==tricky.name
        assert metadata['repeats']==1 and metadata['warmup_runs']==0
        with runner_csv.open(newline='') as f:
            runner_row=next(csv.DictReader(f))
            assert runner_row['image']==tricky.name
            assert runner_row['repeats']=='1' and runner_row['warmup_runs']=='0'
        print('Tooling checks passed: PNG conversion, independent PSNR, binary file sizes, CSV, timing units and CLI errors')

if __name__ == '__main__': main()
