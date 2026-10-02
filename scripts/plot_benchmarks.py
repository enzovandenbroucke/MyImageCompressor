#!/usr/bin/env python3
"""Plot measured rate/distortion and runtime; never invent missing data."""
import argparse
import csv
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('csv', type=Path)
    p.add_argument('--output', type=Path, default=Path('results/benchmark.png'))
    args = p.parse_args()
    with args.csv.open(newline='', encoding='utf-8') as f: rows = list(csv.DictReader(f))
    if not rows: p.error('Empty benchmark CSV')
    fig, axes = plt.subplots(1,2,figsize=(11,4.4), constrained_layout=True)
    for name in sorted({r['image'] for r in rows}):
        group = sorted((r for r in rows if r['image']==name), key=lambda r:float(r['file_bpp']))
        axes[0].plot([float(r['file_bpp']) for r in group], [float(r['psnr_db']) for r in group],
                     marker='o', label=Path(name).stem)
        group.sort(key=lambda r:int(r['quality']))
        axes[1].plot([int(r['quality']) for r in group], [float(r['encode_wall_s_per_mb']) for r in group],
                     marker='o', label=Path(name).stem+' encode')
        axes[1].plot([int(r['quality']) for r in group], [float(r['decode_wall_s_per_mb']) for r in group],
                     marker='.', linestyle='--', label=Path(name).stem+' decode')
    axes[0].set(xlabel='Complete file bits / original pixel', ylabel='RGB PSNR (dB)', title='Rate–distortion')
    axes[1].set(xlabel='Quality parameter', ylabel='Wall seconds / MB of original RGB', title='Codec runtime')
    for ax in axes:
        ax.grid(alpha=.2); ax.legend(fontsize=8)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=160); plt.close(fig)

if __name__ == '__main__': main()
