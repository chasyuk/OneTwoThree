import { useQueryClient } from "@tanstack/react-query"
import { CalendarDays, LogOut, Plus } from "lucide-react"
import { Link, useNavigate } from "react-router"

import { useMe } from "@/hooks/useMe"
import { cognitoLogoutUrl, hostedLoginEnabled, signOut } from "@/lib/auth"

interface SiteHeaderProps {
  onNewMeeting: () => void
}

export function SiteHeader({ onNewMeeting }: SiteHeaderProps) {
  const { data: me } = useMe()
  const queryClient = useQueryClient()
  const navigate = useNavigate()

  const handleSignOut = () => {
    signOut()
    queryClient.clear()
    if (hostedLoginEnabled()) {
      window.location.assign(cognitoLogoutUrl())
      return
    }
    navigate("/login/", { replace: true })
  }

  return (
    <header className="sticky top-0 z-40 bg-brand text-white shadow-[0_0.8px_8px_rgba(0,0,0,0.2)]">
      <div className="mx-auto flex h-14 max-w-7xl items-center gap-8 px-4 sm:px-6">
        <Link to="/home" className="flex items-center gap-2.5">
          <span className="flex size-9 items-center justify-center rounded-sm border-2 border-white/90">
            <CalendarDays className="size-5" />
          </span>
          <span className="font-serif text-sm leading-tight">
            Meetings
            <br />
            <span className="text-white/80">Scheduler</span>
          </span>
        </Link>

        <nav className="hidden h-full items-stretch gap-6 text-sm sm:flex">
          <Link
            to="/home"
            className="flex items-center border-b-[3px] border-white pt-[3px] font-medium"
          >
            Meetings
          </Link>
        </nav>

        <div className="ml-auto flex items-center gap-4">
          <button
            type="button"
            onClick={onNewMeeting}
            className="flex items-center gap-1.5 text-sm font-semibold hover:text-white/80"
          >
            <Plus className="size-4" /> New meeting
          </button>
          <span className="h-8 w-px bg-white/30" />
          {me && (
            <span
              className="max-w-36 truncate text-xs text-white/90 sm:max-w-48 sm:text-sm"
              title={me.email}
            >
              {me.name ?? me.email}
            </span>
          )}
          <button
            type="button"
            onClick={handleSignOut}
            className="flex items-center gap-1.5 text-sm text-white/90 hover:text-white"
            aria-label="Sign out"
          >
            <LogOut className="size-4" />
            <span className="hidden md:inline">Sign out</span>
          </button>
        </div>
      </div>
    </header>
  )
}
