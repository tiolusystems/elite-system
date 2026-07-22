"use client";

import { usePathname } from "next/navigation";
import { useState } from "react";

import { manualForPath } from "@/lib/manuals";

export function ManualTrigger() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const manual = manualForPath(pathname);
  if (!manual) return null;

  return (
    <>
      <button className="manual-trigger" type="button" onClick={() => setOpen(true)} aria-label={`Abrir manual de ${manual.title}`}>
        <span aria-hidden="true">?</span>
        <span>Como usar</span>
      </button>
      {open ? (
        <div className="manual-dialog-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
          <section className="manual-dialog" role="dialog" aria-modal="true" aria-labelledby="manual-title" onMouseDown={(event) => event.stopPropagation()}>
            <header>
              <div><span className="eyebrow">{manual.module}</span><h2 id="manual-title">{manual.title}</h2></div>
              <button type="button" aria-label="Fechar manual" onClick={() => setOpen(false)}>×</button>
            </header>
            <ManualSection title="O que esta tela faz" items={[manual.purpose]} />
            <ManualSection title="Antes de comecar" items={manual.before} />
            <ManualSection title="Como executar" items={manual.steps} ordered />
            <ManualSection title="O que acontece depois" items={manual.after} />
            <ManualSection title="Quem pode executar" items={manual.roles} />
            <ManualSection title="Erros e bloqueios" items={manual.blockers} />
            <ManualSection title="Dados e historico gerados" items={manual.records} />
          </section>
        </div>
      ) : null}
    </>
  );
}

function ManualSection({ title, items, ordered = false }: { title: string; items: string[]; ordered?: boolean }) {
  const List = ordered ? "ol" : "ul";
  return <section><h3>{title}</h3><List>{items.map((item) => <li key={item}>{item}</li>)}</List></section>;
}
