import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

import { api } from "@/lib/api"
import type { AgendaCreate, AgendaRead } from "@/types"

export function useAgenda(meetingId?: string) {
  return useQuery({
    queryKey: ["agenda", meetingId],
    queryFn: async () => {
      if (!meetingId) return null
      try {
        return await api.getAgenda(meetingId)
      } catch (err: unknown) {
        if (
          typeof err === "object" &&
          err !== null &&
          "status" in err &&
          (err as { status: unknown }).status === 404
        ) {
          return null
        }
        throw err
      }
    },
    enabled: Boolean(meetingId),
  })
}

export function useSaveAgenda() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ meetingId, data }: { meetingId: string; data: AgendaCreate }) =>
      api.saveAgenda(meetingId, data),
    onSuccess: (savedAgenda: AgendaRead) => {
      queryClient.setQueryData(["agenda", savedAgenda.meeting_id], savedAgenda)
      queryClient.invalidateQueries({ queryKey: ["agenda", savedAgenda.meeting_id] })
    },
  })
}
