import type { User as OidcUser } from "oidc-client-ts"

/**
 * Cognito issues the browser session through managed login (authorization code + PKCE). The app
 * keeps the ID token for its API calls; the backend verifies it.
 *
 * Without VITE_COGNITO_CLIENT_ID (local development without AWS) auth is disabled: any valid form
 * "signs in" and the backend treats every request as one local user.
 */

export interface AuthConfig {
  region: string
  userPoolId: string
  clientId: string
  domain: string
  googleEnabled: boolean
}

export function authConfig(): AuthConfig {
  const env = import.meta.env
  return {
    region: env.VITE_COGNITO_REGION || "us-east-1",
    userPoolId: env.VITE_COGNITO_USER_POOL_ID ?? "",
    clientId: env.VITE_COGNITO_CLIENT_ID ?? "",
    domain: env.VITE_COGNITO_DOMAIN ?? "",
    googleEnabled: env.VITE_COGNITO_GOOGLE === "true" && Boolean(env.VITE_COGNITO_DOMAIN),
  }
}

export const authEnabled = () => Boolean(authConfig().clientId)
export const hostedLoginEnabled = () =>
  Boolean(authConfig().userPoolId && authConfig().clientId && authConfig().domain)
export const googleEnabled = () =>
  authEnabled() && Boolean(authConfig().domain) && authConfig().googleEnabled

export const cognitoAuthority = () => {
  const { region, userPoolId } = authConfig()
  return `https://cognito-idp.${region}.amazonaws.com/${userPoolId || `${region}_local`}`
}

export const oidcUserStorageKey = () =>
  `oidc.user:${cognitoAuthority()}:${authConfig().clientId || "local"}`

/** Cognito error with its exception name, e.g. NotAuthorizedException. */
export class AuthError extends Error {
  readonly code: string

  constructor(code: string, message: string) {
    super(message)
    this.name = "AuthError"
    this.code = code
  }
}

const FRIENDLY_MESSAGES: Record<string, string> = {
  NotAuthorizedException: "Incorrect email or password",
  UserNotFoundException: "Incorrect email or password",
  UsernameExistsException: "An account with this email already exists",
  CodeMismatchException: "That code is not right, check the email and try again",
  ExpiredCodeException: "The code has expired, send a new one",
  LimitExceededException: "Too many attempts, try again in a few minutes",
  TooManyRequestsException: "Too many attempts, try again in a few minutes",
}

async function cognito<T>(action: string, body: Record<string, unknown>): Promise<T> {
  const { region, clientId } = authConfig()
  const response = await fetch(`https://cognito-idp.${region}.amazonaws.com/`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-amz-json-1.1",
      "X-Amz-Target": `AWSCognitoIdentityProviderService.${action}`,
    },
    body: JSON.stringify({ ClientId: clientId, ...body }),
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) {
    const code =
      String(data.__type ?? "")
        .split("#")
        .pop() || "UnknownError"
    throw new AuthError(code, FRIENDLY_MESSAGES[code] ?? data.message ?? "Sign-in failed")
  }
  return data as T
}

// --- Session (kept in localStorage so a reload stays signed in) ---

interface Session {
  idToken: string
  refreshToken?: string
  /** Epoch ms when the ID token expires. */
  expiresAt: number
}

const SESSION_KEY = "meetings.session"
const LOCAL_SESSION: Session = { idToken: "", expiresAt: Number.MAX_SAFE_INTEGER }

function readSession(): Session | null {
  try {
    const raw = localStorage.getItem(SESSION_KEY)
    return raw ? (JSON.parse(raw) as Session) : null
  } catch {
    return null
  }
}

function writeSession(session: Session | null) {
  try {
    if (session) localStorage.setItem(SESSION_KEY, JSON.stringify(session))
    else localStorage.removeItem(SESSION_KEY)
  } catch {
    // Storage unavailable (private mode): the session lasts until reload.
  }
}

interface Tokens {
  IdToken: string
  RefreshToken?: string
  ExpiresIn: number
}

function saveTokens(tokens: Tokens, previousRefresh?: string) {
  writeSession({
    idToken: tokens.IdToken,
    refreshToken: tokens.RefreshToken ?? previousRefresh,
    expiresAt: Date.now() + tokens.ExpiresIn * 1000,
  })
}

export const isSignedIn = () => readSession() !== null

export function signOut() {
  writeSession(null)
  try {
    localStorage.removeItem(oidcUserStorageKey())
  } catch {
    // Storage unavailable.
  }
}

export function cognitoLogoutUrl() {
  const { clientId, domain } = authConfig()
  const params = new URLSearchParams({
    client_id: clientId,
    logout_uri: `${window.location.origin}/`,
  })
  return `https://${domain}/logout?${params}`
}

/** Copy the library-managed OIDC session into the app's token helper. */
export function saveOidcSession(user?: OidcUser) {
  if (!user?.id_token) return
  saveTokens(
    {
      IdToken: user.id_token,
      RefreshToken: user.refresh_token,
      ExpiresIn: user.expires_in ?? 3600,
    },
    user.refresh_token,
  )
}

/** A valid ID token for the API, refreshed when about to expire; null when signed out. */
export async function getIdToken(): Promise<string | null> {
  const session = readSession()
  if (!session || !authEnabled()) return null
  if (session.expiresAt - 60_000 > Date.now()) return session.idToken
  if (!session.refreshToken) {
    signOut()
    return null
  }
  try {
    const { AuthenticationResult } = await cognito<{ AuthenticationResult: Tokens }>(
      "InitiateAuth",
      { AuthFlow: "REFRESH_TOKEN_AUTH", AuthParameters: { REFRESH_TOKEN: session.refreshToken } },
    )
    saveTokens(AuthenticationResult, session.refreshToken)
    return AuthenticationResult.IdToken
  } catch {
    signOut()
    return null
  }
}

// --- Email + password ---

export async function signIn(email: string, password: string): Promise<void> {
  if (!authEnabled()) {
    writeSession(LOCAL_SESSION)
    return
  }
  const result = await cognito<{ AuthenticationResult?: Tokens; ChallengeName?: string }>(
    "InitiateAuth",
    { AuthFlow: "USER_PASSWORD_AUTH", AuthParameters: { USERNAME: email, PASSWORD: password } },
  )
  if (!result.AuthenticationResult) {
    throw new AuthError(
      result.ChallengeName ?? "ChallengeRequired",
      "This account needs an extra step that the app does not support yet",
    )
  }
  saveTokens(result.AuthenticationResult)
}

/** Creates the account; Cognito then emails a code to confirm it. */
export async function signUp(name: string, email: string, password: string): Promise<void> {
  if (!authEnabled()) return
  await cognito("SignUp", {
    Username: email,
    Password: password,
    UserAttributes: [
      { Name: "email", Value: email },
      { Name: "name", Value: name },
    ],
  })
}

export async function confirmSignUp(email: string, code: string): Promise<void> {
  if (!authEnabled()) return
  await cognito("ConfirmSignUp", { Username: email, ConfirmationCode: code })
}

export async function resendCode(email: string): Promise<void> {
  if (!authEnabled()) return
  await cognito("ResendConfirmationCode", { Username: email })
}
