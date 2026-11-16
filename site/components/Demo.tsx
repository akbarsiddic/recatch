"use client";

import { useEffect, useRef } from "react";
import { useLang } from "@/lib/i18n";
import Wordmark from "./Wordmark";

export default function Demo() {
  const lang = useLang();
  const id = lang === "id";

  const stageRef = useRef<HTMLDivElement>(null);
  const cursorRef = useRef<HTMLDivElement>(null);
  const catchRef = useRef<HTMLButtonElement>(null);
  const summaryRef = useRef<HTMLDivElement>(null);
  const askRef = useRef<HTMLDivElement>(null);
  const fieldRef = useRef<HTMLSpanElement>(null);
  const sendRef = useRef<HTMLButtonElement>(null);
  const qRef = useRef<HTMLDivElement>(null);
  const aRef = useRef<HTMLDivElement>(null);

  const copy = {
    question: id ? "Priya minta apa ke saya?" : "What did Priya ask me?",
    answer: id
      ? "Konfirmasi tanggal rilis 12 September ke tim desain (12:22)."
      : "Confirm the September 12 launch date with the design team (12:22).",
  };

  useEffect(() => {
    const stage = stageRef.current;
    const cur = cursorRef.current;
    const catchBtn = catchRef.current;
    const summary = summaryRef.current;
    const ask = askRef.current;
    const field = fieldRef.current;
    const send = sendRef.current;
    const q = qRef.current;
    const a = aRef.current;
    if (!stage || !cur || !catchBtn || !summary || !ask || !field || !send || !q || !a) return;

    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      summary.classList.add("show");
      q.textContent = copy.question;
      q.classList.add("show");
      a.textContent = copy.answer;
      a.classList.add("show");
      return;
    }

    let token = 0;
    const t = ++token;
    const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
    const z = (ms: number) => sleep(ms).then(() => { if (t !== token) throw 0; });

    const go = async (el: HTMLElement) => {
      const s = stage.getBoundingClientRect();
      const r = el.getBoundingClientRect();
      cur.style.transform = `translate(${r.left - s.left + r.width / 2}px, ${r.top - s.top + r.height / 2}px)`;
      await z(700);
    };
    const click = async () => {
      cur.classList.add("down");
      await z(220);
      cur.classList.remove("down");
    };
    const type = async (text: string) => {
      field.textContent = "";
      field.classList.remove("ph");
      for (let i = 0; i < text.length; i++) {
        field.textContent += text[i];
        await z(42);
      }
    };

    (async () => {
      cur.style.transform = "translate(60px, 50px)";
      while (t === token) {
        try {
          // reset
          summary.classList.remove("show");
          q.classList.remove("show");
          q.textContent = "";
          a.classList.remove("show");
          a.textContent = "";
          field.textContent = "";
          field.classList.add("ph");
          await z(500);

          // 1. click "Catch me up"
          await go(catchBtn);
          await click();
          catchBtn.classList.add("active");
          summary.classList.add("show");
          await z(1700);
          catchBtn.classList.remove("active");

          // 2. type a question
          await go(ask);
          await click();
          await type(copy.question);
          await z(350);

          // 3. click send
          await go(send);
          await click();
          q.textContent = copy.question;
          q.classList.add("show");
          field.textContent = "";
          field.classList.add("ph");
          a.textContent = "···";
          a.classList.add("show");
          await z(650);
          a.textContent = "";
          for (let i = 0; i < copy.answer.length; i++) {
            a.textContent += copy.answer[i];
            await z(24);
          }
          await z(2600);
        } catch {
          break;
        }
      }
    })();

    return () => { token++; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  return (
    <section className="sec" id="demo" style={{ paddingTop: 8 }}>
      <div className="wrap">
        <div className="sec-head center">
          <h2>{id ? "Lihat langsung." : "See it in action."}</h2>
          <p className="lead">
            {id
              ? "Beginilah recatch saat rapat sungguhan — kursor memainkan alurnya: kejar ketinggalan, lalu bertanya."
              : "This is recatch during a real meeting — the cursor plays through the flow: catch up, then ask."}
          </p>
        </div>

        <div className="demo-stage" ref={stageRef}>
          <div className="demo-cursor" ref={cursorRef} aria-hidden="true">
            <svg width="22" height="22" viewBox="0 0 24 24">
              <path d="M4 2l16 9-7 2-3 7z" fill="#1B1620" stroke="#FBF8F1" strokeWidth="1.8" strokeLinejoin="round" />
            </svg>
            <i className="demo-ring" />
          </div>

          <div className="demo-panel">
            <div className="demo-head">
              <span className="wm" style={{ height: 15 }}>
                <Wordmark />
              </span>
              <span className="demo-pill">
                <span className="dot" />
                {id ? "Mendengarkan 0:32" : "Listening 0:32"}
              </span>
            </div>

            <div className="demo-body">
              <div className="demo-now">
                <span className="demo-lbl">{id ? "Sekarang" : "Right now"}</span>
                <p>{id ? "Priya sedang membahas jadwal rilis kuartal tiga." : "Priya is walking through the Q3 launch timeline."}</p>
              </div>

              <div className="demo-summary">
                <div className="demo-summary-head">
                  <span className="demo-lbl">{id ? "Kejar ketinggalan" : "Catch me up"}</span>
                  <button className="demo-catch" ref={catchRef} aria-label="Catch me up">
                    ↻
                  </button>
                </div>
                <div className="demo-summary-body" ref={summaryRef}>
                  <b>{id ? "Rilis pindah ke 12 September" : "Launch moved to September 12"}</b>{" "}
                  {id
                    ? "(12:04) · Desain dibekukan — naskah masih menunggu (12:18)"
                    : "(12:04) · Design freeze approved — copy still pending (12:18)"}
                </div>
              </div>

              <div className="demo-chat">
                <div className="demo-q" ref={qRef} />
                <div className="demo-a" ref={aRef} />
              </div>

              <div className="demo-ask" ref={askRef}>
                <span className="demo-ask-field ph" ref={fieldRef} data-ph="">
                  {id ? "Tanya soal rapat…" : "Ask about the meeting…"}
                </span>
                <button className="demo-send" ref={sendRef} aria-label="Send">
                  ↵
                </button>
              </div>
            </div>
          </div>
        </div>

        <p className="note" style={{ textAlign: "center", maxWidth: 520, margin: "24px auto 0" }}>
          {id
            ? "Video rekaman asli akan menggantikan demo animasi ini di sini."
            : "The recorded walkthrough video will live right here, in place of this animated demo."}
        </p>
      </div>
    </section>
  );
}
