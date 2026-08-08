/** Inline Sonoran Forge mark — desert sun + anvil + hammer */
export default function SonoranForgeLogo({ size = 36, className = '' }) {
  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 64 64"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Sonoran Forge"
    >
      <defs>
        <linearGradient id="sfBg" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#241c16" />
          <stop offset="100%" stopColor="#0f0e0d" />
        </linearGradient>
        <linearGradient id="sfMetal" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stopColor="#e8bd79" />
          <stop offset="55%" stopColor="#de865b" />
          <stop offset="100%" stopColor="#c45c26" />
        </linearGradient>
        <linearGradient id="sfAnvil" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stopColor="#5c3a28" />
          <stop offset="50%" stopColor="#904d2b" />
          <stop offset="100%" stopColor="#5c3a28" />
        </linearGradient>
      </defs>
      <circle cx="32" cy="32" r="30" fill="url(#sfBg)" stroke="#904d2b" strokeWidth="2" />
      <circle cx="32" cy="22" r="8" fill="#e8bd79" opacity="0.9" />
      <circle cx="32" cy="22" r="12" fill="none" stroke="#de865b" strokeWidth="1.5" opacity="0.5" />
      <path d="M14 40 h36 l-3 6 H17 z" fill="url(#sfAnvil)" />
      <path d="M18 36 h28 v4 H18 z" fill="#a89888" />
      <path d="M12 36 h8 v3 H12 z" fill="#de865b" />
      <path d="M40 18 l10 4 -2 6 -10 -4 z" fill="url(#sfMetal)" />
      <rect
        x="36"
        y="20"
        width="3"
        height="14"
        rx="1"
        fill="#e3d4ad"
        transform="rotate(25 37.5 27)"
      />
      <text
        x="32"
        y="54"
        textAnchor="middle"
        fontFamily="system-ui, Segoe UI, sans-serif"
        fontSize="9"
        fontWeight="700"
        fill="#e3d4ad"
        letterSpacing="1"
      >
        SF
      </text>
    </svg>
  )
}
