"use client";

import Image from "next/image";
import { useLang } from "@/lib/i18n";
import Reveal from "./Reveal";
import VoxelSprite from "./VoxelSprite";
import DemoStage from "./Demo";

const DL = "https://github.com/akbarsiddic/recatch/releases/latest";
const GH = "https://github.com/akbarsiddic/recatch";

function Brand({ src, alt, size = 16 }: { src: string; alt: string; size?: number }) {
  return (
    <Image
      src={src}
      alt={alt}
      width={size}
      height={size}
      unoptimized
      style={{ objectFit: "contain" }}
    />
  );
}

/* ---------------------------------- Hero ---------------------------------- */
export function Hero() {
  const lang = useLang();
  const id = lang === "id";
  return (
    <section className="hero">
      <div className="wrap">
        <div className="hero-grid">
          <div>
            <span className="badge">
              <span className="dot" />
              {id ? "Gratis · Sumber terbuka · macOS" : "Free · Open source · macOS"}
            </span>
            <h1>
              {id ? (
                <>Lagi melamun? <em>recatch</em> yang nangkep.</>
              ) : (
                <>Spaced out? <em>recatch</em> caught it.</>
              )}
            </h1>
            <p className="sub">
              {id
                ? "Kamu sudah bisa mendengar rapatnya. recatch menjelaskan maksudnya — ringkasan langsung saat kamu menyimak, kejar ketinggalan saat melamun, dan jawaban saat kamu bertanya."
                : "You can hear the meeting. recatch tells you what it means — a live summary while you listen, a catch-up when you drift, and answers when you ask."}
            </p>
            <div className="acts">
              <a className="btn p" href={DL}>
                {id ? "Unduh untuk macOS" : "Download for macOS"}
              </a>
              <a className="btn s" href="#how">
                {id ? "Lihat cara kerjanya" : "See how it works"}
              </a>
            </div>
            <p className="note mono">
              <b>{id ? "Gratis & sumber terbuka" : "Free & open source"}</b> · Apple Silicon · macOS 14+
            </p>
          </div>
          <DemoStage />
        </div>
      </div>
    </section>
  );
}

/* ------------------------------ How it works ------------------------------ */
export function HowItWorks() {
  const lang = useLang();
  const id = lang === "id";
  return (
    <section className="sec" id="how">
      <div className="wrap">
        <div className="sec-head">
          <h2>{id ? "Semua dalam satu panel melayang." : "Everything in one floating panel."}</h2>
          <p className="lead">
            {id ? (
              <>recatch ada di menu bar kamu. Tekan <kbd>⌥⌘R</kbd> dan satu panel memberi tahu apa yang sedang terjadi, apa yang terlewat, dan menjawab pertanyaanmu.</>
            ) : (
              <>recatch lives in your menu bar. Press <kbd>⌥⌘R</kbd> and one panel tells you what&apos;s happening, what you missed, and answers what you ask.</>
            )}
          </p>
        </div>
        <div className="steps">
          <Reveal>
            <div className="step">
              <div className="step-top">
                <span className="no">01</span>
                <VoxelSprite name="wave" scale={1.5} />
              </div>
              <h3>{id ? "Mulai mendengarkan" : "Start listening"}</h3>
              <p>
                {id
                  ? "Satu klik di menu bar. recatch menyalin suara di Mac kamu dengan Whisper — tidak ada yang masuk ke panggilanmu."
                  : "One click in the menu bar. recatch transcribes on your Mac with Whisper — nothing joins your call."}
              </p>
            </div>
          </Reveal>
          <Reveal>
            <div className="step">
              <div className="step-top">
                <span className="no">02</span>
                <VoxelSprite name="clock" scale={1.5} />
              </div>
              <h3>{id ? "Kejar ketinggalan kapan saja" : "Catch up anytime"}</h3>
              <p>
                {id ? (
                  <>Melamun semenit? Tekan <kbd>⌥⌘R</kbd> untuk ringkasan berstempel waktu: keputusan, pertanyaan terbuka, dan hal yang ditujukan kepadamu.</>
                ) : (
                  <>Drifted for a minute? Press <kbd>⌥⌘R</kbd> for a timestamped summary: decisions, open questions, and what&apos;s aimed at you.</>
                )}
              </p>
            </div>
          </Reveal>
          <Reveal>
            <div className="step">
              <div className="step-top">
                <span className="no">03</span>
                <VoxelSprite name="chat" scale={1.5} />
              </div>
              <h3>{id ? "Tanya rapatnya" : "Ask the meeting"}</h3>
              <p>
                {id
                  ? "Tanya apa saja. Jawabannya langsung dari transkrip, dalam bahasa rapatnya."
                  : "Ask anything. The answer comes straight from the transcript, in the meeting's own language."}
              </p>
            </div>
          </Reveal>
        </div>
      </div>
    </section>
  );
}

/* -------------------------------- Features -------------------------------- */
export function Features() {
  const lang = useLang();
  const id = lang === "id";
  return (
    <section className="sec">
      <div className="wrap">
        <Reveal>
          <div className="row">
            <div>
              <div className="kicker">{id ? "Sekarang" : "Right now"}</div>
              <h2>{id ? "Ringkasan langsung, bukan tembok kata." : "A live summary, not a wall of words."}</h2>
              <p>
                {id
                  ? "Kamu sudah bisa mendengar rapatnya. Jadi alih-alih teks berjalan, recatch menampilkan ringkasan langsung tentang apa yang terjadi — lirik sebentar, lalu lanjut kerja."
                  : "You can already hear the meeting. So instead of captions, recatch shows a live summary of what's happening — glance, then get back to work."}
              </p>
            </div>
            <div className="vis">
              <Image src="/assets/overlay.png" alt="recatch live NOW summary" width={952} height={886} />
            </div>
          </div>
        </Reveal>
        <Reveal>
          <div className="row rev">
            <div>
              <div className="kicker">{id ? "Kejar ketinggalan" : "Catch me up"}</div>
              <h2>{id ? "Kejar ketinggalan dalam hitungan detik." : "Catch me up in seconds."}</h2>
              <p>
                {id
                  ? "Ketinggalan beberapa menit? Satu tekan memberi kamu keputusan dan pertanyaan terbuka, berstempel waktu. Tidak ada yang tahu kamu melamun."
                  : "Missed a few minutes? One press gives you the decisions and open questions, timestamped. Nobody has to know you drifted."}
              </p>
            </div>
            <div className="vis slim">
              <Image src="/assets/overlay-collapsed.png" alt="recatch collapsed to a single live summary line" width={712} height={240} />
            </div>
          </div>
        </Reveal>
        <Reveal>
          <div className="row">
            <div>
              <div className="kicker">{id ? "Tanya" : "Ask"}</div>
              <h2>{id ? "Tanya rapatnya." : "Ask the meeting."}</h2>
              <p>
                {id
                  ? "Tanya apa saja dan dapatkan jawaban dari transkrip, dalam bahasa rapat. recatch tidak menerjemahkan."
                  : "Ask anything and get an answer from the transcript, in the meeting's language. recatch doesn't translate."}
              </p>
            </div>
            <div className="vis">
              <Image src="/assets/chat.png" alt="recatch Ask chat thread" width={1520} height={576} />
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

/* --------------------------------- Privacy --------------------------------- */
function PrivacyIcon({ name }: { name: "lock" | "shield" | "clock" | "key" }) {
  if (name === "lock") {
    return (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
        <rect x="5" y="11" width="14" height="9" rx="2" />
        <path d="M8 11V8a4 4 0 0 1 8 0v3" />
      </svg>
    );
  }
  if (name === "shield") {
    return (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 3l7 3v5c0 4.6-3 7.6-7 9-4-1.4-7-4.4-7-9V6l7-3z" />
        <path d="M9 12l2 2 4-4" />
      </svg>
    );
  }
  if (name === "clock") {
    return (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="12" r="8.5" />
        <path d="M12 7.5V12l3 2" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="7.5" cy="15.5" r="3.5" />
      <path d="M10.5 12.5L19 4M14.5 8.5l2 2" />
    </svg>
  );
}

export function Privacy() {
  const lang = useLang();
  const id = lang === "id";
  const facts: { icon: "lock" | "shield" | "clock" | "key"; title: string; body: string; wide?: boolean }[] = [
    {
      icon: "lock",
      title: id ? "Audio tidak pernah keluar dari Mac kamu." : "Audio never leaves your Mac.",
      body: id ? "Pengenalan suara berjalan di perangkat dengan Whisper." : "Speech recognition runs on-device with Whisper.",
    },
    {
      icon: "shield",
      title: id ? "Tanpa bot, tanpa akun." : "No bots, no accounts.",
      body: id ? "Tidak ada yang bergabung ke panggilanmu dan tidak ada yang diunggah." : "Nothing joins your call and nothing is uploaded.",
    },
    {
      icon: "clock",
      title: id ? "Hanya yang kamu tanyakan yang dikirim." : "Only what you ask is sent.",
      body: id
        ? "Potongan transkrip dikirim ke penyedia pilihanmu — dicatat lokal berdasarkan waktu dan ukuran, tidak pernah isinya."
        : "The transcript window goes to the provider you choose — logged locally by time and size, never content.",
    },
    {
      icon: "key",
      title: id ? "Transkrip kedaluwarsa." : "Transcripts expire.",
      body: id ? "Disimpan lokal, dihapus setelah 3 hari secara bawaan." : "Stored locally, deleted after 3 days by default.",
    },
    {
      icon: "shield",
      title: id ? "Kunci tetap di Keychain kamu." : "Keys stay in your Keychain.",
      body: id ? "Tidak pernah di preferensi atau log." : "Never in preferences or logs.",
      wide: true,
    },
  ];
  return (
    <section className="sec" id="privacy">
      <div className="wrap">
        <div className="priv">
          <div className="sec-head center">
            <h2>{id ? "Audiomu tetap di Mac ini." : "Your audio stays on this Mac."}</h2>
            <p className="lead">
              {id
                ? "Privasi bukan halaman pengaturan — melainkan cara recatch dibangun. Semua di daftar ini adalah cara aplikasi bekerja saat ini."
                : "Privacy isn't a settings page — it's how recatch is built. Everything on this list is how the app works today."}
            </p>
          </div>
          <ul className="facts">
            {facts.map((f, i) => (
              <li key={i} className={f.wide ? "wide" : undefined}>
                <span className="ic">
                  <PrivacyIcon name={f.icon} />
                </span>
                <span>
                  <b>{f.title}</b> {f.body}
                </span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}

/* --------------------------- Bring your own brain -------------------------- */
export function BringYourOwnBrain() {
  const lang = useLang();
  const id = lang === "id";
  const rows = [
    { nm: "Claude Pro", sub: id ? "skrip & penalaran" : "scripts & reasoning", pr: "$20/mo", logo: "/brands/claude.svg" },
    { nm: "ChatGPT Plus", sub: id ? "chat & penalaran" : "chat & reasoning", pr: "$20/mo", logo: "/brands/openai.svg" },
    { nm: "Groq", sub: id ? "inferensi cepat" : "fast inference", pr: id ? "pemakaian" : "usage", logo: "/brands/groq.svg" },
    { nm: "DeepSeek", sub: id ? "penalaran" : "reasoning", pr: id ? "pemakaian" : "usage", logo: "/brands/deepseek.svg" },
  ];
  const chips = [
    { name: "Groq", logo: "/brands/groq.svg" },
    { name: "Claude Code", logo: "/brands/claude.svg" },
    { name: "opencode", logo: "/brands/opencode.svg" },
    { name: "Gemini CLI", logo: "/brands/googlegemini.svg" },
    { name: "Codex", logo: "/brands/openai.svg" },
    { name: "DeepSeek", logo: "/brands/deepseek.svg" },
    { name: "OpenAI", logo: "/brands/openai.svg" },
    { name: id ? "endpoint kompatibel OpenAI apa pun" : "any OpenAI-compatible endpoint", logo: null },
  ];
  return (
    <section className="sec" id="brain">
      <div className="wrap">
        <div className="sec-head center">
          <h2>{id ? "Pakai otakmu sendiri." : "Bring your own brain."}</h2>
          <p className="lead">
            {id
              ? "Kamu sudah berlangganan AI. recatch menyambungkannya — dan aplikasinya tetap gratis."
              : "You already pay for an AI. recatch plugs into it — and the app stays free."}
          </p>
        </div>
        <div className="brain-grid">
          <div className="brain-col">
            <div className="ttl">{id ? "Otak yang sudah kamu bayar" : "The brains you already pay for"}</div>
            <div className="brain-list">
              {rows.map((r) => (
                <div className="brain-item" key={r.nm}>
                  <div className="brain-left">
                    <span className="brain-logo">
                      <Brand src={r.logo} alt={r.nm} />
                    </span>
                    <span className="nm">
                      {r.nm}
                      <small>{r.sub}</small>
                    </span>
                  </div>
                  <span className="pr">{r.pr}</span>
                </div>
              ))}
            </div>
            <div className="brain-total">
              <span>{id ? "Kunci API apa pun, atau agen CLI" : "Any API key, or a CLI agent"}</span>
              <span>{id ? "sudah punya" : "yours already"}</span>
            </div>
          </div>
          <div className="recatch-card">
              <span className="free">{id ? "Gratis & sumber terbuka" : "Free & open source"}</span>
              <div className="price" style={{ marginTop: 16 }}>
                $0<small>{id ? " / selamanya" : " / forever"}</small>
              </div>
              <h3>recatch</h3>
              <p>
                {id
                  ? "Pendamping rapat. Kejar ketinggalan dan bertanya, didukung AI yang sudah kamu bayar. Tanpa langganan untuk aplikasinya."
                  : "The meeting companion. Catch up and ask, powered by the AI you already pay for. No subscription for the app."}
              </p>
              <a className="btn" href={DL}>
                {id ? "Unduh gratis" : "Download free"}
              </a>
            </div>
        </div>
        <div className="chips" style={{ justifyContent: "center" }}>
          {chips.map((c) => (
            <span key={c.name}>
              {c.logo ? <Brand src={c.logo} alt={c.name} /> : null}
              {c.name}
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}

/* --------------------------------- Download -------------------------------- */
export function Download() {
  const lang = useLang();
  const id = lang === "id";
  return (
    <section className="sec" id="download">
      <div className="wrap">
        <div className="download">
          <h2>{id ? "Unduh untuk macOS." : "Download for macOS."}</h2>
          <p className="lead">
            {id
              ? "Gratis dan sumber terbuka. Tanpa akun, tanpa bot di panggilanmu. Kejar ketinggalan setiap rapat dari menu bar."
              : "Free and open source. No account, no bots in your calls. Catch up on every meeting from your menu bar."}
          </p>
          <a className="btn p" href={DL}>
            {id ? "Unduh untuk macOS" : "Download for macOS"}
          </a>
          <p className="req mono">
            <b>Apple Silicon</b> · macOS 14+ ·{" "}
            {id ? "jalan pertama mengunduh model suara (~140 MB)" : "first run downloads a speech model (~140 MB)"}
          </p>
          <p className="alt">
            {id ? "Mau membangun sendiri? " : "Prefer to build it yourself? "}
            <a href={GH}>{id ? "Sumbernya ada di GitHub" : "The source is on GitHub"}</a>.
          </p>
        </div>
      </div>
    </section>
  );
}

/* ----------------------------------- FAQ ----------------------------------- */
export function Faq() {
  const lang = useLang();
  const id = lang === "id";
  const items = [
    {
      q: id ? "recatch itu apa?" : "What is recatch?",
      a: id
        ? "Aplikasi macOS gratis dan sumber terbuka yang mendengarkan rapatmu di mesinmu sendiri. Tekan satu tombol dan dia memberi tahu apa yang sedang dibahas dan apa yang terlewat."
        : "A free, open-source macOS app that listens to your meeting on your own machine. Press a key and it tells you what's happening and what you missed.",
    },
    {
      q: id ? "Sudah bisa dipakai?" : "Can I use it today?",
      a: id
        ? "Bisa. Unduh aplikasi macOS-nya — gratis dan sumber terbuka dengan lisensi MIT. Ini versi awal, jadi wajar ada yang kasar, dan beri tahu kami apa yang rusak."
        : "Yes. Download the macOS app — it's free and open source under the MIT license. It's an early version, so expect rough edges and tell us what breaks.",
    },
    {
      q: id ? "Audioku ke mana?" : "Where does my audio go?",
      a: id
        ? "Tidak ke mana-mana. Pengenalan suara berjalan di perangkatmu dengan Whisper. Hanya potongan transkrip yang kamu tanyakan yang dikirim ke penyedia pilihanmu."
        : "Nowhere. Speech recognition runs on your device with Whisper. Only the transcript window you ask about goes to the provider you choose.",
    },
    {
      q: id ? "Apakah menerjemahkan?" : "Does it translate?",
      a: id
        ? "Tidak. Jawaban mengikuti bahasa rapat. Bahasa campur? Pilih bahasa rapat di pengaturan."
        : "No. Answers follow the meeting's language. Mixed languages? Pick your meeting language in settings.",
    },
    {
      q: id ? "AI apa yang bisa kupakai?" : "What AI can I use?",
      a: id
        ? "Groq sudah bisa hari ini. Claude Code, opencode, Gemini CLI, Codex, DeepSeek, dan endpoint kompatibel OpenAI apa pun sudah tersambung — bawa kunci atau agenmu sendiri."
        : "Groq works today. Claude Code, opencode, Gemini CLI, Codex, DeepSeek, and any OpenAI-compatible endpoint are wired in — bring your own key or agent.",
    },
    {
      q: id ? "Berapa lama transkrip disimpan?" : "How long are transcripts kept?",
      a: id
        ? "3 hari secara bawaan, hanya di Mac kamu. Ubah, atau hapus semuanya, di pengaturan."
        : "3 days by default, stored only on your Mac. Change that, or delete everything, in settings.",
    },
    {
      q: id ? "Kenapa Mac memberi peringatan saat membukanya?" : "Why does my Mac warn me when I open it?",
      a: id
        ? "Beta-nya belum dinotarisasi Apple, jadi macOS belum bisa memastikan pembuatnya. Sumbernya publik di GitHub kalau kamu mau memeriksanya sendiri."
        : "The beta isn't notarized by Apple yet, so macOS can't confirm who made it. The source is public on GitHub if you'd rather check it yourself.",
    },
  ];
  return (
    <section className="sec" id="faq">
      <div className="wrap">
        <div className="sec-head center">
          <h2>{id ? "Pertanyaan, dijawab." : "Questions, answered."}</h2>
        </div>
        <div className="faq">
          {items.map((it) => (
            <details key={it.q}>
              <summary>{it.q}</summary>
              <p>{it.a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
