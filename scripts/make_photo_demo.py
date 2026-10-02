#!/usr/bin/env python3
"""Compare a photograph with actual file-based codec reconstructions.

The codec always processes the original resolution. Resizing and enlarged
crops are used only for the documentation figures. Each quality is encoded
and decoded once; metrics are computed from those same files.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont

def render_figures(original, images, metrics, crop, source_name, output):
    panel_width = 640
    display_height = round(original.height*panel_width/original.width)
    header_height = 64
    labels = ['Original - '+source_name]+[
        f'q={m["quality"]} | {m["file_bpp"]:.2f} bpp | {m["psnr_db"]:.2f} dB' for m in metrics]
    font = ImageFont.load_default(size=20)
    def board_for(panels, height):
        board = Image.new('RGB',(2*panel_width,2*(height+header_height)),(245,247,250))
        draw = ImageDraw.Draw(board)
        for i,(panel,label) in enumerate(zip(panels,labels)):
            x = (i%2)*panel_width; y = (i//2)*(height+header_height)
            draw.text((x+16,y+20),label,font=font,fill=(22,37,64))
            board.paste(panel,(x,y+header_height))
        return board
    previews = []
    for img in images:
        preview = img.resize((panel_width,display_height),Image.Resampling.LANCZOS)
        draw = ImageDraw.Draw(preview)
        rectangle = tuple(round(v*panel_width/original.width) for v in crop)
        draw.rectangle(rectangle,outline=(255,212,70),width=2)
        previews.append(preview)
    board_for(previews,display_height).save(output/'comparison.png',optimize=True)
    detail_height = round((crop[3]-crop[1])*panel_width/(crop[2]-crop[0]))
    details = [img.crop(crop).resize((panel_width,detail_height),Image.Resampling.NEAREST) for img in images]
    board_for(details,detail_height).save(output/'detail.png',optimize=True)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('input', type=Path)
    p.add_argument('--exe', type=Path, default=Path('_build/default/bin/main.exe'))
    p.add_argument('--runtime', type=Path)
    p.add_argument('--output', type=Path, default=Path('results/photo-demo'))
    p.add_argument('--crop', type=int, nargs=4, metavar=('LEFT','TOP','RIGHT','BOTTOM'),
                   help='Original-resolution crop for the enlarged detail')
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with Image.open(args.input) as img:
        if 'A' in img.getbands() or 'transparency' in img.info:
            p.error('Transparent input requires an explicit background choice')
        original = img.convert('RGB')
    crop = tuple(args.crop) if args.crop else (
        original.width//2-160,original.height//2-160,
        original.width//2+160,original.height//2+160)
    if not (0 <= crop[0] < crop[2] <= original.width and
            0 <= crop[1] < crop[3] <= original.height):
        p.error('Crop must be inside the original image')
    source = args.output/(args.input.stem+'.ppm')
    original.save(source,format='PPM')
    command = ([str(args.runtime.resolve())] if args.runtime else [])+[str(args.exe.resolve())]
    images = [original]
    metrics = []
    expected = original.tobytes()
    pixel_count = original.width*original.height
    for quality in [10,50,90]:
        print(f'Encoding {args.input.name} at original resolution, q={quality}',flush=True)
        compressed = args.output/f'q{quality}.ojpg'
        decoded = args.output/f'q{quality}.ppm'
        subprocess.run(command+['compress',str(source),str(compressed),'--quality',str(quality)],check=True)
        subprocess.run(command+['decompress',str(compressed),str(decoded)],check=True)
        with Image.open(decoded) as img:
            assert img.size == original.size
            reconstruction = img.convert('RGB')
        images.append(reconstruction)
        mse = sum((a-b)**2 for a,b in zip(expected,reconstruction.tobytes()))/len(expected)
        psnr = math.inf if mse == 0 else 10*math.log10(255**2/mse)
        blob = compressed.read_bytes()
        assert blob[:4] == b'OJPG'
        lengths = [int.from_bytes(blob[offset:offset+4],'big') for offset in [16,20,24]]
        assert len(blob) == 28 + sum((length+7)//8 for length in lengths)
        metrics.append({'image':args.input.name,'quality':quality,
            'width':original.width,'height':original.height,'raw_rgb_bytes':len(expected),
            'payload_bits':sum(lengths),'file_bytes':len(blob),
            'payload_bpp':sum(lengths)/pixel_count,'file_bpp':8*len(blob)/pixel_count,
            'compression_ratio':len(expected)/len(blob),'psnr_db':psnr})
        print(f'  {metrics[-1]["file_bpp"]:.3f} bpp, {psnr:.2f} dB',flush=True)
    with (args.output/'metrics.csv').open('w',newline='',encoding='utf-8') as f:
        writer = csv.DictWriter(f,fieldnames=list(metrics[0]))
        writer.writeheader(); writer.writerows(metrics)
    metadata = {'source':args.input.name,
        'source_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),
        'ppm_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'width':original.width,'height':original.height,'crop':crop,
        'processing':'Original-resolution RGB input, one encode/decode per quality; no warmup or repeated benchmark',
        'display':'Overview resized with Lanczos; detail enlarged with nearest-neighbor; metrics use full original image',
        'note':'Visual example only; no runtime measurements in this CSV'}
    (args.output/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8')

    render_figures(original, images, metrics, crop, args.input.name, args.output)
    print(args.output/'comparison.png')

if __name__ == '__main__': main()
