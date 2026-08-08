"""Pharmacy-specific prompt templates — answers must come from retrieved Chroma context only."""

import re

from langchain_core.prompts import ChatPromptTemplate, PromptTemplate

CONTEXT_ONLY_RULES = """
CRITICAL GROUNDING RULES:
1. Answer ONLY using the retrieved knowledge-base context provided below (from Chroma vector search).
2. Do NOT use outside world knowledge, training recall, or speculation beyond that context.
3. If the context is empty or does not contain the answer, say clearly that the knowledge base does not have that information.
4. When you use a fact from context, prefer citing the source filename shown in [Source: ...].
5. Educational use only — not medical, legal, or dispensing advice.
""".strip()

SYSTEM_PHARMACY = f"""You are a Pharmacy Assistant AI for medication identification and DEA controlled-substance education.

{CONTEXT_ONLY_RULES}

Domain focus (still only if present in context):
- Tablet imprint / NDC style identification from seed docs
- DEA schedules I–V, prescribing/refill rules, recordkeeping summaries
"""

RAG_PROMPT = ChatPromptTemplate.from_messages(
    [
        (
            "system",
            SYSTEM_PHARMACY
            + "\n\nRetrieved knowledge-base context (Chroma similarity search):\n{context}\n\n"
            + "If context is insufficient, say so. Do not invent schedules or imprints.",
        ),
        ("human", "{question}"),
    ]
)

MED_ID_PROMPT = PromptTemplate.from_template(
    """You must identify medications ONLY from the retrieved knowledge-base context.

User query: {query}

Retrieved Chroma context:
{context}

If the imprint/name is not in the context, say the knowledge base has no match.
Otherwise list brand/generic, strength, schedule if present in context, and caveats.
"""
)

DEA_QUERY_PROMPT = PromptTemplate.from_template(
    """Answer this DEA/schedule question ONLY from the retrieved knowledge-base context.

Question: {query}

Retrieved Chroma context:
{context}

If the context lacks the answer, say the knowledge base does not cover it.
Include a short educational disclaimer.
"""
)

TERM_ALIASES = {
    "oxy": "oxycodone",
    "percs": "oxycodone acetaminophen",
    "vikes": "hydrocodone",
    "vicodin": "hydrocodone acetaminophen",
    "norco": "hydrocodone acetaminophen",
    "xanax": "alprazolam",
    "valium": "diazepam",
    "adderall": "amphetamine mixed salts",
    "ritalin": "methylphenidate",
    "fent": "fentanyl",
    "methadone": "methadone",
    "suboxone": "buprenorphine naloxone",
    "schedule 2": "Schedule II",
    "schedule ii": "Schedule II",
    "c2": "Schedule II",
    "cii": "Schedule II",
    "c3": "Schedule III",
    "ciii": "Schedule III",
    "dea number": "DEA registration number",
    "ndc": "National Drug Code",
    "imprint": "tablet imprint code",
}


def expand_query(query: str) -> str:
    if not query or not str(query).strip():
        return query
    lower = query.lower()
    expansions = []
    seen = set()
    items = sorted(TERM_ALIASES.items(), key=lambda kv: len(kv[0]), reverse=True)
    for alias, formal in items:
        pattern = r"(?<!\w)" + re.escape(alias) + r"(?!\w)"
        if re.search(pattern, lower) and formal not in seen:
            expansions.append(formal)
            seen.add(formal)
    if expansions:
        return f"{query} ({', '.join(expansions)})"
    return query
