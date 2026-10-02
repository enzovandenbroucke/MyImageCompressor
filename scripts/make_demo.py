#!/usr/bin/env python3
"""Create a deterministic original test image and compare actual reconstructions."""
import argparse
import csv
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont

def generate(width=640, height=384):
    image = Image.new('RGB', (width,height))
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            pixels[x,y] = (int(255*x/(width-1)), int(255*y/(height-1)),
                           int(127+110*((x%64)/63)))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((24,24,260,180), radius=24, fill=(22,37,64))
    draw.ellipse((45,45,185,165), fill=(244,192,69))
    draw.polygon([(170,155),(240,45),(285,155)], fill=(231,68,96))
    for x in range(320,610,4):
        draw.line((x,30,x,190), fill=(255,255,255) if x%8 else (10,10,10), width=2)
    for y in range(225,355,8):
        for x in range(30,610,8):
            value = 35 if (x//8+y//8)%2 else 230
            draw.rectangle((x,y,x+3,y+3), fill=(value,value,value))
    return image

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--exe', type=Path, default=Path('_build/default/bin/main.exe'))
    p.add_argument('--runtime', type=Path)
    p.add_argument('--output', type=Path, default=Path('results/demo'))
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    original = generate(); source = args.output/'synthetic.ppm'; original.save(source)
    command = ([str(args.runtime.resolve())] if args.runtime else [])+[str(args.exe.resolve())]
    qualities = [10,50,90]
    images = [original]
    for quality in qualities:
        compressed = args.output/f'q{quality}.ojpg'; decoded = args.output/f'q{quality}.ppm'
        subprocess.run(command+['compress',str(source),str(compressed),'--quality',str(quality)],check=True)
        subprocess.run(command+['decompress',str(compressed),str(decoded)],check=True)
        with Image.open(decoded) as img: images.append(img.copy())
    metrics = args.output/'metrics.csv'
    subprocess.run(command+['benchmark',str(source),'--qualities',','.join(map(str,qualities)),
                            '--repeat','1','--csv',str(metrics)],check=True)
    with metrics.open(newline='',encoding='utf-8') as f: rows = list(csv.DictReader(f))
    font = ImageFont.load_default(size=17)
    board = Image.new('RGB',(1280,960),(245,247,250)); draw = ImageDraw.Draw(board)
    labels = ['Original']+[f"q={r['quality']} | {float(r['file_bpp']):.2f} bpp | {float(r['psnr_db']):.2f} dB" for r in rows]
    for i,(img,label) in enumerate(zip(images,labels)):
        x=(i%2)*640; y=(i//2)*480
        draw.text((x+16,y+14),label,font=font,fill=(22,37,64))
        board.paste(img,(x,y+48))
    board.save(args.output/'comparison.png')
    # Publish only our generated illustration; do not redistribute dataset photos.
    original.save(args.output/'original.png')
    print(args.output/'comparison.png')

if __name__ == '__main__': main()
