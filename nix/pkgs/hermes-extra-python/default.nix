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
python312.withPackages (_: [
  ollama
])
