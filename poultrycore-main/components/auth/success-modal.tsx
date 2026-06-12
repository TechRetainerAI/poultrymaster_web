"use client"

// Success modal component for various success states

import { Button } from "@/components/ui/button"

interface SuccessModalProps {
  title: string
  message: string
  onClose: () => void
  buttonText?: string
}

export function SuccessModal({ title, message, onClose, buttonText = "Back to Login" }: SuccessModalProps) {
  return (
    <div className="fixed inset-0 bg-black/20 backdrop-blur-sm flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-2xl shadow-xl p-8 max-w-md w-full text-center">
        {/* Party popper icon */}
        <div className="mb-6 flex justify-center">
          <div className="text-6xl">🎉</div>
        </div>

        <h2 className="text-2xl font-bold text-slate-900 mb-3">{title}</h2>
        <p className="text-slate-500 mb-8">{message}</p>

        <Button
          onClick={onClose}
          className="w-full h-12 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg"
        >
          {buttonText}
        </Button>
      </div>
    </div>
  )
}
