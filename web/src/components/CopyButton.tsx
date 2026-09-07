"use client";

import { useEffect, useState } from "react";

export function CopyButton({
  text,
  label = "Copy",
  className = "",
}: {
  text: string;
  label?: string;
  className?: string;
}) {
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!copied) return;
    const t = setTimeout(() => setCopied(false), 1600);
    return () => clearTimeout(t);
  }, [copied]);

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
    } catch {
      // Clipboard can be unavailable (insecure context). Fall back to selecting nothing;
      // the text is visible right next to the button.
      setCopied(false);
    }
  }

  return (
    <button
      type="button"
      onClick={copy}
      aria-live="polite"
      className={`inline-flex h-8 shrink-0 items-center gap-1.5 rounded-[8px] border border-line bg-paper px-2.5 font-mono text-mono-sm text-ink2 transition-colors duration-150 hover:border-ink2 hover:text-ink ${className}`}
    >
      {copied ? (
        <>
          <svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true" className="stroke-ok" fill="none" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 8.5l3 3 7-7" />
          </svg>
          <span className="text-ok">Copied</span>
        </>
      ) : (
        <>
          <svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true" className="stroke-current" fill="none" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
            <rect x="5.5" y="5.5" width="8" height="8" rx="1.5" />
            <path d="M10.5 5.5v-2a1 1 0 0 0-1-1h-6a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2" />
          </svg>
          <span>{label}</span>
        </>
      )}
    </button>
  );
}
