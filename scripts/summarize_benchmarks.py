#!/usr/bin/env python3
"""Validate a complete benchmark grid and summarize per-image distributions.

Run from the repository root:
    python scripts/summarize_benchmarks.py benchmarks/div2k-100.csv

The CSV and its matching JSON metadata remain the authoritative measurements.
The PNG, SVG and summary JSON are derived outputs; no codec is rerun.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from statistics import fmean, median


METRICS = ('file_bpp', 'compression_ratio', 'psnr_db',
           'encode_wall_s_per_mb', 'decode_wall_s_per_mb')


def percentile(values, fraction):
    """Linear interpolation between sorted observations (inclusive endpoints)."""
    values = sorted(values)
    position = (len(values) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    return values[lower] + (values[upper] - values[lower]) * (position - lower)


def load_measurements(source):
    with source.open(newline='', encoding='utf-8') as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise ValueError('Empty benchmark CSV')
    metadata = json.loads(source.with_suffix('.json').read_text(encoding='utf-8'))
    images = sorted({row['image'] for row in rows})
    qualities = sorted({int(row['quality']) for row in rows})
    pairs = [(row['image'], int(row['quality'])) for row in rows]
    if len(set(pairs)) != len(rows):
        raise ValueError('Duplicate image/quality pair')
    if set(pairs) != {(image, quality) for image in images for quality in qualities}:
        raise ValueError('Incomplete image/quality grid')
    if images != sorted(record['name'] for record in metadata['inputs']):
        raise ValueError('CSV images disagree with metadata')
    if qualities != sorted(metadata['qualities']):
        raise ValueError('CSV qualities disagree with metadata')
    dimensions = {}
    for row in rows:
        for key, value in row.items():
            if key != 'image' and not math.isfinite(float(value)):
                raise ValueError(f"Nonfinite {key} for {row['image']}")
        shape = (int(row['width']), int(row['height']))
        if min(shape) <= 0 or dimensions.setdefault(row['image'], shape) != shape:
            raise ValueError('Invalid or inconsistent image dimensions')
        pixels = math.prod(shape)
        raw = int(row['raw_rgb_bytes'])
        size = int(row['file_bytes'])
        if raw != 3 * pixels or size < 28:
            raise ValueError('Invalid RGB or container size')
        expected = {'file_bpp': 8 * size / pixels, 'compression_ratio': raw / size,
                    'payload_bpp': int(row['payload_bits']) / pixels,
                    'space_saving_percent': 100 * (1 - size / raw)}
        for key, value in expected.items():
            if not math.isclose(float(row[key]), value, rel_tol=0, abs_tol=6e-9):
                raise ValueError(f"Inconsistent {key} for {row['image']}")
        for direction in ['encode', 'decode']:
            for clock in ['wall', 'cpu']:
                seconds = float(row[f'{direction}_{clock}_s'])
                normalized = float(row[f'{direction}_{clock}_s_per_mb'])
                if seconds < 0 or not math.isclose(normalized, seconds / (raw / 1e6),
                                                  rel_tol=0, abs_tol=1e-8):
                    raise ValueError('Invalid normalized time')
        for field, metadata_field in [('repeats', 'repeats'), ('warmup_runs', 'warmup_runs')]:
            if int(row[field]) != metadata[metadata_field]:
                raise ValueError(f'Inconsistent {field}')
    return rows, metadata, images, qualities


def load_png_sizes(path, rows, metadata):
    with path.open(newline='', encoding='utf-8') as stream:
        records = list(csv.DictReader(stream))
    sizes = {record['image']: int(record['png_file_bytes']) for record in records}
    hashes = {record['name']: record['sha256'] for record in metadata['inputs']}
    dimensions = {row['image']: (int(row['width']), int(row['height'])) for row in rows}
    if len(sizes) != len(records) or set(sizes) != set(dimensions):
        raise ValueError('PNG size records do not match benchmark images exactly')
    for record in records:
        name = record['image']
        if sizes[name] <= 0 or record['ppm_sha256'] != hashes[name]:
            raise ValueError(f'Invalid PNG size or benchmark input hash: {name}')
        if (int(record['width']), int(record['height'])) != dimensions[name]:
            raise ValueError(f'PNG size record has inconsistent dimensions: {name}')
    return sizes


def summarize(rows, qualities, png_sizes=None):
    results = []
    for quality in qualities:
        group = [row for row in rows if int(row['quality']) == quality]
        result = {'quality': quality, 'image_count': len(group)}
        metrics = {metric: [float(row[metric]) for row in group] for metric in METRICS}
        if png_sizes is not None:
            metrics['ojpg_percent_of_png'] = [100 * int(row['file_bytes']) / png_sizes[row['image']]
                                             for row in group]
        for metric, values in metrics.items():
            result[metric] = {'median': median(values),
                              'p25': percentile(values, 0.25),
                              'p75': percentile(values, 0.75),
                              'mean': fmean(values), 'min': min(values), 'max': max(values)}
        # Ratios of dataset totals are retained separately from image medians.
        total_pixels = sum(int(row['width']) * int(row['height']) for row in group)
        total_bytes = sum(int(row['file_bytes']) for row in group)
        result['dataset_file_bpp'] = 8 * total_bytes / total_pixels
        result['dataset_compression_ratio'] = 3 * total_pixels / total_bytes
        if png_sizes is not None:
            result['dataset_ojpg_percent_of_png'] = 100 * total_bytes / sum(png_sizes[row['image']] for row in group)
        results.append(result)
    return results


def render(results, image_count, metadata, figure_path):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.ticker import MaxNLocator

    blue, orange, ink = '#176b9b', '#bf551d', '#203247'
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 11,
                         'axes.titlesize': 14, 'axes.labelsize': 11,
                         'axes.spines.top': False, 'axes.spines.right': False,
                         'text.color': ink, 'axes.labelcolor': ink,
                         'xtick.color': ink, 'ytick.color': ink,
                         'svg.fonttype': 'none'})
    fig, (rate, runtime) = plt.subplots(1, 2, figsize=(12, 5.4))
    fig.subplots_adjust(left=0.065, right=0.98, top=0.80, bottom=0.20, wspace=0.25)
    fig.suptitle(f'DIV2K validation — {image_count} images', fontsize=18, fontweight='bold', y=0.97)
    fig.text(0.5, 0.90, 'Medians across images; bars and shading show the middle 50% of images',
             ha='center', fontsize=10.5)
    x = [item['file_bpp']['median'] for item in results]
    y = [item['psnr_db']['median'] for item in results]
    xerr = [[item['file_bpp']['median'] - item['file_bpp']['p25'] for item in results],
            [item['file_bpp']['p75'] - item['file_bpp']['median'] for item in results]]
    yerr = [[item['psnr_db']['median'] - item['psnr_db']['p25'] for item in results],
            [item['psnr_db']['p75'] - item['psnr_db']['median'] for item in results]]
    rate.errorbar(x, y, xerr=xerr, yerr=yerr, fmt='none', ecolor=blue, alpha=0.30,
                  capsize=3, elinewidth=1.5, zorder=1)
    rate.plot(x, y, color=blue, marker='o', linewidth=2, markersize=6, zorder=2)
    for index, item in enumerate(results):
        offsets = {10: (10, -15), 30: (-8, 11), 50: (10, -15),
                   75: (8, 9), 90: (10, -15), 100: (8, 9)}
        offset = offsets.get(item['quality'], (8, 9))
        rate.annotate(f"q={item['quality']}", (x[index], y[index]), xytext=offset,
                      textcoords='offset points', fontsize=9, color=ink)
    rate.set(title='Size–quality trade-off', xlabel='Complete file size (bits/pixel)',
             ylabel='RGB PSNR (dB)', xlim=(0, max(item['file_bpp']['p75'] for item in results) * 1.13))
    rate.xaxis.set_major_locator(MaxNLocator(nbins=6))
    qualities = [item['quality'] for item in results]
    for metric, label, color, marker in [
        ('encode_wall_s_per_mb', 'Encode', blue, 'o'),
        ('decode_wall_s_per_mb', 'Decode', orange, 's')]:
        runtime.fill_between(qualities, [item[metric]['p25'] for item in results],
                             [item[metric]['p75'] for item in results], color=color, alpha=0.15)
        runtime.plot(qualities, [item[metric]['median'] for item in results],
                     color=color, marker=marker, linewidth=2, label=label)
    runtime.set(title='Codec runtime', xlabel='Quality parameter',
                ylabel='Wall time (s/MB of original RGB)', xticks=qualities, ylim=(0, None))
    runtime.legend(frameon=False, loc='lower right')
    for axes in [rate, runtime]:
        axes.grid(axis='y', color='#d6dee5', alpha=0.7, linewidth=0.7)
        axes.set_axisbelow(True)
    fig.text(0.5, 0.075, metadata['build'].replace(', compiler default optimization', ''),
             ha='center', fontsize=10)
    passes = 'pass' if metadata['repeats'] == 1 else 'passes'
    fig.text(0.5, 0.035, f"{metadata['repeats']} measured {passes}, {metadata['warmup_runs']} warmup; "
             'codec time excludes file I/O; 1 MB = 1,000,000 bytes', ha='center', fontsize=9)
    figure_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(figure_path, dpi=180, facecolor='white')
    fig.savefig(figure_path.with_suffix('.svg'), facecolor='white')
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv', type=Path)
    parser.add_argument('--summary', type=Path, default=Path('benchmarks/div2k-100-summary.json'))
    parser.add_argument('--figure', type=Path, default=Path('docs/div2k-summary.png'))
    parser.add_argument('--png-sizes', type=Path, help='Original PNG size CSV; auto-detected beside the benchmark')
    parser.add_argument('--no-figure', action='store_true', help='Update numerical summary without redrawing unchanged plots')
    args = parser.parse_args()
    rows, metadata, images, qualities = load_measurements(args.csv)
    png_path = args.png_sizes or args.csv.with_name(args.csv.stem + '-png.csv')
    png_sizes = load_png_sizes(png_path, rows, metadata) if png_path.exists() else None
    if args.png_sizes and png_sizes is None:
        parser.error(f'PNG size CSV not found: {png_path}')
    results = summarize(rows, qualities, png_sizes)
    output = {'source_csv': args.csv.name,
              'source_csv_sha256': hashlib.sha256(args.csv.read_bytes()).hexdigest(),
              'source_metadata_sha256': hashlib.sha256(args.csv.with_suffix('.json').read_bytes()).hexdigest(),
              'image_count': len(images), 'row_count': len(rows),
              'aggregation': 'Per-image median; p25/p75 use linear interpolation at (n-1)*p; '
                             'spread describes images, not repeat timing uncertainty',
              'build': metadata['build'], 'repeats': metadata['repeats'],
              'warmup_runs': metadata['warmup_runs'], 'results': results}
    if png_sizes is not None:
        output['png_size_source'] = png_path.name
        output['png_size_source_sha256'] = hashlib.sha256(png_path.read_bytes()).hexdigest()
        output['png_comparison'] = ('Median of paired complete OJPG bytes / original PNG bytes * 100; '
                                    'the original PNG is lossless and OJPG is lossy')
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.summary.write_text(json.dumps(output, indent=2) + '\n', encoding='utf-8')
    if not args.no_figure:
        render(results, len(images), metadata, args.figure)
    extra_header = ' OJPG / PNG size |' if png_sizes is not None else ''
    print('| Quality | File bits/pixel | Compression ratio | RGB PSNR (dB) |' + extra_header)
    print('| ---: | ---: | ---: | ---: |' + (' ---: |' if png_sizes is not None else ''))
    for item in results:
        extra_value = f" {item['ojpg_percent_of_png']['median']:.1f}% |" if png_sizes is not None else ''
        print(f"| {item['quality']} | {item['file_bpp']['median']:.2f} | "
              f"{item['compression_ratio']['median']:.1f}× | {item['psnr_db']['median']:.1f} |" + extra_value)
    print(f'Validated {len(rows)} rows; wrote {args.summary}')


if __name__ == '__main__':
    main()
