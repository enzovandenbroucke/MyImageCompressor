#!/usr/bin/env python3
"""Record original PNG file sizes and hashes for a benchmark's input images."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import struct


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv', type=Path, help='Original benchmark CSV')
    parser.add_argument('--png-directory', type=Path, required=True)
    parser.add_argument('--conversion-manifest', type=Path, required=True,
                        help='Manifest produced by prepare_dataset.py for these benchmark inputs')
    parser.add_argument('--output', type=Path, default=Path('benchmarks/div2k-100-png.csv'))
    args = parser.parse_args()
    if args.output.exists():
        parser.error(f'Refusing to overwrite {args.output}')
    with args.csv.open(newline='', encoding='utf-8') as stream:
        rows = list(csv.DictReader(stream))
    metadata = json.loads(args.csv.with_suffix('.json').read_text())
    conversion = json.loads(args.conversion_manifest.read_text())
    converted = {item['output_name']: item for item in conversion['images']}
    input_hashes = {item['name']: item['sha256'] for item in metadata['inputs']}
    records = []
    for name in sorted({row['image'] for row in rows}):
        item = converted[name]
        path = args.png_directory / item['source_name']
        data = path.read_bytes()
        if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
            raise ValueError(f'Invalid PNG header: {path.name}')
        width, height = struct.unpack('>II', data[16:24])
        digest = hashlib.sha256(data).hexdigest()
        if digest != item['source_sha256'] or item['ppm_sha256'] != input_hashes[name]:
            raise ValueError(f'PNG/conversion/benchmark hashes disagree: {name}')
        group = [row for row in rows if row['image'] == name]
        if any((int(row['width']), int(row['height'])) != (width, height) for row in group):
            raise ValueError(f'PNG dimensions disagree with benchmark: {name}')
        records.append({'image': name, 'png_name': path.name, 'png_file_bytes': len(data),
                        'width': width, 'height': height, 'png_sha256': digest,
                        'ppm_sha256': item['ppm_sha256']})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=records[0].keys())
        writer.writeheader()
        writer.writerows(records)
    print(f'PNG sizes recorded for {len(records)} images; source and converted hashes verified.')


if __name__ == '__main__':
    main()
