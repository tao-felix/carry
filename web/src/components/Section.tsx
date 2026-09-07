import type { ReactNode } from "react";

/** Page-wide horizontal container: max 1040, generous gutters. */
export function Container({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={`mx-auto w-full max-w-[1040px] px-5 sm:px-8 ${className}`}>
      {children}
    </div>
  );
}

/** A numbered page section with a serif heading and an optional one-line lede. */
export function Section({
  id,
  number,
  title,
  lede,
  children,
  className = "",
}: {
  id?: string;
  number: string;
  title: ReactNode;
  lede?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section
      id={id}
      className={`scroll-mt-20 border-t border-line py-16 sm:py-24 ${className}`}
    >
      <Container>
        <header className="mb-10 grid gap-3 sm:mb-14 sm:grid-cols-[120px_1fr] sm:gap-8">
          <p className="font-mono text-mono-sm text-ink2">{number}</p>
          <div className="max-w-[640px]">
            <h2 className="font-serif text-[28px] leading-[34px] tracking-[-0.005em] sm:text-h2">
              {title}
            </h2>
            {lede ? (
              <p className="mt-3 text-body text-ink2">{lede}</p>
            ) : null}
          </div>
        </header>
        {children}
      </Container>
    </section>
  );
}
