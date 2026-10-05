import { useMemo } from "react"
import { AuthProvider, type AuthProviderProps } from "react-oidc-context"
import { WebStorageStateStore } from "oidc-client-ts"
import { Navigate, Route, Routes } from "react-router"

import { RedirectIfSignedIn, RequireAuth } from "@/components/auth/RequireAuth"
import { AuthCallbackPage } from "@/pages/AuthCallbackPage"
import { ConfirmPage } from "@/pages/ConfirmPage"
import { HomePage } from "@/pages/HomePage"
import { LoginPage, ManagedLoginPage } from "@/pages/LoginPage"
import { SignUpPage } from "@/pages/SignUpPage"
import { authConfig, cognitoAuthority, saveOidcSession } from "@/lib/auth"

export default function App() {
  const oidcConfig = useMemo<AuthProviderProps>(() => {
    const { clientId } = authConfig()
    return {
      authority: cognitoAuthority(),
      client_id: clientId || "local",
      redirect_uri: `${window.location.origin}/auth/callback`,
      response_type: "code",
      scope: "openid email profile",
      userStore: new WebStorageStateStore({ store: window.localStorage }),
      automaticSilentRenew: false,
      onSigninCallback: (user) => {
        saveOidcSession(user)
        window.history.replaceState({}, document.title, window.location.pathname)
      },
    }
  }, [])

  return (
    <AuthProvider {...oidcConfig}>
      <Routes>
        <Route
          path="/"
          element={
            <RedirectIfSignedIn>
              <LoginPage />
            </RedirectIfSignedIn>
          }
        />
        <Route path="/login" element={<ManagedLoginPage />} />
        <Route
          path="/signup"
          element={
            <RedirectIfSignedIn>
              <SignUpPage />
            </RedirectIfSignedIn>
          }
        />
        <Route path="/confirm" element={<ConfirmPage />} />
        <Route path="/auth/callback" element={<AuthCallbackPage />} />
        <Route
          path="/home"
          element={
            <RequireAuth>
              <HomePage />
            </RequireAuth>
          }
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AuthProvider>
  )
}
