"use client";

import { useEffect, useRef } from "react";

type SpriteName = "logo" | "lock" | "shield" | "clock" | "key";

const d = (x: number, y: number, a: number, b: number) => Math.hypot(x - a, y - b);

type Voxel = [fn: (x: number, y: number, z: number) => boolean, color: string];

const SPRITES: Record<SpriteName, { n: number; h: number; p: Voxel[] }> = {
  logo: {
    n: 32,
    h: 14,
    p: [
      [(x, y, z) => { const r = d(x, y, 14, 16); return z >= 1 && z <= 11 && r >= 6.8 && r <= 13.2 && Math.abs(Math.atan2(y - 16, x - 14)) > 0.76; }, "#FF5A36"],
      [(x, y, z) => { const r = d(x, y, 14, 16); return z === 12 && r >= 8.5 && r <= 11.5 && Math.abs(Math.atan2(y - 16, x - 14)) > 0.85; }, "#FF8A6E"],
      [(x, y, z) => { const a = x - 25.2, b = y - 16, c = z - 6; return a * a + b * b + c * c <= 32; }, "#FFD23F"],
      [(x, y, z) => { const a = x - 24.2, b = y - 15, c = z - 8; return a * a + b * b + c * c <= 9; }, "#FFF3B0"],
    ],
  },
  lock: {
    n: 18,
    h: 8,
    p: [
      [(x, y) => x >= 3 && x <= 15 && y >= 8 && y <= 16, "#FFD23F"],
      [(x, y, z) => { const r = d(x, y, 9, 8); return z >= 1 && z <= 6 && y <= 8 && r >= 3.2 && r <= 5; }, "#1B1620"],
      [(x, y, z) => z === 7 && d(x, y, 9, 11.5) <= 1.5, "#1B1620"],
    ],
  },
  shield: {
    n: 18,
    h: 8,
    p: [
      [(x, y) => y >= 2 && y <= 16 && Math.abs(x - 9) <= (y < 10 ? 5.8 : 5.8 - (y - 10)), "#74E0F2"],
      [(x, y, z) => z === 7 && [[6, 9], [7, 10], [8, 11], [9, 10], [10, 9], [11, 8]].some((c) => Math.floor(x) === c[0] && Math.floor(y) === c[1]), "#FFFFFF"],
    ],
  },
  clock: {
    n: 18,
    h: 8,
    p: [
      [(x, y) => d(x, y, 9, 9) <= 6.8, "#7CE3B5"],
      [(x, y, z) => z === 7 && ((x >= 8.2 && x < 9.6 && y >= 4.5 && y < 9.5) || (x >= 9 && x <= 12.5 && y >= 8.5 && y < 9.8)), "#1B1620"],
    ],
  },
  key: {
    n: 18,
    h: 8,
    p: [
      [(x, y) => { const r = d(x, y, 5.5, 9); return (r >= 2.2 && r <= 4.4) || (x >= 9 && x <= 15.5 && y >= 8 && y <= 9.6) || (x >= 12 && x <= 13.2 && y >= 9.6 && y <= 11.8) || (x >= 14.2 && x <= 15.4 && y >= 9.6 && y <= 11.8); }, "#FF5A36"],
    ],
  },
};

function shade(hex: string, f: number) {
  const a = [1, 3, 5].map((i) => parseInt(hex.substr(i, 2), 16));
  return `rgb(${a.map((v) => Math.max(0, Math.min(255, Math.round(f <= 1 ? v * f : v + (255 - v) * (f - 1) * 1.8)))).join(",")})`;
}

export default function VoxelSprite({
  name,
  scale = 2.2,
  className = "",
}: {
  name: SpriteName;
  scale?: number;
  className?: string;
}) {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const cv = ref.current;
    const o = SPRITES[name];
    if (!cv || !o) return;

    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const W = Math.ceil(o.n * scale);
    const H = Math.ceil(o.n * scale * 0.5 + o.h * scale);
    cv.width = W * dpr;
    cv.height = H * dpr;
    cv.style.width = `${W}px`;
    cv.style.height = `${H}px`;

    // Build the voxel grid once.
    const V: (string | null)[][][] = [];
    for (let z = 0; z < o.h; z++) {
      V[z] = [];
      for (let y = 0; y < o.n; y++) {
        V[z][y] = [];
        for (let x = 0; x < o.n; x++) {
          let c: string | null = null;
          for (const [fn, col] of o.p) if (fn(x + 0.5, y + 0.5, z)) c = col;
          V[z][y][x] = c;
        }
      }
    }
    const layers: HTMLCanvasElement[] = [];
    for (let z = 0; z < o.h; z++) {
      const layer = document.createElement("canvas");
      layer.width = layer.height = o.n;
      const g = layer.getContext("2d")!;
      for (let y = 0; y < o.n; y++) {
        for (let x = 0; x < o.n; x++) {
          const c2 = V[z][y][x];
          if (!c2) continue;
          const top = !V[z + 1] || !V[z + 1][y][x];
          const rimL = !V[z][y][x - 1] || !(V[z][y - 1] && V[z][y - 1][x]);
          const rimR = !V[z][y][x + 1] || !(V[z][y + 1] && V[z][y + 1][x]);
          const ao = V[z + 1] && ((V[z + 1][y - 1] && V[z + 1][y - 1][x]) || (V[z + 1][y] && V[z + 1][y][x - 1])) ? 0.12 : 0;
          let f = 0.72 + 0.28 * (z / Math.max(1, o.h - 1)) - ao;
          if (top) { f += 0.18; if (rimL) f += 0.08; }
          else { if (rimR) f -= 0.14; else if (rimL) f += 0.04; }
          g.fillStyle = shade(c2, f);
          g.fillRect(x, y, 1, 1);
        }
      }
      layers.push(layer);
    }

    const ctx = cv.getContext("2d")!;
    const k = scale * dpr;
    const cx = (W * dpr) / 2;
    const cy = H * dpr - o.n * k * 0.5 * 0.82 * 1.1;
    const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
    let angle = 0.5, squash = 0.82, lift = 0, hov = false, tlift = 0;
    const phase = Math.random() * 6.28;

    const draw = () => {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, cv.width, cv.height);
      ctx.imageSmoothingEnabled = false;
      ctx.fillStyle = "rgba(27,22,19,.14)";
      ctx.beginPath();
      ctx.ellipse(cx + 2 * dpr, cy + 3 * dpr, o.n * k * 0.34, o.n * k * 0.34 * squash, 0, 0, 6.3);
      ctx.fill();
      for (let z = 0; z < o.h; z++) {
        const oz = z * k * squash * 0.98 + lift * dpr;
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.translate(cx, cy - oz);
        ctx.scale(1, squash);
        ctx.rotate(angle);
        ctx.drawImage(layers[z], (-o.n * k) / 2, (-o.n * k) / 2, o.n * k, o.n * k);
      }
    };

    const enter = () => { hov = true; tlift = 4; };
    const leave = () => { hov = false; tlift = 0; };
    cv.addEventListener("pointerenter", enter);
    cv.addEventListener("pointerleave", leave);

    let raf = 0;
    if (!reduced) {
      const frame = (t: number) => {
        const idle = Math.sin(t / 1400 + phase) * 2.4;
        lift += (idle + tlift - lift) * 0.08;
        squash += (0.82 + (hov ? 0.06 : 0) - squash) * 0.1;
        angle += (0.5 + (hov ? 0.22 : 0) - angle) * 0.08;
        draw();
        raf = requestAnimationFrame(frame);
      };
      raf = requestAnimationFrame(frame);
    } else {
      draw();
    }

    return () => {
      cancelAnimationFrame(raf);
      cv.removeEventListener("pointerenter", enter);
      cv.removeEventListener("pointerleave", leave);
    };
  }, [name, scale]);

  return <canvas ref={ref} data-s={name} className={className} aria-hidden="true" />;
}
