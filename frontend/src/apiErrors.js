/**
 * Parse Pharmacy AI structured API errors for UI display.
 *
 * Expected body shape:
 * {
 *   error: { code, message, status, detail?, hint? },
 *   detail: "..."   // FastAPI-compatible string
 * }
 */

export function parseApiError(err) {
  const status = err?.response?.status ?? null
  const data = err?.response?.data

  // Structured envelope from backend _error_body()
  const nested = data?.error && typeof data.error === 'object' ? data.error : null

  let code = nested?.code || null
  let message = nested?.message || null
  let detail = nested?.detail || null
  let hint = nested?.hint || null

  // Fallback: top-level detail string (FastAPI / older handlers)
  if (!message && data?.detail) {
    if (typeof data.detail === 'string') {
      message = data.detail
    } else if (Array.isArray(data.detail)) {
      // Pydantic validation list
      message = 'Request validation failed'
      detail = JSON.stringify(data.detail)
      code = code || 'VALIDATION_ERROR'
    } else {
      message = JSON.stringify(data.detail)
    }
  }

  // Network / timeout / no response
  if (!err?.response) {
    code = code || 'NETWORK_ERROR'
    message = message || err?.message || 'Network error'
    hint =
      hint ||
      'Is the backend running? Try: bash scripts/run.sh status  and  curl http://localhost:8000/api/health'
  }

  if (!message) {
    message = err?.message || 'Unknown error'
  }

  // Default hints by status when server omitted them
  if (!hint && status) {
    if (status === 422) {
      hint = 'Check message (1–4000 chars, non-blank) and mode (general|med_id|dea).'
    } else if (status === 503) {
      hint =
        'RAG/LLM not ready. Ensure Ollama is up and models are pulled (bash scripts/run.sh logs).'
    } else if (status === 413) {
      hint = 'File exceeds max upload size (default 5 MB).'
    } else if (status >= 500) {
      hint = 'Check backend logs: bash scripts/run.sh logs'
    }
  }

  if (!code && status) {
    const map = {
      400: 'BAD_REQUEST',
      404: 'NOT_FOUND',
      413: 'PAYLOAD_TOO_LARGE',
      422: 'VALIDATION_ERROR',
      500: 'INTERNAL_ERROR',
      503: 'SERVICE_UNAVAILABLE',
    }
    code = map[status] || `HTTP_${status}`
  }

  if (!code) code = 'UNKNOWN_ERROR'

  return {
    code: String(code),
    message: String(message),
    detail: detail != null ? String(detail) : null,
    hint: hint != null ? String(hint) : null,
    status,
  }
}

/** One-line summary for plain text fallbacks */
export function formatApiErrorText(parsed) {
  const parts = [`[${parsed.code}]`]
  if (parsed.status) parts.push(`HTTP ${parsed.status}`)
  parts.push(parsed.message)
  if (parsed.hint) parts.push(`Hint: ${parsed.hint}`)
  return parts.join(' — ')
}
