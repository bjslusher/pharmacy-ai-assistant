import React, { useState, useRef, useEffect } from 'react'
import axios from 'axios'

const API = import.meta.env.VITE_API_URL || '/api'
const QUICK = [
  'What is the DEA schedule for oxycodone?',
  'Explain Schedule II prescribing and refill rules.',
  'Identify white oval tablet imprint M367',
  'Pharmacy recordkeeping for controlled substances',
  'Difference between Schedule III and IV',
  'Can Schedule II prescriptions be refilled?'
]

export default function App() {
  const [msgs, setMsgs] = useState([{
    role: 'bot',
    text: 'Hello! Pharmacy AI Assistant for medication identification and DEA regulations.\n\nAsk about schedules I–V, prescribing rules, imprint codes, or recordkeeping.\n\nNot a substitute for licensed professional judgment or official DEA sources.',
    sources: []
  }])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const [imprint, setImprint] = useState('')
  const [ndc, setNdc] = useState('')
  const [name, setName] = useState('')
  const end = useRef(null)
  useEffect(() => end.current?.scrollIntoView({ behavior: 'smooth' }), [msgs])

  async function send(q) {
    const query = (q || input).trim()
    if (!query || busy) return
    setInput('')
    setMsgs(m => [...m, { role: 'user', text: query, sources: [] }])
    setBusy(true)
    try {
      const { data } = await axios.post(`${API}/chat`, { message: query, session_id: 'web' }, { timeout: 120000 })
      setMsgs(m => [...m, { role: 'bot', text: data.answer || data.response || 'No answer', sources: data.sources || [] }])
    } catch (e) {
      setMsgs(m => [...m, { role: 'bot', text: `Error: ${e.response?.data?.detail || e.message}. Is the backend running?`, sources: [] }])
    }
    setBusy(false)
  }

  function identify() {
    const parts = []
    if (imprint) parts.push(`imprint "${imprint}"`)
    if (ndc) parts.push(`NDC ${ndc}`)
    if (name) parts.push(`name "${name}"`)
    if (!parts.length) return
    send(`Identify medication with ${parts.join(', ')}. Include brand/generic, strength, DEA schedule if controlled.`)
  }

  return (
    <>
      <header className="header">
        <h1>💊 Pharmacy AI Assistant <span style={{fontSize:'0.7rem',background:'rgba(255,255,255,0.2)',padding:'2px 8px',borderRadius:99}}>Med ID + DEA</span></h1>
        <span style={{fontSize:'0.85rem',opacity:0.9}}>Assessment III · RAG · Mem0</span>
      </header>
      <div className="layout">
        <section className="chat">
          <div className="msgs">
            {msgs.map((m,i) => (
              <div key={i} className={`msg ${m.role}`}>
                <div style={{fontSize:'0.7rem',fontWeight:600,opacity:0.7,marginBottom:4}}>{m.role==='user'?'You':'Assistant'}</div>
                {m.text}
                {m.sources?.length > 0 && (
                  <div className="src">
                    <strong>Sources:</strong>
                    {m.sources.map((s,j) => <div key={j}>{typeof s==='string'?s:(s.source||s.filename||JSON.stringify(s))}</div>)}
                  </div>
                )}
              </div>
            ))}
            {busy && <div className="msg bot">Thinking…</div>}
            <div ref={end} />
          </div>
          <div className="input-row">
            <textarea value={input} onChange={e=>setInput(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();send()}}} placeholder="Ask about med ID or DEA regs…" disabled={busy} rows={1} />
            <button onClick={()=>send()} disabled={busy||!input.trim()}>Send</button>
          </div>
        </section>
        <aside className="side">
          <div className="card">
            <h3>🔍 Medication ID</h3>
            <input placeholder="Imprint e.g. M367" value={imprint} onChange={e=>setImprint(e.target.value)} />
            <input placeholder="NDC optional" value={ndc} onChange={e=>setNdc(e.target.value)} />
            <input placeholder="Drug name optional" value={name} onChange={e=>setName(e.target.value)} />
            <button onClick={identify} disabled={busy}>Identify</button>
          </div>
          <div className="card">
            <h3>⚡ Quick Questions</h3>
            {QUICK.map((q,i)=><button key={i} className="quick" onClick={()=>send(q)} disabled={busy}>{q}</button>)}
          </div>
          <div className="card">
            <h3>⚠️ Disclaimer</h3>
            <div className="disclaimer">Educational tool only. Grounded in sample DEA/med docs. Not professional advice. Verify with official DEA Pharmacist's Manual, CFR, and licensed pharmacists.</div>
          </div>
        </aside>
      </div>
    </>
  )
}
