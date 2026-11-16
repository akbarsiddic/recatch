import type { Metadata } from "next";
import { Fraunces, Plus_Jakarta_Sans } from "next/font/google";
import "./globals.css";

const fraunces = Fraunces({
  subsets: ["latin"],
  weight: ["600", "700"],
  style: ["normal", "italic"],
  variable: "--font-fraunces",
  display: "swap",
});

const jakarta = Plus_Jakarta_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
  variable: "--font-jakarta",
  display: "swap",
});

export const metadata: Metadata = {
  title: "recatch — spaced out? recatch caught it",
  description:
    "recatch is a free, open-source macOS meeting companion. A live summary while you listen, a catch-up when you drift, and answers when you ask. Audio never leaves your Mac.",
  openGraph: {
    title: "recatch — spaced out? recatch caught it",
    description:
      "A free, open-source macOS meeting companion. Live summary, catch-up, and answers — with your audio staying on your Mac.",
    type: "website",
  },
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${fraunces.variable} ${jakarta.variable}`}>
      <body>{children}</body>
    </html>
  );
}
