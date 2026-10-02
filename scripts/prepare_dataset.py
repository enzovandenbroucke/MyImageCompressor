#!/usr/bin/env python3
"""Convert a local PNG dataset to 8-bit RGB PPM without resizing or cropping."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('source', type=Path)
    p.add_argument('destination', type=Path)
    p.add_argument('--limit', type=int, help='First N files in filename order')
    args = p.parse_args()
    if args.limit is not None and args.limit < 1:
        p.error('--limit must be positive')
    files = sorted(args.source.glob('*.png')) if args.source.is_dir() else [args.source]
    if args.limit: files = files[:args.limit]
    if not files: p.error('No PNG images found')
    args.destination.mkdir(parents=True, exist_ok=True)
    records = []
    for path in files:
        target = args.destination/(path.stem+'.ppm')
        if target.exists(): raise FileExistsError(f'Refusing to overwrite {target}')
        with Image.open(path) as source:
            if 'A' in source.getbands() or 'transparency' in source.info:
                raise ValueError(f'{path.name}: transparent input requires an explicit background choice')
            rgb = source.convert('RGB')
            rgb.save(target, format='PPM')
            records.append({'source_name':path.name, 'output_name':target.name,
                            'width':rgb.width, 'height':rgb.height,
                            'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                            'ppm_sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
        print(f'{path.name} -> {target.name}')
    manifest = args.destination/'conversion-manifest.json'
    manifest.write_text(json.dumps({'conversion':'Pillow RGB, no resizing/cropping/color-profile conversion',
        'images':records}, indent=2)+'\n', encoding='utf-8')

if __name__ == '__main__': main()
