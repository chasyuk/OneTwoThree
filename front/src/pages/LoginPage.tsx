import { useEffect, useRef, useState } from "react"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { CircleCheck } from "lucide-react"
import { useAuth } from "react-oidc-context"
import { Link, Navigate, useLocation, useNavigate } from "react-router"
import { z } from "zod"

import { AuthLayout } from "@/components/auth/AuthLayout"
import { GoogleButton, OrDivider } from "@/components/auth/GoogleButton"
import { PasswordInput } from "@/components/auth/PasswordInput"
import { Button } from "@/components/ui/button"
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form"
import { Input } from "@/components/ui/input"
import { AuthError, hostedLoginEnabled, signIn } from "@/lib/auth"

const loginSchema = z.object({
  email: z.email("Enter a valid email"),
  password: z.string().min(1, "Password is required"),
})

type LoginValues = z.infer<typeof loginSchema>

/** Set by the confirm page after a new account is verified. */
interface LoginState {
  email?: string
  confirmed?: boolean
}

export function LoginPage() {
  return <LocalLoginPage />
}

export function ManagedLoginPage() {
  return hostedLoginEnabled() ? <CognitoLoginRedirect /> : <Navigate to="/" replace />
}

function CognitoLoginRedirect() {
  const auth = useAuth()
  const { activeNavigator, isAuthenticated, isLoading, signinRedirect } = auth
  const [error, setError] = useState<string | null>(null)
  const started = useRef(false)

  useEffect(() => {
    if (isLoading || isAuthenticated || activeNavigator || started.current) return
    started.current = true
    void signinRedirect().catch((reason: unknown) => {
      setError(reason instanceof Error ? reason.message : "Could not open the sign-in page")
    })
  }, [activeNavigator, isAuthenticated, isLoading, signinRedirect])

  if (isAuthenticated) return <Navigate to="/home" replace />

  return (
    <AuthLayout>
      {error ? (
        <div role="alert">
          <h1 className="text-2xl font-semibold text-foreground">Could not open sign-in</h1>
          <p className="mt-2 text-sm text-muted-foreground">{error}</p>
          <button
            type="button"
            className="mt-6 font-medium text-primary underline-offset-4 hover:underline"
            onClick={() => window.location.reload()}
          >
            Try again
          </button>
        </div>
      ) : (
        <p className="text-sm text-muted-foreground">Opening secure sign-in…</p>
      )}
    </AuthLayout>
  )
}

function LocalLoginPage() {
  const navigate = useNavigate()
  const state = (useLocation().state ?? {}) as LoginState
  const form = useForm<LoginValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: state.email ?? "", password: "" },
  })

  const onSubmit = async ({ email, password }: LoginValues) => {
    try {
      await signIn(email, password)
      navigate("/home", { replace: true })
    } catch (error) {
      if (error instanceof AuthError && error.code === "UserNotConfirmedException") {
        navigate("/confirm", { state: { email } })
        return
      }
      form.setError("root", { message: error instanceof Error ? error.message : "Sign-in failed" })
    }
  }

  return (
    <AuthLayout>
      <h1 className="text-2xl font-semibold text-foreground">Sign in</h1>
      <p className="mt-1.5 text-sm text-muted-foreground">
        Welcome back. Sign in to see your meetings.
      </p>

      {state.confirmed && (
        <p className="mt-6 flex items-center gap-2 rounded-sm bg-secondary px-3 py-2 text-sm text-secondary-foreground">
          <CircleCheck className="size-4 shrink-0" /> Account confirmed. Sign in to continue.
        </p>
      )}

      <div className="mt-8">
        <GoogleButton label="Continue with Google" />
      </div>
      <OrDivider />

      <Form {...form}>
        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4" noValidate>
          <FormField
            control={form.control}
            name="email"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Email</FormLabel>
                <FormControl>
                  <Input
                    type="email"
                    autoComplete="email"
                    placeholder="you@example.com"
                    {...field}
                  />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
          <FormField
            control={form.control}
            name="password"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Password</FormLabel>
                <FormControl>
                  <PasswordInput autoComplete="current-password" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
          {form.formState.errors.root && (
            <p role="alert" className="text-sm text-destructive">
              {form.formState.errors.root.message}
            </p>
          )}
          <Button type="submit" className="h-10 w-full" disabled={form.formState.isSubmitting}>
            {form.formState.isSubmitting ? "Signing in…" : "Sign in"}
          </Button>
        </form>
      </Form>

      <p className="mt-6 text-center text-sm text-muted-foreground">
        Don&apos;t have an account?{" "}
        <Link to="/signup" className="font-medium text-primary underline-offset-4 hover:underline">
          Sign up
        </Link>
      </p>
    </AuthLayout>
  )
}
