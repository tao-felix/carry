/** The Carry mark: an italic Instrument Serif C carrying a dot. Same shape as brand/mark.svg. */
export function Mark({ size = 18, className = "" }: { size?: number; className?: string }) {
  return (
    <svg viewBox="0 0 1024 1024" width={size} height={size} aria-hidden="true" className={className}>
      <path transform="translate(288.92 793.19) scale(0.78000 -0.78000)" d="M256 -9Q150 -9 102.5 58.0Q55 125 55 252Q55 313 70.0 379.0Q85 445 113.5 507.5Q142 570 182.0 620.0Q222 670 272.5 700.0Q323 730 382 730Q452 730 509 683Q519 675 516 661L486 510Q483 494 471 494Q459 494 459 510L458 549Q456 632 434.0 667.0Q412 702 371 702Q332 702 296.0 670.5Q260 639 229.0 586.5Q198 534 174.5 470.5Q151 407 138.0 343.0Q125 279 125 224Q125 134 152.5 77.0Q180 20 244 20Q282 20 311.5 47.5Q341 75 372 142L394 189Q399 201 409 201Q425 201 420 182L380 26Q376 11 364 8Q347 2 315.0 -3.5Q283 -9 256 -9Z" className="fill-ink stroke-ink" strokeWidth="40" strokeLinejoin="round"/>
      <circle cx="585.32" cy="656.69" r="60.84" className="fill-tangerine"/>
    </svg>
  );
}
