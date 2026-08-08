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
            + "If context is insufficient, say so. Do not invent schedules or imprints. "
            + "When an imprint code (e.g. M367) appears in the context with a drug name, report that match.",
        ),
        ("human", "{question}"),
    ]
)

MED_ID_PROMPT = PromptTemplate.from_template(
    """You must identify medications ONLY from the retrieved knowledge-base context.

User query: {query}

Retrieved Chroma context:
{context}

Instructions:
- Scan the context for the exact imprint code the user mentioned (e.g. M367, M 367).
- If found, report: drug name (brand/generic if present), strength, DEA schedule if stated, and that this is educational seed data.
- If the imprint is not in the context, say the knowledge base has no match for that code.
- Do not invent imprints that are not written in the context.
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
    "perc": "oxycodone acetaminophen",
    "hydro": "hydrocodone",
}

# Tablet imprint codes in seed data (boost retrieval when user types the code)
IMPRINT_BOOST = {
    "m367": "imprint M367 hydrocodone bitartrate 10 mg acetaminophen 325 mg Schedule II white oval",
    "m366": "imprint M366 hydrocodone 7.5 mg acetaminophen 325 mg",
    "m365": "imprint M365 hydrocodone 5 mg acetaminophen 325 mg",
    "oc 10": "imprint OC 10 OxyContin oxycodone extended-release",
    "oc 20": "imprint OC 20 OxyContin oxycodone extended-release",
    "oc 40": "imprint OC 40 OxyContin oxycodone extended-release",
    "oc 80": "imprint OC 80 OxyContin oxycodone extended-release",
}

# Alphanumeric imprint-like tokens (e.g. M367, AD10, alza18)
_IMPRINT_TOKEN = re.compile(r"\b([A-Za-z]{1,4}\s?\d{2,4}|\d{2,4}\s?[A-Za-z]{1,4})\b")


def expand_query(query: str) -> str:
    """Expand slang + imprint codes so Chroma similarity ranks the right seed chunks."""
    if not query or not str(query).strip():
        return query
    lower = query.lower()
    expansions: list[str] = []
    seen: set[str] = set()

    items = sorted(TERM_ALIASES.items(), key=lambda kv: len(kv[0]), reverse=True)
    for alias, formal in items:
        pattern = r"(?<!\w)" + re.escape(alias) + r"(?!\w)"
        if re.search(pattern, lower) and formal not in seen:
            expansions.append(formal)
            seen.add(formal)

    # Explicit imprint boost map
    for code, boost in IMPRINT_BOOST.items():
        if re.search(r"(?<!\w)" + re.escape(code).replace(r"\ ", r"\s*") + r"(?!\w)", lower):
            if boost not in seen:
                expansions.append(boost)
                seen.add(boost)

    # Generic imprint token → "imprint CODE identification"
    for m in _IMPRINT_TOKEN.finditer(query):
        token = m.group(1)
        compact = re.sub(r"\s+", "", token).upper()
        boost = f"imprint code {token} {compact} tablet identification"
        if boost not in seen:
            expansions.append(boost)
            seen.add(boost)

    if expansions:
        return f"{query.strip()} | " + " | ".join(expansions)
    return query.strip()
