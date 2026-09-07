/** The Carry mark: a luggage tag. Same shape as app/icon.svg. */
export function Mark({ size = 18, className = "" }: { size?: number; className?: string }) {
  return (
    <svg
      viewBox="0 0 32 32"
      width={size}
      height={size}
      aria-hidden="true"
      className={className}
    >
      <path
        d="M16 2.5 L26.5 12 V26 a3 3 0 0 1 -3 3 H8.5 a3 3 0 0 1 -3 -3 V12 Z"
        className="fill-tangerine"
      />
      <circle cx="16" cy="11.5" r="2.4" className="fill-paper" />
    </svg>
  );
}
