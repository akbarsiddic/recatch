"use client";

import { useEffect, useRef } from "react";

export default function Cursor() {
  const cur = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const root = cur.current;
    if (!root) return;
    if (
      matchMedia("(prefers-reduced-motion: reduce)").matches ||
      matchMedia("(pointer: coarse)").matches
    ) {
      return;
    }
    const ring = root.querySelector(".ring") as HTMLElement | null;
    let tx = innerWidth / 2,
      ty = innerHeight / 2,
      x = tx,
      y = ty,
      sc = 0.5,
      tsc = 0.5,
      vis = false;

    const move = (e: MouseEvent) => {
      tx = e.clientX;
      ty = e.clientY;
    };
    const down = () => (tsc = 0.9);
    const up = () => (tsc = 0.5);
    const enter = () => (vis = true);
    const leave = () => (vis = false);

    addEventListener("mousemove", move);
    addEventListener("mousedown", down);
    addEventListener("mouseup", up);
    addEventListener("mouseenter", enter);
    addEventListener("mouseleave", leave);

    let raf = 0;
    const step = () => {
      x += (tx - x) * 0.18;
      y += (ty - y) * 0.18;
      sc += (tsc - sc) * 0.2;
      root.style.transform = `translate(${x}px, ${y}px)`;
      if (ring) {
        ring.style.transform = `scale(${sc})`;
        ring.style.opacity = vis ? "1" : "0";
      }
      raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);

    return () => {
      cancelAnimationFrame(raf);
      removeEventListener("mousemove", move);
      removeEventListener("mousedown", down);
      removeEventListener("mouseup", up);
      removeEventListener("mouseenter", enter);
      removeEventListener("mouseleave", leave);
    };
  }, []);

  return (
    <div id="cursor" ref={cur} aria-hidden="true">
      <div className="ring" />
      <div className="dot" />
    </div>
  );
}
