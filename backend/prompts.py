"""Pharmacy-specific prompt templates for medication identification and DEA regulations."""

import re

from langchain_core.prompts import ChatPromptTemplate, PromptTemplate

SYSTEM_PHARMACY = """You are a knowledgeable, careful Pharmacy Assistant AI specializing in medication identification and DEA (Drug Enforcement Administration) controlled substance regulations.

Your responsibilities:
1. Medication Identification: Help identify medications from imprint codes, NDC numbers, brand/generic names, physical descriptions (color, shape, scoring). Always note confidence and recommend verifying with official sources or a licensed pharmacist.
2. DEA Regulations: Provide accurate information on controlled substance schedules (I-V), prescribing rules, dispensing requirements, recordkeeping, registration, and diversion prevention based on the Controlled Substances Act (CSA) and DEA Pharmacist's Manual guidance.
3. Safety first: Never provide medical advice, dosing recommendations for patients, or encourage illegal activity. Always include disclaimers that this is for educational/informational purposes and users should consult licensed professionals and official DEA/FDA sources.
4. Cite sources from the retrieved context when possible. If information is not in the knowledge base, say so clearly.

Be precise, professional, and cite schedules accurately (e.g., Schedule II has high abuse potential and severe dependence risk, no refills without new prescription in most cases).
"""

RAG_PROMPT = ChatPromptTemplate.from_messages([
    ("system", SYSTEM_PHARMACY + "\n\nUse the following retrieved context to answer the question. If the context does not contain relevant information, say you do not have sufficient information in the knowledge base.\n\nContext:\n{context}"),
    ("human", "{question}")
])

MED_ID_PROMPT = PromptTemplate.from_template(
    """Given the medication description or imprint: {query}

Identify possible matches. Include:
- Brand and generic names
- Strength
- Manufacturer if known
- Controlled substance schedule if applicable
- Common uses (high level)
- Any identification caveats

Retrieved knowledge:\n{context}

Answer carefully with confidence level."""
)

DEA_QUERY_PROMPT = PromptTemplate.from_template(
    """Answer the following question about DEA regulations, controlled substance schedules, or pharmacy compliance:

Question: {query}

Retrieved context from DEA-related documents:\n{context}

Provide a clear, accurate summary with references to schedules or sections where possible. Include disclaimers."""
)

# Keys stored lowercase for case-insensitive matching
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
    """Expand query with pharmacy term aliases for better retrieval.

    Uses case-insensitive word-boundary matching so short aliases like
    "oxy" do not match inside unrelated words (e.g. "epoxy").
    Longer aliases are applied first; formal expansions are de-duplicated.
    """
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
