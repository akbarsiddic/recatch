"use client";

import { useSyncExternalStore } from "react";
import { useLang, setLang } from "@/lib/i18n";
import VoxelSprite from "./VoxelSprite";

const DL = "https://github.com/akbarsiddic/recatch/releases/latest";

function useDarkMode() {
  return useSyncExternalStore(
    (cb) => {
      const mq = matchMedia("(prefers-color-scheme: dark)");
      mq.addEventListener("change", cb);
      return () => mq.removeEventListener("change", cb);
    },
    () => matchMedia("(prefers-color-scheme: dark)").matches,
    () => false
  );
}

export default function Header() {
  const lang = useLang();
  const t = lang === "id";
  const dark = useDarkMode();

  return (
    <header>
      <div className="wrap">
        <a href="#top" aria-label="recatch">
          <VoxelSprite name="wordmark" scale={1.3} className="nav-wm" color={dark ? "#F7F2E8" : "#1B1620"} />
        </a>
        <nav>
          <a href="#how">{t ? "Cara kerja" : "How it works"}</a>
          <a href="#privacy">{t ? "Privasi" : "Privacy"}</a>
          <a href="#brain">{t ? "AI kamu" : "Your AI"}</a>
          <a href="#faq">{t ? "Tanya jawab" : "FAQ"}</a>
        </nav>
        <div className="head-cta">
          <span className="lang" role="group" aria-label="Language">
            <button type="button" aria-pressed={lang === "en"} onClick={() => setLang("en")}>
              EN
            </button>
            <button type="button" aria-pressed={lang === "id"} onClick={() => setLang("id")}>
              ID
            </button>
          </span>
          <a className="btn p sm" href={DL}>
            {t ? "Unduh" : "Download"}
          </a>
        </div>
      </div>
    </header>
  );
}
