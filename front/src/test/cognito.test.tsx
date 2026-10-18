import { screen, waitFor } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it, vi } from "vitest"

import App from "@/App"
import { api } from "@/lib/api"
import { getIdToken, signIn } from "@/lib/auth"
import { mockFetch, renderWithQuery, signInForTest } from "@/test/utils"

const COGNITO = "https://cognito-idp.us-east-1.amazonaws.com/"
const tokens = { IdToken: "id-token", RefreshToken: "refresh-token", ExpiresIn: 3600 }

/** Cognito request body and action of a fetch call. */
function cognitoCall(call: unknown[]) {
  const init = call[1] as RequestInit
  const headers = init.headers as Record<string, string>
  return { action: headers["X-Amz-Target"], body: JSON.parse(String(init.body)) }
}

describe("with Cognito configured", () => {
  beforeEach(() => {
    vi.stubEnv("VITE_COGNITO_REGION", "us-east-1")
    vi.stubEnv("VITE_COGNITO_CLIENT_ID", "client-123")
    vi.stubEnv("VITE_COGNITO_DOMAIN", "meetings.auth.us-east-1.amazoncognito.com")
  })

  it("signs in with Cognito and sends the ID token to the API", async () => {
    const fetchMock = mockFetch((url) =>
      url === COGNITO ? { body: { AuthenticationResult: tokens } } : { body: [] },
    )
    await signIn("anna@example.com", "secret123")

    const { action, body } = cognitoCall(fetchMock.mock.calls[0])
    expect(action).toBe("AWSCognitoIdentityProviderService.InitiateAuth")
    expect(body).toEqual({
      ClientId: "client-123",
      AuthFlow: "USER_PASSWORD_AUTH",
      AuthParameters: { USERNAME: "anna@example.com", PASSWORD: "secret123" },
    })

    await api.listMeetings()
    const apiCall = fetchMock.mock.calls.find(([url]) => url === "/api/meetings")
    expect((apiCall?.[1]?.headers as Record<string, string>).Authorization).toBe("Bearer id-token")
  })

  it("refreshes an expiring token", async () => {
    signInForTest({ idToken: "old", refreshToken: "refresh-token", expiresAt: Date.now() + 1000 })
    const fetchMock = mockFetch(() => ({
      body: { AuthenticationResult: { IdToken: "new", ExpiresIn: 3600 } },
    }))

    expect(await getIdToken()).toBe("new")
    expect(cognitoCall(fetchMock.mock.calls[0]).body.AuthFlow).toBe("REFRESH_TOKEN_AUTH")
    expect(JSON.parse(localStorage.getItem("meetings.session")!).refreshToken).toBe("refresh-token")
  })

  it("shows Cognito's error on a wrong password", async () => {
    mockFetch(() => ({
      status: 400,
      body: { __type: "NotAuthorizedException", message: "Incorrect username or password." },
    }))
    renderWithQuery(<App />, "/")
    await userEvent.type(screen.getByLabelText("Email"), "anna@example.com")
    await userEvent.type(screen.getByLabelText("Password"), "wrong")
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }))
    expect(await screen.findByRole("alert")).toHaveTextContent("Incorrect email or password")
  })

  it("signs up, confirms with the emailed code, then asks to sign in", async () => {
    const fetchMock = mockFetch(() => ({ body: {} }))
    renderWithQuery(<App />, "/signup")
    await userEvent.type(screen.getByLabelText("Name"), "Anna")
    await userEvent.type(screen.getByLabelText("Email"), "anna@example.com")
    await userEvent.type(screen.getByLabelText("Password"), "password1")
    await userEvent.type(screen.getByLabelText("Confirm password"), "password1")
    await userEvent.click(screen.getByRole("button", { name: "Create account" }))

    expect(await screen.findByRole("heading", { name: "Check your email" })).toBeInTheDocument()
    expect(cognitoCall(fetchMock.mock.calls[0]).body).toMatchObject({
      Username: "anna@example.com",
      UserAttributes: [
        { Name: "email", Value: "anna@example.com" },
        { Name: "name", Value: "Anna" },
      ],
    })

    await userEvent.type(screen.getByLabelText("Confirmation code"), "123456")
    await userEvent.click(screen.getByRole("button", { name: "Confirm account" }))

    expect(await screen.findByText(/Account confirmed/)).toBeInTheDocument()
    expect(screen.getByLabelText("Email")).toHaveValue("anna@example.com")
    const confirm = cognitoCall(fetchMock.mock.calls[1])
    expect(confirm.action).toBe("AWSCognitoIdentityProviderService.ConfirmSignUp")
    expect(confirm.body.ConfirmationCode).toBe("123456")
  })

  it("sends an unconfirmed account to the code page", async () => {
    mockFetch(() => ({ status: 400, body: { __type: "UserNotConfirmedException", message: "" } }))
    renderWithQuery(<App />, "/")
    await userEvent.type(screen.getByLabelText("Email"), "anna@example.com")
    await userEvent.type(screen.getByLabelText("Password"), "password1")
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }))
    expect(await screen.findByRole("heading", { name: "Check your email" })).toBeInTheDocument()
  })

  it("enables Google only when the pool has it", () => {
    vi.stubEnv("VITE_COGNITO_GOOGLE", "true")
    mockFetch(() => ({ body: {} }))
    renderWithQuery(<App />, "/")
    expect(screen.getByRole("button", { name: "Continue with Google" })).toBeEnabled()
    expect(screen.queryByText("Google sign-in is coming soon.")).not.toBeInTheDocument()
  })

  it("rejects an OAuth callback it did not start", async () => {
    mockFetch(() => ({ body: {} }))
    window.history.pushState({}, "", "/auth/callback?code=abc&state=forged")
    renderWithQuery(<App />, "/auth/callback?code=abc&state=forged")
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Sign-in failed"))
  })
})
