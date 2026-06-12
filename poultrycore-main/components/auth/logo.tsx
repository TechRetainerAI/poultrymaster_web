// Reusable Poultry Master logo component
import Image from "next/image"

export function InventoryLogo({ dark = false }: { dark?: boolean }) {
  return (
    <div className="flex items-center gap-2 min-w-0">
      <Image
        src="/main_logo.png"
        alt="Poultry Master"
        width={40}
        height={40}
        className="rounded-lg shrink-0 object-contain w-8 h-8 sm:w-10 sm:h-10"
      />
      <h1 className={`text-base sm:text-lg font-bold whitespace-nowrap truncate max-w-[120px] sm:max-w-none max-[380px]:hidden ${dark ? "text-white" : "text-orange-600"}`}>
        Poultry Master
      </h1>
    </div>
  )
}
