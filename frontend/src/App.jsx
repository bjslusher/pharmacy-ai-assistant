import React, { useState, useRef, useEffect } from 'react'
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
  'Can Schedule II prescriptions be refilled?'
]

function ErrorBlock({ error }) {
  if (!error) return null
  return (
    <div className="api-error" role="alert">
      <div className="api-error-header">
        <span className="api-error-code">{error.code}</span>
        {error.status != null && (
          <span className="api-error-status">HTTP {error.status}</span>
        )}
      </div>
      <div className="api-error-message">{error.message}</div>
      {error.detail && (
        <details className="api-error-detail">
          <summary>Technical detail</summary>
          <pre>{error.detail}</pre>
        </details>
      )}
      {error.hint && (
        <div className="api-error-hint">
          <strong>Hint:</strong> {error.hint}
        </div>
      )}
    </div>
  )
}

export default function App() {
  const [msgs, setMsgs] = useState([{
    role: 'bot',
    text: 'Hello! Pharmacy AI Assistant for medication identification and DEA regulations.\n\nAsk about schedules I–V, prescribing rules, imprint codes, or recordkeeping.\n\nNot a substitute for licensed professional judgment or official DEA sources.',
    sources: [],
    error: null,
  }])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const [imprint, setImprint] = useState('')
  const [ndc, setNdc] = useState('')
  const [name, setName] = useState('')
  const end = useRef(null)
  useEffect(() => end.current?.scrollIntoView({ behavior: 'smooth' }), [msgs])

  async function send(q, opts = {}) {
    const query = (q || input).trim()
    if (!query || busy) return
    const endpoint = opts.endpoint || 'chat'
    const mode = opts.mode || 'general'
    setInput('')
    setMsgs(m => [...m, { role: 'user', text: query, sources: [], error: null }])
    setBusy(true)
    try {
      const { data } = await axios.post(
        `${API}/${endpoint}`,
        { message: query, session_id: 'web', mode },
        { timeout: 120000 }
      )
      setMsgs(m => [...m, {
        role: 'bot',
        text: data.answer || data.response || 'No answer',
        sources: data.sources || [],
        error: null,
      }])
    } catch (e) {
      const parsed = parseApiError(e)
      setMsgs(m => [...m, {
        role: 'bot',
        text: '',
        sources: [],
        error: parsed,
      }])
    }
    setBusy(false)
  }

  function identify() {
    const parts = []
    if (imprint) parts.push(`imprint "${imprint}"`)
    if (ndc) parts.push(`NDC ${ndc}`)
    if (name) parts.push(`name "${name}"`)
    if (!parts.length) return
    send(
      `Identify medication with ${parts.join(', ')}. Include brand/generic, strength, DEA schedule if controlled.`,
      { endpoint: 'meds/identify', mode: 'med_id' }
    )
  }

  return (
    <>
      <header className="header">
        <div className="brand">
          <SonoranForgeLogo size={40} className="brand-logo" />
          <div className="brand-text">
            <h1>
              Pharmacy AI Assistant
              <span className="badge">Med ID + DEA</span>
            </h1>
            <span className="brand-sub">Sonoran Forge</span>
          </div>
        </div>
        <span className="meta">Assessment III · RAG · Mem0</span>
      </header>
      <div className="layout">
        <section className="chat">
          <div className="msgs">
            {msgs.map((m, i) => (
              <div key={i} className={`msg ${m.role}${m.error ? ' is-error' : ''}`}>
                <div className="role-label">{m.role === 'user' ? 'You' : 'Assistant'}</div>
                {m.error ? (
                  <ErrorBlock error={m.error} />
                ) : (
                  m.text
                )}
                {m.sources?.length > 0 && (
                  <div className="src">
                    <strong>Sources:</strong>
                    {m.sources.map((s, j) => (
                      <div key={j}>{typeof s === 'string' ? s : (s.source || s.filename || JSON.stringify(s))}</div>
                    ))}
                  </div>
                )}
              </div>
            ))}
            {busy && <div className="msg bot">Thinking…</div>}
            <div ref={end} />
          </div>
          <div className="input-row">
            <textarea
              value={input}
              onChange={e => setInput(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send() } }}
              placeholder="Ask about med ID or DEA regs…"
              disabled={busy}
              rows={1}
            />
            <button onClick={() => send()} disabled={busy || !input.trim()}>Send</button>
          </div>
        </section>
        <aside className="side">
          <div className="card">
            <h3>Medication ID</h3>
            <input placeholder="Imprint e.g. M367" value={imprint} onChange={e => setImprint(e.target.value)} />
            <input placeholder="NDC optional" value={ndc} onChange={e => setNdc(e.target.value)} />
            <input placeholder="Drug name optional" value={name} onChange={e => setName(e.target.value)} />
            <button onClick={identify} disabled={busy}>Identify</button>
          </div>
          <div className="card">
            <h3>Quick Questions</h3>
            {QUICK.map((q, i) => (
              <button key={i} className="quick" onClick={() => send(q)} disabled={busy}>{q}</button>
            ))}
          </div>
          <div className="card">
            <h3>Disclaimer</h3>
            <div className="disclaimer">
              Educational tool only. Grounded in sample DEA/med docs. Not professional advice.
              Verify with official DEA Pharmacist's Manual, CFR, and licensed pharmacists.
            </div>
          </div>
        </aside>
      </div>
    </>
  )
}
