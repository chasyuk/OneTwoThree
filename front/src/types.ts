export interface Participant {
  id: string
  name: string
  email: string
}

export interface User {
  id: string
  email: string
  name: string | null
}

export interface Meeting {
  id: string
  title: string
  description: string | null
  call_link: string | null
  place: string | null
  starts_at: string
  ends_at: string
  owner_id: string | null
  participants: Participant[]
  created_at: string
}

export interface MeetingCreate {
  title: string
  description: string | null
  call_link: string | null
  place: string | null
  starts_at: string
  ends_at: string
  participant_ids: string[]
}

export interface ParticipantCreate {
  name: string
  email: string
}

/** One entry of FastAPI's 422 `detail` list. */
export interface ValidationIssue {
  loc: (string | number)[]
  msg: string
  type: string
}

export interface AgendaItem {
  topic: string
  owner: string | null
  minutes: number | null
}

export interface ActionItem {
  task: string
  owner: string | null
  due: string | null
}

export interface ParsedAgenda {
  title: string | null
  starts_at: string | null
  duration_minutes: number | null
  items: AgendaItem[]
  action_items: ActionItem[]
  language: string
}

export interface AgendaSuggestion {
  agenda: ParsedAgenda
  model: string
  prompt_version: string
}

export interface AgendaRead {
  id: string
  meeting_id: string
  items: AgendaItem[]
  action_items: ActionItem[]
  ai_suggestion: AgendaSuggestion | null
  created_at: string
  updated_at: string
}

export interface AgendaCreate {
  items: AgendaItem[]
  action_items: ActionItem[]
  ai_suggestion?: AgendaSuggestion | null
}
