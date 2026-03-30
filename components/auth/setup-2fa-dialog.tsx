"use client"

import { useState } from "react"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Shield, Lock, Mail, CheckCircle } from "lucide-react"

interface Setup2FADialogProps {
  open: boolean
  onClose: () => void
  onEnable: () => void
  onSkip: () => void
}

export function Setup2FADialog({ open, onClose, onEnable, onSkip }: Setup2FADialogProps) {
  return (
    <AlertDialog open={open} onOpenChange={onClose}>
      <AlertDialogContent className="sm:max-w-[425px]">
        <AlertDialogHeader>
          <div className="flex items-center gap-3 mb-2">
            <div className="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center">
              <Shield className="w-6 h-6 text-blue-600" />
            </div>
            <AlertDialogTitle className="text-2xl">Enable Two-Factor Authentication?</AlertDialogTitle>
          </div>
          <AlertDialogDescription className="text-base space-y-3 pt-2">
            <span className="block text-slate-600">
              Add an extra layer of security to your account by enabling two-factor authentication (2FA).
            </span>
            <span className="block space-y-2 mt-4">
              <span className="flex items-start gap-2">
                <Lock className="w-5 h-5 text-green-600 mt-0.5 shrink-0" />
                <span className="text-sm text-slate-700">
                  <strong>Better Security:</strong> Protect your account even if your password is compromised
                </span>
              </span>
              <span className="flex items-start gap-2">
                <Mail className="w-5 h-5 text-blue-600 mt-0.5 shrink-0" />
                <span className="text-sm text-slate-700">
                  <strong>Easy Setup:</strong> Just verify codes sent to your email during login
                </span>
              </span>
              <span className="flex items-start gap-2">
                <CheckCircle className="w-5 h-5 text-orange-600 mt-0.5 shrink-0" />
                <span className="text-sm text-slate-700">
                  <strong>Quick Login:</strong> Only takes a few extra seconds to verify
                </span>
              </span>
            </span>
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter className="sm:justify-start gap-2 mt-6">
          <AlertDialogAction
            onClick={onEnable}
            className="bg-green-600 hover:bg-green-700 text-white"
          >
            Enable 2FA
          </AlertDialogAction>
          <AlertDialogCancel
            onClick={onSkip}
            variant="outline"
          >
            Maybe Later
          </AlertDialogCancel>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}
