import React, { Component, useState, useRef, useEffect } from 'react'
import axios from 'axios'
import SonoranForgeLogo from './SonoranForgeLogo'
import { parseApiError } from './apiErrors'

const API = import.meta.env.VITE_API_URL || '/api'
const QUICK = [
  'What is the DEA schedule for oxycodone?',
  'Explain Schedule II prescribing and refill rules.',
  'Identify white oval tablet imprint M367',
  'Pharmacy recordkeeping for controlled substances',
  'Difference between Schedule III and IV',
  'Can Schedule II prescriptions be refilled?',
]

/** Keep React from crashing if a value is not a renderable string */
function asText(value, fallback = '') {
  if (value == null) return fallback
  if (typeof value === 'string') return value
  if (typeof value === 'number' || typeof value === 'boolean') return String(value)
  try {
    return JSON.stringify(value)
  } catch {
    return fallback
  }
}

function normalizeSources(raw) {
  if (!Array.isArray(raw)) return []
  return raw.map((s) => {
    if (typeof s === 'string') return s
    if (s && typeof s === 'object') {
      return asText(s.source || s.filename || s.name || s, JSON.stringify(s))
    }
    return asText(s)
  })
}

function ErrorBlock({ error }) {
  if (!error) return null
  return (
    <div className="api-error" role="alert">
      <div className="api-error-header">
        <span className="api-error-code">{asText(error.code, 'ERROR')}</span>
        {error.status != null && (
          <span className="api-error-status">HTTP {asText(error.status)}</span>
        )}
      </div>
      <div className="api-error-message">{asText(error.message, 'Request failed')}</div>
      {error.detail && (
        <details className="api-error-detail">
          <summary>Technical detail</summary>
          <pre>{asText(error.detail)}</pre>
        </details>
      )}
      {error.hint && (
        <div className="api-error-hint">
          <strong>Hint:</strong> {asText(error.hint)}
        </div>
      )}
    </div>
  )
}

class ErrorBoundary extends Component {
  constructor(props) {
    super(props)
    this.state = { error: null }
  }

  static getDerivedStateFromError(error) {
    return { error }
  }

  componentDidCatch(error, info) {
    console.error('UI crash:', error, info)
  }

  render() {
    if (this.state.error) {
      return (
        <div className="app-shell" style={{ padding: '2rem', color: '#efe4d0' }}>
          <h1>Something went wrong in the UI</h1>
          <p style={{ color: '#a89888', marginTop: '0.75rem' }}>
            {asText(this.state.error?.message, 'Unknown render error')}
          </p>
          <button
            type="button"
            className="btn-primary"
            style={{ marginTop: '1rem', padding: '0.6rem 1.2rem' }}
            onClick={() => window.location.reload()}
          >
            Reload
          </button>
        </div>
      )
    }
    return this.props.children
  }
}

function AppInner() {
  const [msgs, setMsgs] = useState([{
    role: 'bot',
    text: 'Hello — Pharmacy AI Assistant for medication identification and DEA regulations.\n\nAsk about schedules I–V, prescribing rules, imprint codes, or recordkeeping.\n\nNot a substitute for licensed professional judgment or official DEA sources.',
    sources: [],
    error: null,
  }])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const [imprint, setImprint] = useState('')
  const [ndc, setNdc] = useState('')
  const [name, setName] = useState('')
  const end = useRef(null)
  useEffect(() => {
    try {
      end.current?.scrollIntoView({ behavior: 'smooth' })
    } catch {
      /* ignore */
    }
  }, [msgs, busy])

  async function send(q, opts = {}) {
    const query = asText(q || input).trim()
    if (!query || busy) return
    const endpoint = opts.endpoint || 'chat'
    const mode = opts.mode || 'general'
    setInput('')
    setMsgs((m) => [...m, { role: 'user', text: query, sources: [], error: null }])
    setBusy(true)
    try {
      const url = `${API.replace(/\/$/, '')}/${endpoint.replace(/^\//, '')}`
      const { data } = await axios.post(
        url,
        { message: query, session_id: 'web', mode },
        { timeout: 180000 },
      )
      const answer = asText(
        data?.answer ?? data?.response,
        'No answer returned from the API.',
      )
      setMsgs((m) => [
        ...m,
        {
          role: 'bot',
          text: answer,
          sources: normalizeSources(data?.sources),
          error: null,
        },
      ])
    } catch (e) {
      console.error('API error', e)
      let parsed
      try {
        parsed = parseApiError(e)
      } catch (parseErr) {
        parsed = {
          code: 'CLIENT_ERROR',
          message: asText(e?.message, 'Request failed'),
          detail: asText(parseErr?.message),
          hint: 'Open DevTools → Network and confirm POST /api/chat reaches the backend.',
          status: e?.response?.status ?? null,
        }
      }
      setMsgs((m) => [
        ...m,
        {
          role: 'bot',
          text: '',
          sources: [],
          error: parsed,
        },
      ])
    } finally {
      setBusy(false)
    }
  }

  function identify() {
    const parts = []
    if (imprint.trim()) parts.push(`imprint "${imprint.trim()}"`)
    if (ndc.trim()) parts.push(`NDC ${ndc.trim()}`)
    if (name.trim()) parts.push(`name "${name.trim()}"`)
    if (!parts.length) return
    send(
      `Identify medication with ${parts.join(', ')}. Include brand/generic, strength, DEA schedule if controlled.`,
      { endpoint: 'meds/identify', mode: 'med_id' },
    )
  }

  return (
    <div className="app-shell">
      <header className="header">
        <div className="brand">
          <SonoranForgeLogo size={48} className="brand-logo" />
          <div className="brand-text">
            <div className="brand-title-row">
              <h1>Pharmacy AI Assistant</h1>
              <span className="badge">Med ID + DEA</span>
            </div>
            <span className="brand-sub">Sonoran Forge</span>
          </div>
        </div>
        <div className="header-right">
          <span className="meta">Assessment III · RAG</span>
        </div>
      </header>

      <div className="layout">
        <section className="chat" aria-label="Conversation">
          <div className="msgs">
            {msgs.map((m, i) => (
              <div key={i} className={`msg ${m.role}${m.error ? ' is-error' : ''}`}>
                <div className="role-label">{m.role === 'user' ? 'You' : 'Assistant'}</div>
                {m.error ? <ErrorBlock error={m.error} /> : asText(m.text)}
                {m.sources?.length > 0 && (
                  <div className="src">
                    <strong>Sources</strong>
                    {m.sources.map((s, j) => (
                      <div key={j}>{asText(s)}</div>
                    ))}
                  </div>
                )}
              </div>
            ))}
            {busy && (
              <div className="msg bot thinking">
                <span className="pulse" /> Thinking…
              </div>
            )}
            <div ref={end} />
          </div>

          <div className="composer">
            <textarea
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault()
                  send()
                }
              }}
              placeholder="Ask about imprint codes, schedules, or prescribing rules…"
              disabled={busy}
              rows={2}
              aria-label="Message"
            />
            <button
              type="button"
              className="btn-primary"
              onClick={() => send()}
              disabled={busy || !input.trim()}
            >
              Send
            </button>
          </div>
        </section>

        <aside className="side" aria-label="Tools">
          <div className="card card-identify">
            <div className="card-head">
              <h3>Medication ID</h3>
              <p className="card-hint">Tablet imprint, NDC, or name</p>
            </div>
            <label className="field">
              <span>Imprint</span>
              <input
                placeholder="e.g. M367"
                value={imprint}
                onChange={(e) => setImprint(e.target.value)}
                autoComplete="off"
              />
            </label>
            <label className="field">
              <span>NDC</span>
              <input
                placeholder="Optional"
                value={ndc}
                onChange={(e) => setNdc(e.target.value)}
                autoComplete="off"
              />
            </label>
            <label className="field">
              <span>Drug name</span>
              <input
                placeholder="Optional"
                value={name}
                onChange={(e) => setName(e.target.value)}
                autoComplete="off"
              />
            </label>
            <button
              type="button"
              className="btn-primary btn-block"
              onClick={identify}
              disabled={busy || (!imprint.trim() && !ndc.trim() && !name.trim())}
            >
              Identify
            </button>
          </div>

          <div className="card">
            <div className="card-head">
              <h3>Quick questions</h3>
            </div>
            <div className="quick-list">
              {QUICK.map((q, i) => (
                <button
                  key={i}
                  type="button"
                  className="quick"
                  onClick={() => send(q)}
                  disabled={busy}
                >
                  {q}
                </button>
              ))}
            </div>
          </div>

          <div className="card card-disclaimer">
            <h3>Disclaimer</h3>
            <p className="disclaimer">
              Educational tool only. Grounded in sample DEA and medication docs.
              Not professional advice. Verify with the official DEA Pharmacist&apos;s
              Manual, CFR, and licensed pharmacists.
            </p>
          </div>

          <footer className="side-footer">
            <img
              src="/brand/sf-banner-lockup.png"
              alt="Sonoran Forge"
              className="side-lockup"
            />
          </footer>
        </aside>
      </div>
    </div>
  )
}

export default function App() {
  return (
    <ErrorBoundary>
      <AppInner />
    </ErrorBoundary>
  )
}
