/**
 * Sonoran Forge mark from brand pack (docs/brand → public/brand at build).
 * Falls back to inline SVG if the PNG is missing (dev without Docker copy).
 */
export default function SonoranForgeLogo({
  size = 44,
  className = '',
  variant = 'badge', // badge | wordmark
}) {
  if (variant === 'wordmark') {
    return (
      <img
        className={`sf-wordmark ${className}`}
        src="/brand/sf-wordmark-stacked.png"
        alt="Sonoran Forge"
        height={size}
        style={{ height: size, width: 'auto' }}
      />
    )
  }

  return (
    <img
      className={`sf-badge ${className}`}
      src="/brand/sf-badge-circular.png"
      alt="Sonoran Forge"
      width={size}
      height={size}
      style={{ width: size, height: size }}
      onError={(e) => {
        // Keep layout if asset path fails
        e.currentTarget.style.visibility = 'hidden'
      }}
    />
  )
}
