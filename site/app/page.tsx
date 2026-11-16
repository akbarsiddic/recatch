import Header from "@/components/Header";
import Cursor from "@/components/Cursor";
import Footer from "@/components/Footer";
import Demo from "@/components/Demo";
import {
  Hero,
  HowItWorks,
  Features,
  Privacy,
  BringYourOwnBrain,
  Download,
  Faq,
} from "@/components/sections";

export default function Page() {
  return (
    <>
      <Header />
      <main id="top">
        <Hero />
        <Demo />
        <HowItWorks />
        <Features />
        <Privacy />
        <BringYourOwnBrain />
        <Download />
        <Faq />
      </main>
      <Footer />
      <Cursor />
    </>
  );
}
