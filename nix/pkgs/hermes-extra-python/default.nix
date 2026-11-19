{
  python312,
  ollama,
}:

# Extra Python packages injected into the hermes agent venv via
# PYTHONPATH. History: this carried firecrawl-py + qdrant-client for
# the firecrawl web plugin era; since the DonSeTch switch the only
# remaining need is the `ollama` pip client (mem0 OSS llm/embedder
# import `from ollama import Client` — mem0ai itself only ships
# qdrant-client; the ollama client is the upstream `llms` extra).
#
# MUST track the Python version of the upstream hermes-agent package:
# the PYTHONPATH prefix shadows the agent's own site-packages, and a
# C-extension built for a different interpreter ABI breaks the import
# (pydantic_core._pydantic_core missing when the agent and injected
# packages use different Python ABIs).
python312.withPackages (_: [
  ollama
])
