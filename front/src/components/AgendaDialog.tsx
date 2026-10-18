import { useEffect, useRef, useState } from "react"
import { AlertCircle, Loader2, Plus, Sparkles, Trash2, X } from "lucide-react"
import { toast } from "sonner"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { useAgenda, useSaveAgenda } from "@/hooks/useAgenda"
import { parseAgendaText } from "@/lib/api"
import type {
  ActionItem,
  AgendaCreate,
  AgendaItem,
  AgendaRead,
  AgendaSuggestion,
  Meeting,
} from "@/types"

interface FieldState<T> {
  value: T
  isSuggested: boolean
}

interface UiAgendaItem {
  id: string
  topic: FieldState<string>
  owner: FieldState<string>
  minutes: FieldState<string>
}

interface UiActionItem {
  id: string
  task: FieldState<string>
  owner: FieldState<string>
  due: FieldState<string>
}

interface AgendaDialogProps {
  meeting: Meeting | null
  open: boolean
  onOpenChange: (open: boolean) => void
}

interface AgendaFormProps {
  meeting: Meeting
  existingAgenda: AgendaRead | null
  onClose: () => void
}

function AgendaForm({ meeting, existingAgenda, onClose }: AgendaFormProps) {
  const meetingId = meeting.id
  const saveAgendaMutation = useSaveAgenda()

  const [pastedText, setPastedText] = useState("")
  const [isParsing, setIsParsing] = useState(false)
  const [parseError, setParseError] = useState<string | null>(null)
  const abortControllerRef = useRef<AbortController | null>(null)

  const [items, setItems] = useState<UiAgendaItem[]>(() =>
    (existingAgenda?.items ?? []).map((it, idx) => ({
      id: `item-${idx}-${Date.now()}`,
      topic: { value: it.topic ?? "", isSuggested: false },
      owner: { value: it.owner ?? "", isSuggested: false },
      minutes: { value: it.minutes != null ? String(it.minutes) : "", isSuggested: false },
    })),
  )

  const [actionItems, setActionItems] = useState<UiActionItem[]>(() =>
    (existingAgenda?.action_items ?? []).map((it, idx) => ({
      id: `action-${idx}-${Date.now()}`,
      task: { value: it.task ?? "", isSuggested: false },
      owner: { value: it.owner ?? "", isSuggested: false },
      due: { value: it.due ?? "", isSuggested: false },
    })),
  )

  const [suggestion, setSuggestion] = useState<AgendaSuggestion | null>(
    () => existingAgenda?.ai_suggestion ?? null,
  )

  // Cancel any ongoing parsing on unmount
  useEffect(() => {
    return () => {
      if (abortControllerRef.current) {
        abortControllerRef.current.abort()
        abortControllerRef.current = null
      }
    }
  }, [])

  const handleParse = async () => {
    if (!pastedText.trim()) return
    setParseError(null)
    setIsParsing(true)

    const controller = new AbortController()
    abortControllerRef.current = controller

    try {
      const todayIso = new Date().toISOString().split("T")[0]
      const userTz = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"
      const result = await parseAgendaText(pastedText, todayIso, userTz, controller.signal)

      // Store raw suggestion for evaluation
      setSuggestion({
        agenda: result.agenda,
        model: result.model,
        prompt_version: result.prompt_version,
      })

      // Pre-fill agenda items with suggested badges
      setItems(
        (result.agenda.items ?? []).map((it, idx) => ({
          id: `item-${idx}-${Date.now()}`,
          topic: { value: it.topic ?? "", isSuggested: Boolean(it.topic) },
          owner: { value: it.owner ?? "", isSuggested: Boolean(it.owner) },
          minutes: {
            value: it.minutes != null ? String(it.minutes) : "",
            isSuggested: it.minutes != null,
          },
        })),
      )

      // Pre-fill action items with suggested badges
      setActionItems(
        (result.agenda.action_items ?? []).map((it, idx) => ({
          id: `action-${idx}-${Date.now()}`,
          task: { value: it.task ?? "", isSuggested: Boolean(it.task) },
          owner: { value: it.owner ?? "", isSuggested: Boolean(it.owner) },
          due: { value: it.due ?? "", isSuggested: Boolean(it.due) },
        })),
      )

      toast.success("Agenda parsed! Review the suggested fields below.")
    } catch (err: unknown) {
      if (err instanceof Error && err.name === "AbortError") {
        toast.info("Parsing cancelled")
      } else {
        const msg = err instanceof Error ? err.message : "Failed to parse agenda"
        setParseError(msg)
        toast.error(msg)
      }
    } finally {
      setIsParsing(false)
      abortControllerRef.current = null
    }
  }

  const handleCancelParse = () => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort()
      abortControllerRef.current = null
      setIsParsing(false)
    }
  }

  // Updating a field clears its suggested status as per requirements
  const updateItemField = (id: string, field: "topic" | "owner" | "minutes", val: string) => {
    setItems((prev) =>
      prev.map((it) =>
        it.id === id ? { ...it, [field]: { value: val, isSuggested: false } } : it,
      ),
    )
  }

  const addItem = () => {
    setItems((prev) => [
      ...prev,
      {
        id: `item-${Date.now()}-${Math.random()}`,
        topic: { value: "", isSuggested: false },
        owner: { value: "", isSuggested: false },
        minutes: { value: "", isSuggested: false },
      },
    ])
  }

  const removeItem = (id: string) => {
    setItems((prev) => prev.filter((it) => it.id !== id))
  }

  const updateActionField = (id: string, field: "task" | "owner" | "due", val: string) => {
    setActionItems((prev) =>
      prev.map((it) =>
        it.id === id ? { ...it, [field]: { value: val, isSuggested: false } } : it,
      ),
    )
  }

  const addActionItem = () => {
    setActionItems((prev) => [
      ...prev,
      {
        id: `action-${Date.now()}-${Math.random()}`,
        task: { value: "", isSuggested: false },
        owner: { value: "", isSuggested: false },
        due: { value: "", isSuggested: false },
      },
    ])
  }

  const removeActionItem = (id: string) => {
    setActionItems((prev) => prev.filter((it) => it.id !== id))
  }

  const handleSave = async () => {
    const agendaItems: AgendaItem[] = items
      .filter((it) => it.topic.value.trim().length > 0)
      .map((it) => ({
        topic: it.topic.value.trim(),
        owner: it.owner.value.trim() || null,
        minutes: it.minutes.value.trim() ? parseInt(it.minutes.value.trim(), 10) : null,
      }))

    const actionItemsPayload: ActionItem[] = actionItems
      .filter((it) => it.task.value.trim().length > 0)
      .map((it) => ({
        task: it.task.value.trim(),
        owner: it.owner.value.trim() || null,
        due: it.due.value.trim() || null,
      }))

    const payload: AgendaCreate = {
      items: agendaItems,
      action_items: actionItemsPayload,
      ai_suggestion: suggestion,
    }

    try {
      await saveAgendaMutation.mutateAsync({ meetingId, data: payload })
      toast.success("Agenda saved successfully")
      onClose()
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to save agenda")
    }
  }

  return (
    <div className="space-y-6 pt-2">
      {/* AI Parse section */}
      <div className="space-y-3 rounded-lg border bg-muted/30 p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-1.5 text-sm font-medium">
            <Sparkles className="size-4 text-brand" />
            <span>Paste an agenda</span>
          </div>
          {isParsing && (
            <Button
              variant="ghost"
              size="sm"
              onClick={handleCancelParse}
              className="h-7 text-xs text-muted-foreground hover:text-foreground"
            >
              <X className="mr-1 size-3" /> Stop
            </Button>
          )}
        </div>

        <Textarea
          placeholder="e.g. Пн 10:00, синк по прайсингу, 45 хв. 1) нові тарифи Pro — Олена, 15 хв 2) фідбек від клієнтів — Taras..."
          value={pastedText}
          onChange={(e) => setPastedText(e.target.value)}
          rows={3}
          disabled={isParsing}
          className="resize-none bg-background text-sm"
        />

        {parseError && (
          <div className="flex items-start gap-2 rounded bg-destructive/10 p-2 text-xs text-destructive">
            <AlertCircle className="mt-0.5 size-4 shrink-0" />
            <span>{parseError}</span>
          </div>
        )}

        <div className="flex items-center justify-between pt-1">
          <span className="text-xs text-muted-foreground">
            Claude will parse topics, owners, durations, and action items.
          </span>
          <Button
            size="sm"
            onClick={handleParse}
            disabled={isParsing || !pastedText.trim()}
            className="text-brand-foreground h-8 bg-brand hover:bg-brand/90"
          >
            {isParsing ? (
              <>
                <Loader2 className="mr-1.5 size-3.5 animate-spin" />
                Parsing...
              </>
            ) : (
              <>
                <Sparkles className="mr-1.5 size-3.5" />
                Parse text
              </>
            )}
          </Button>
        </div>
      </div>

      {/* Structured Agenda Items section */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-semibold text-foreground">Agenda Topics</h3>
          <Button variant="outline" size="sm" onClick={addItem} className="h-7 text-xs">
            <Plus className="mr-1 size-3" /> Add item
          </Button>
        </div>

        {items.length === 0 ? (
          <p className="rounded-md border border-dashed py-2 text-center text-xs text-muted-foreground">
            No agenda items yet. Paste text above or click Add item.
          </p>
        ) : (
          <div className="space-y-2">
            {items.map((it) => (
              <div
                key={it.id}
                className="flex flex-col items-start gap-2 rounded-md border bg-card p-2.5 text-card-foreground sm:flex-row sm:items-center"
              >
                <div className="w-full flex-1 sm:w-auto">
                  <div className="mb-1 flex items-center gap-1.5">
                    <Label className="text-xs font-medium text-muted-foreground">Topic</Label>
                    {it.topic.isSuggested && (
                      <Badge
                        variant="outline"
                        className="h-4 border-amber-300 bg-amber-50 px-1 py-0 text-[10px] text-amber-700"
                      >
                        suggested
                      </Badge>
                    )}
                  </div>
                  <Input
                    placeholder="Topic description"
                    value={it.topic.value}
                    onChange={(e) => updateItemField(it.id, "topic", e.target.value)}
                    className="h-8 text-xs"
                  />
                </div>

                <div className="w-full sm:w-36">
                  <div className="mb-1 flex items-center gap-1.5">
                    <Label className="text-xs font-medium text-muted-foreground">Owner</Label>
                    {it.owner.isSuggested && (
                      <Badge
                        variant="outline"
                        className="h-4 border-amber-300 bg-amber-50 px-1 py-0 text-[10px] text-amber-700"
                      >
                        suggested
                      </Badge>
                    )}
                  </div>
                  <Input
                    placeholder="e.g. Taras"
                    value={it.owner.value}
                    onChange={(e) => updateItemField(it.id, "owner", e.target.value)}
                    className="h-8 text-xs"
                  />
                </div>

                <div className="w-full sm:w-24">
                  <div className="mb-1 flex items-center gap-1.5">
                    <Label className="text-xs font-medium text-muted-foreground">Mins</Label>
                    {it.minutes.isSuggested && (
                      <Badge
                        variant="outline"
                        className="h-4 border-amber-300 bg-amber-50 px-1 py-0 text-[10px] text-amber-700"
                      >
                        suggested
                      </Badge>
                    )}
                  </div>
                  <Input
                    type="number"
                    min="1"
                    placeholder="15"
                    value={it.minutes.value}
                    onChange={(e) => updateItemField(it.id, "minutes", e.target.value)}
                    className="h-8 text-xs"
                  />
                </div>

                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => removeItem(it.id)}
                  className="size-8 shrink-0 self-end text-muted-foreground hover:text-destructive sm:self-center"
                  aria-label="Remove item"
                >
                  <Trash2 className="size-3.5" />
                </Button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Action Items section */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-semibold text-foreground">Action Items</h3>
          <Button variant="outline" size="sm" onClick={addActionItem} className="h-7 text-xs">
            <Plus className="mr-1 size-3" /> Add action
          </Button>
        </div>

        {actionItems.length === 0 ? (
          <p className="rounded-md border border-dashed py-2 text-center text-xs text-muted-foreground">
            No action items assigned.
          </p>
        ) : (
          <div className="space-y-2">
            {actionItems.map((act) => (
              <div
                key={act.id}
                className="flex flex-col items-start gap-2 rounded-md border bg-card p-2.5 text-card-foreground sm:flex-row sm:items-center"
              >
                <div className="w-full flex-1 sm:w-auto">
                  <div className="mb-1 flex items-center gap-1.5">
                    <Label className="text-xs font-medium text-muted-foreground">Action</Label>
                    {act.task.isSuggested && (
                      <Badge
                        variant="outline"
                        className="h-4 border-amber-300 bg-amber-50 px-1 py-0 text-[10px] text-amber-700"
                      >
                        suggested
                      </Badge>
                    )}
                  </div>
                  <Input
                    placeholder="What needs to be done"
                    value={act.task.value}
                    onChange={(e) => updateActionField(act.id, "task", e.target.value)}
                    className="h-8 text-xs"
                  />
                </div>

                <div className="w-full sm:w-36">
                  <div className="mb-1 flex items-center gap-1.5">
                    <Label className="text-xs font-medium text-muted-foreground">Owner</Label>
                    {act.owner.isSuggested && (
                      <Badge
                        variant="outline"
                        className="h-4 border-amber-300 bg-amber-50 px-1 py-0 text-[10px] text-amber-700"
                      >
                        suggested
                      </Badge>
                    )}
                  </div>
                  <Input
                    placeholder="Assignee"
                    value={act.owner.value}
                    onChange={(e) => updateActionField(act.id, "owner", e.target.value)}
                    className="h-8 text-xs"
                  />
                </div>

                <div className="w-full sm:w-32">
                  <div className="mb-1 flex items-center gap-1.5">
                    <Label className="text-xs font-medium text-muted-foreground">Due Date</Label>
                    {act.due.isSuggested && (
                      <Badge
                        variant="outline"
                        className="h-4 border-amber-300 bg-amber-50 px-1 py-0 text-[10px] text-amber-700"
                      >
                        suggested
                      </Badge>
                    )}
                  </div>
                  <Input
                    type="date"
                    value={act.due.value}
                    onChange={(e) => updateActionField(act.id, "due", e.target.value)}
                    className="h-8 text-xs"
                  />
                </div>

                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => removeActionItem(act.id)}
                  className="size-8 shrink-0 self-end text-muted-foreground hover:text-destructive sm:self-center"
                  aria-label="Remove action"
                >
                  <Trash2 className="size-3.5" />
                </Button>
              </div>
            ))}
          </div>
        )}
      </div>

      <DialogFooter className="border-t pt-3">
        <Button variant="outline" onClick={onClose}>
          Close
        </Button>
        <Button
          onClick={handleSave}
          disabled={saveAgendaMutation.isPending}
          className="text-brand-foreground bg-brand hover:bg-brand/90"
        >
          {saveAgendaMutation.isPending ? "Saving..." : "Save agenda"}
        </Button>
      </DialogFooter>
    </div>
  )
}

export function AgendaDialog({ meeting, open, onOpenChange }: AgendaDialogProps) {
  const meetingId = meeting?.id
  const { data: existingAgenda, isLoading: isAgendaLoading } = useAgenda(meetingId)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <span>Agenda & Action Items</span>
            {meeting && (
              <span className="max-w-xs truncate text-sm font-normal text-muted-foreground">
                — {meeting.title}
              </span>
            )}
          </DialogTitle>
          <DialogDescription>
            Paste notes, an email, or a message to automatically parse into structured items.
          </DialogDescription>
        </DialogHeader>

        {isAgendaLoading ? (
          <div className="flex justify-center py-8">
            <Loader2 className="size-6 animate-spin text-muted-foreground" />
          </div>
        ) : meeting ? (
          <AgendaForm
            key={`${meeting.id}-${existingAgenda?.meeting_id ?? "new"}`}
            meeting={meeting}
            existingAgenda={existingAgenda ?? null}
            onClose={() => onOpenChange(false)}
          />
        ) : null}
      </DialogContent>
    </Dialog>
  )
}
