"""Unit tests for pharmacy query expansion — edge cases and regressions."""
import pytest
from prompts import expand_query, TERM_ALIASES


class TestExpandQueryHappyPath:
    def test_oxy_expands_to_oxycodone(self):
        out = expand_query("what is oxy schedule")
        assert "oxycodone" in out
        assert "what is oxy schedule" in out

    def test_xanax_expands(self):
        assert "alprazolam" in expand_query("xanax refill")

    def test_multiple_aliases(self):
        out = expand_query("oxy and xanax")
        assert "oxycodone" in out
        assert "alprazolam" in out

    def test_schedule_ii_phrase(self):
        out = expand_query("schedule ii rules")
        assert "Schedule II" in out

    def test_c2_short(self):
        assert "Schedule II" in expand_query("is this a c2 drug")

    def test_imprint_and_ndc(self):
        out = expand_query("imprint M367 and ndc lookup")
        assert "tablet imprint code" in out
        assert "National Drug Code" in out


class TestExpandQueryEdgeCases:
    def test_empty_string(self):
        assert expand_query("") == ""

    def test_whitespace_only(self):
        assert expand_query("   ") == "   "

    def test_no_alias_passthrough(self):
        q = "What is acetaminophen maximum daily dose?"
        assert expand_query(q) == q

    def test_epoxy_does_not_match_oxy(self):
        """Substring false positive: epoxy must NOT expand to oxycodone."""
        out = expand_query("epoxy coating safety")
        assert "oxycodone" not in out
        assert out == "epoxy coating safety"

    def test_cii_case_insensitive(self):
        for q in ("CII refill", "cii refill", "Cii refill"):
            assert "Schedule II" in expand_query(q), f"failed for {q!r}"

    def test_ciii_case_insensitive(self):
        assert "Schedule III" in expand_query("CIII limits")

    def test_dedupe_formal_terms(self):
        out = expand_query("vicodin or norco")
        assert out.count("hydrocodone acetaminophen") == 1

    def test_long_query_preserved(self):
        q = "A" * 500 + " xanax"
        out = expand_query(q)
        assert "alprazolam" in out

    def test_special_characters_safe(self):
        out = expand_query("imprint: M367 / NDC?")
        assert "tablet imprint code" in out

    def test_aliases_are_lowercase_keys(self):
        for k in TERM_ALIASES:
            assert k == k.lower(), f"alias key should be lowercase: {k}"
