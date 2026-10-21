"""Sample mean colour of small boxes: sample.py img x,y[,r] ... -> hex list"""
import sys
sys.path.append("/Users/minimax/Library/Python/3.9/lib/python/site-packages")
import numpy as np
from PIL import Image

def main() -> None:
    im = np.asarray(Image.open(sys.argv[1]).convert("RGB"), dtype=np.float32)
    for spec in sys.argv[2:]:
        parts = [int(v) for v in spec.split(",")]
        x, y = parts[0], parts[1]
        r = parts[2] if len(parts) > 2 else 4
        box = im[max(0, y - r):y + r + 1, max(0, x - r):x + r + 1].reshape(-1, 3)
        m = box.mean(axis=0).astype(int)
        print(f"{spec:>16}: #{m[0]:02x}{m[1]:02x}{m[2]:02x}  rgb{tuple(m)}  std {box.std(axis=0).mean():.1f}")

if __name__ == "__main__":
    main()
