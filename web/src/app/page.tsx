import { Nav } from "@/components/Nav";
import { Hero } from "@/components/Hero";
import { ContextFile } from "@/components/ContextFile";
import { HowItWorks } from "@/components/HowItWorks";
import { Sources } from "@/components/Sources";
import { Privacy } from "@/components/Privacy";
import { Pro } from "@/components/Pro";
import { ForAgents } from "@/components/ForAgents";
import { Footer } from "@/components/Footer";

export default function Page() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <ContextFile />
        <HowItWorks />
        <Sources />
        <Privacy />
        <Pro />
        <ForAgents />
      </main>
      <Footer />
    </>
  );
}
