{
  python312,
  firecrawl-py,
  qdrant-client,
}:

python312.withPackages (_: [
  firecrawl-py
  qdrant-client
])
