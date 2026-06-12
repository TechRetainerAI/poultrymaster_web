import * as React from 'react'

import { Input } from '@/components/ui/input'

type InputProps = React.ComponentProps<typeof Input>

const toText = (v: InputProps['value']) =>
  v === null || v === undefined || (typeof v === 'number' && Number.isNaN(v)) ? '' : String(v)

// Wraps <Input type="number"> with an internal text buffer so the user can type
// "0", "0.5", "0.05", or clear the field entirely. The previous version rendered
// any 0 as an empty string and the parent's `Number(e.target.value) || 0` reset
// fed back through React's controlled value — so a standalone "0" or a leading
// "0." was stripped as you typed (you literally could not enter 0). Here the
// displayed text is what the user types; we only re-sync from the numeric prop
// while the field is NOT focused, so external updates still flow in but never
// clobber in-progress input.
function NumberInput({ value, onChange, onFocus, onBlur, ...props }: Omit<InputProps, 'type'>) {
  const [text, setText] = React.useState<string>(() => toText(value))
  const focusedRef = React.useRef(false)

  React.useEffect(() => {
    if (focusedRef.current) return // don't overwrite what the user is typing
    const next = toText(value)
    // Re-sync only when the numeric meaning actually changed, so "5" doesn't get
    // rewritten to "5.0" etc. on unrelated re-renders.
    if (next === '' || Number(next) !== Number(text)) setText(next)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value])

  return (
    <Input
      type="number"
      value={text}
      onChange={(e) => {
        setText(e.target.value)
        onChange?.(e)
      }}
      onFocus={(e) => {
        focusedRef.current = true
        onFocus?.(e)
      }}
      onBlur={(e) => {
        focusedRef.current = false
        setText(toText(value))
        onBlur?.(e)
      }}
      {...props}
    />
  )
}

export { NumberInput }
