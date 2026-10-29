import { cognitoLogoutUrl, getIdToken, hostedLoginEnabled, signOut } from "@/lib/auth"
import type {
  AgendaCreate,
  AgendaRead,
  Meeting,
  MeetingCreate,
  ParsedAgenda,
  Participant,
  ParticipantCreate,
  User,
  ValidationIssue,
} from "@/types"

export class ApiError extends Error {
  readonly status: number
  readonly detail: unknown

  constructor(message: string, status: number, detail: unknown) {
    super(message)
    this.name = "ApiError"
    this.status = status
    this.detail = detail
  }

  get issues(): ValidationIssue[] {
    return Array.isArray(this.detail) ? (this.detail as ValidationIssue[]) : []
  }
}

function messageFrom(detail: unknown, status: number): string {
  if (typeof detail === "string") return detail
  if (Array.isArray(detail)) return detail.map((issue: ValidationIssue) => issue.msg).join("; ")
  return `Request failed (${status})`
}

// Backend origin, set at build time (the Lambda function URL on AWS). Empty = same origin,
// where nginx (Docker Compose) or the Vite dev server proxies /api to the backend.
const API_URL = (import.meta.env.VITE_API_URL ?? "").replace(/\/+$/, "")

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const token = await getIdToken()
  const response = await fetch(`${API_URL}/api${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...init?.headers,
    },
  })

  // Session gone or rejected: back to the sign-in page.
  if (response.status === 401) {
    signOut()
    window.location.assign(hostedLoginEnabled() ? cognitoLogoutUrl() : "/")
  }

  if (!response.ok) {
    let detail: unknown = response.statusText
    try {
      detail = (await response.json()).detail
    } catch {
      // Non-JSON error body: keep the status text.
    }
    throw new ApiError(messageFrom(detail, response.status), response.status, detail)
  }

  if (response.status === 204) return undefined as T
  return response.json() as Promise<T>
}

export const api = {
  getMe: () => request<User>("/me"),

  listMeetings: () => request<Meeting[]>("/meetings"),
  createMeeting: (data: MeetingCreate) =>
    request<Meeting>("/meetings", { method: "POST", body: JSON.stringify(data) }),
  updateMeeting: ({ id, data }: { id: string; data: MeetingCreate }) =>
    request<Meeting>(`/meetings/${id}`, { method: "PUT", body: JSON.stringify(data) }),
  deleteMeeting: (id: string) => request<void>(`/meetings/${id}`, { method: "DELETE" }),

  listParticipants: (q = "") =>
    request<Participant[]>(`/participants${q ? `?q=${encodeURIComponent(q)}` : ""}`),
  createParticipant: (data: ParticipantCreate) =>
    request<Participant>("/participants", { method: "POST", body: JSON.stringify(data) }),

  getAgenda: (meetingId: string) => request<AgendaRead>(`/meetings/${meetingId}/agenda`),
  saveAgenda: (meetingId: string, data: AgendaCreate) =>
    request<AgendaRead>(`/meetings/${meetingId}/agenda`, {
      method: "POST",
      body: JSON.stringify(data),
    }),
}

const PARSER_URL = (
  import.meta.env.VITE_PARSER_URL ||
  "https://sj6stkwx3zputn5ld24e42ik440suwfi.lambda-url.us-east-1.on.aws"
).replace(/\/+$/, "")

export async function parseAgendaText(
  text: string,
  today: string,
  tz: string,
  signal?: AbortSignal,
): Promise<{ agenda: ParsedAgenda; model: string; prompt_version: string }> {
  const token = await getIdToken()
  if (!token && hostedLoginEnabled()) {
    signOut()
    window.location.assign(cognitoLogoutUrl())
    throw new Error("Your session has expired. Redirecting to sign in...")
  }

  const targetUrl = PARSER_URL ? `${PARSER_URL}/` : `${API_URL}/api/ai/parse-agenda`
  const response = await fetch(targetUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ text, today, tz }),
    signal,
  })

  if (response.status === 401) {
    signOut()
    window.location.assign(hostedLoginEnabled() ? cognitoLogoutUrl() : "/")
    throw new Error("Your session has expired. Redirecting to sign in...")
  }

  if (!response.ok) {
    let errMessage = `Error ${response.status}`
    try {
      const data = await response.json()
      if (data.error) errMessage = data.error
      else if (data.detail) errMessage = data.detail
    } catch {
      // ignore non-json
    }
    if (response.status === 413) {
      throw new Error("Text exceeds maximum length of 10,000 characters")
    }
    if (response.status === 422) {
      throw new Error(`The model could not find an agenda: ${errMessage}`)
    }
    if (response.status === 429) {
      throw new Error("The AI service is busy. Please wait a moment or enter the agenda manually.")
    }
    throw new Error(errMessage)
  }

  return response.json()
}
