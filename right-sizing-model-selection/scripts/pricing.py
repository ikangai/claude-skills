"""Shared cost ranking for routing decisions: rank models by real blended $/MTok.

Scale: 0.0 = free (local LM Studio, or :free OpenRouter variants); haiku = 1.0;
sonnet = 3.0; opus = 5.0; fable = 10.0; or:-prefixed models are placed by their
actual price from references/openrouter-models.json (unknown ones default to 2.0 —
assume sonnet-ish until registered). "Cheapest passing model" everywhere means
lowest cost_rank among those meeting the quality bar.
"""
import json
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
OR_REGISTRY = SKILL_DIR / "references" / "openrouter-models.json"

# $/MTok (input, output)
CLAUDE_PRICES = {"haiku": (1, 5), "sonnet": (3, 15), "opus": (5, 25), "fable": (10, 50)}


def blended(pin, pout):
    return (pin + pout) / 2


_HAIKU_BLEND = blended(*CLAUDE_PRICES["haiku"])  # 3.0
_or_cache = None


def _or_prices():
    global _or_cache
    if _or_cache is None:
        try:
            data = json.loads(OR_REGISTRY.read_text())
            _or_cache = {f"or:{m['id']}": (m["usd_per_mtok_in"], m["usd_per_mtok_out"])
                         for m in data["models"]}
        except (OSError, json.JSONDecodeError, KeyError):
            _or_cache = {}
    return _or_cache


def cost_rank(model):
    if model in CLAUDE_PRICES:
        return blended(*CLAUDE_PRICES[model]) / _HAIKU_BLEND
    if model.startswith("or:"):
        prices = _or_prices().get(model)
        if prices:
            return blended(*prices) / _HAIKU_BLEND
        return 2.0  # unregistered OpenRouter model — add it to openrouter-models.json
    return 0.0  # local LM Studio
