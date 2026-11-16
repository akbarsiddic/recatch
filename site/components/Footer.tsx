"use client";

import { useLang } from "@/lib/i18n";
import Wordmark from "./Wordmark";

export default function Footer() {
  const lang = useLang();
  const id = lang === "id";
  return (
    <footer>
      <div className="wrap">
        <div className="l">
          <span className="wm" style={{ height: 19 }}>
            <Wordmark />
          </span>
          <span>{id ? "Gratis & sumber terbuka dengan lisensi MIT." : "Free & open source under the MIT license."}</span>
        </div>
        <div className="r">
          <a href="https://github.com/akbarsiddic/recatch">GitHub</a>
          <a href="https://github.com/akbarsiddic/recatch/issues">{id ? "Masalah" : "Issues"}</a>
          <a href="https://github.com/akbarsiddic/recatch/blob/main/LICENSE">License</a>
        </div>
      </div>
    </footer>
  );
}
