import * as React from 'react'

import { Input } from '@/components/ui/input'

type InputProps = React.ComponentProps<typeof Input>

// Wraps <Input type="number"> so an underlying value of 0 / null / undefined
// renders as an empty field instead of a stuck "0" the user can't delete.
// Drop-in: forwards onChange and every other Input prop; type is forced to
// "number". Empty input still calls the parent's onChange with e.target.value
// === "", so the existing `parseInt(value) || 0` patterns keep working.
function NumberInput({ value, ...props }: Omit<InputProps, 'type'>) {
  const isBlank =
    value === 0 ||
    value === '0' ||
    value === null ||
    value === undefined ||
    (typeof value === 'number' && Number.isNaN(value))

  return <Input type="number" value={isBlank ? '' : value} {...props} />
}

export { NumberInput }
