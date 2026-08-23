/**
 * Login illustration — replaces the old /farmer-illustration.png raster clipart.
 *
 * Drawn as inline SVG so it stays crisp at any size, costs ~6KB instead of 142KB,
 * carries no stock-image licensing, and uses the app's own palette (orange-500
 * accent, slate text) instead of clipart colours that matched nothing.
 *
 * Decorative only — the surrounding section carries the real heading text, so this
 * is aria-hidden rather than given a competing alt description.
 */
export function FarmIllustration({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 480 400"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <linearGradient id="vc-hen" x1="150" y1="120" x2="330" y2="300" gradientUnits="userSpaceOnUse">
          <stop stopColor="#FDBA74" />
          <stop offset="0.55" stopColor="#F97316" />
          <stop offset="1" stopColor="#EA580C" />
        </linearGradient>
        <linearGradient id="vc-ground" x1="60" y1="300" x2="420" y2="340" gradientUnits="userSpaceOnUse">
          <stop stopColor="#E2E8F0" />
          <stop offset="1" stopColor="#F1F5F9" />
        </linearGradient>
        <linearGradient id="vc-bars" x1="0" y1="0" x2="0" y2="1">
          <stop stopColor="#34D399" />
          <stop offset="1" stopColor="#10B981" />
        </linearGradient>
        <radialGradient id="vc-glow" cx="0.5" cy="0.5" r="0.5">
          <stop stopColor="#FFF7ED" />
          <stop offset="1" stopColor="#FFF7ED" stopOpacity="0" />
        </radialGradient>
      </defs>

      {/* warm halo behind the subject */}
      <circle cx="240" cy="196" r="168" fill="url(#vc-glow)" />

      {/* dot grid — suggests data without shouting about it */}
      <g fill="#CBD5E1" opacity="0.55">
        {Array.from({ length: 5 }).map((_, row) =>
          Array.from({ length: 9 }).map((_, col) => (
            <circle key={`${row}-${col}`} cx={72 + col * 42} cy={54 + row * 40} r="2.5" />
          )),
        )}
      </g>

      {/* ground line */}
      <ellipse cx="240" cy="322" rx="176" ry="18" fill="url(#vc-ground)" />

      {/* ---- hen ---- */}
      <g>
        {/* tail */}
        <path
          d="M168 236c-26-6-44-26-46-52 18 10 34 12 48 6-10-16-10-34 2-50 8 20 20 32 36 38l-40 58Z"
          fill="#FB923C"
        />
        {/* body */}
        <path
          d="M318 232c0 44-38 74-84 74s-84-30-84-74 34-88 84-88 84 44 84 88Z"
          fill="url(#vc-hen)"
        />
        {/* wing */}
        <path
          d="M232 210c30 0 54 20 60 48-16 14-38 22-62 22-16 0-30-4-42-10 4-34 20-60 44-60Z"
          fill="#FFF7ED"
          opacity="0.5"
        />
        {/* comb */}
        <path
          d="M254 150c4-14 16-20 26-14-2-12 8-22 20-18 10 4 14 14 10 26-14 8-38 10-56 6Z"
          fill="#EF4444"
        />
        {/* head + beak */}
        <circle cx="288" cy="176" r="30" fill="#FB923C" />
        <path d="M316 172l24 8-24 10v-18Z" fill="#FBBF24" />
        <path d="M300 194c-4 10-2 18 4 24-10-2-16-10-16-22l12-2Z" fill="#EF4444" />
        <circle cx="296" cy="170" r="5" fill="#0F172A" />
        <circle cx="298" cy="168" r="1.8" fill="#FFFFFF" />
        {/* legs */}
        <g stroke="#F59E0B" strokeWidth="5" strokeLinecap="round">
          <path d="M214 304v18M250 304v18" />
          <path d="M204 324h20M240 324h20" />
        </g>
      </g>

      {/* ---- floating data card: production trend ---- */}
      <g transform="translate(46 96)">
        <rect width="132" height="96" rx="14" fill="#FFFFFF" stroke="#E2E8F0" strokeWidth="2" />
        <rect x="16" y="18" width="52" height="7" rx="3.5" fill="#CBD5E1" />
        <g fill="url(#vc-bars)">
          <rect x="16" y="60" width="16" height="20" rx="4" />
          <rect x="40" y="50" width="16" height="30" rx="4" />
          <rect x="64" y="40" width="16" height="40" rx="4" />
          <rect x="88" y="30" width="16" height="50" rx="4" />
        </g>
        <path d="M20 56l24-8 24-10 26-12" stroke="#F97316" strokeWidth="3" strokeLinecap="round" fill="none" />
        <circle cx="94" cy="26" r="4.5" fill="#F97316" />
      </g>

      {/* ---- floating data card: egg count ---- */}
      <g transform="translate(318 236)">
        <rect width="126" height="76" rx="14" fill="#FFFFFF" stroke="#E2E8F0" strokeWidth="2" />
        <ellipse cx="34" cy="38" rx="15" ry="19" fill="#FEF3C7" stroke="#FBBF24" strokeWidth="2" />
        <rect x="60" y="24" width="48" height="9" rx="4.5" fill="#0F172A" opacity="0.75" />
        <rect x="60" y="43" width="32" height="7" rx="3.5" fill="#CBD5E1" />
      </g>
    </svg>
  )
}
