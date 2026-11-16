"use client";

import { useLang, setLang } from "@/lib/i18n";
import Wordmark from "./Wordmark";

const DL = "https://github.com/akbarsiddic/recatch/releases/latest";

export default function Header() {
  const lang = useLang();
  const t = lang === "id";

  return (
    <header>
      <div className="wrap">
        <a href="#top" aria-label="recatch" className="wm">
          <Wordmark />
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
