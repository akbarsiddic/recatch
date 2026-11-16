"use client";

import { useSyncExternalStore } from "react";

export type Lang = "en" | "id";

const KEY = "rc-lang";
const listeners = new Set<() => void>();

function readInitial(): Lang {
  try {
    const v = localStorage.getItem(KEY);
    if (v === "id" || v === "en") return v;
  } catch {
    /* ignore */
  }
  if (typeof navigator !== "undefined" && navigator.language?.toLowerCase().startsWith("id")) {
    return "id";
  }
  return "en";
}

// Server renders English; the client switches after hydration without a mismatch.
function getServerSnapshot(): Lang {
  return "en";
}

function getSnapshot(): Lang {
  if (typeof window === "undefined") return "en";
  return readInitial();
}

function subscribe(cb: () => void) {
  listeners.add(cb);
  return () => {
    listeners.delete(cb);
  };
}

export function setLang(l: Lang) {
  try {
    localStorage.setItem(KEY, l);
  } catch {
    /* ignore */
  }
  document.documentElement.lang = l;
  listeners.forEach((cb) => cb());
}

export function useLang(): Lang {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
