# 🧑‍💻 ai-databases-demos

Side-by-side demos of **AI database capabilities on Azure** — keyword, vector, and hybrid
search over the same book catalogue, implemented twice: once in **Azure Cosmos DB for NoSQL**
and once in **Azure Database for PostgreSQL**.

The point of the repo is the comparison. Both halves answer the same question
("find me a lighthearted story about friendship and adventure") against the same 1,000 records,
so you can see where the two engines agree and where they diverge.

## 📁 Repository layout

| Path | What it is |
| --- | --- |
| `src/ai-db-demos.ipynb` | The main demo notebook — everything below happens here. |
| `src/chat.py` | Minimal standalone Foundry agent sample. |
| `data/books.csv` | Source dataset (title, authors, categories, description). |
| `assets/` | Screenshots embedded in the notebook. |
| `.env.example` | Template for the required environment variables. |

## 📓 What the notebook covers

The notebook is split into two mirrored sections. Each follows the same four-stage arc, so the
headings line up one-to-one in the Outline view.

| Stage | Azure Cosmos DB for NoSQL | Azure Database for PostgreSQL |
| --- | --- | --- |
| Setup | Container with vector + full-text policies | `vector`, `pg_diskann`, `azure_ai` extensions |
| Data insertion | `upsert_item` per document | `INSERT ... ON CONFLICT DO NOTHING` |
| Embeddings | Generated in the **app** via the Foundry SDK | Generated **inside the database** via `azure_openai.create_embeddings` |
| Search | `CONTAINS`, `VectorDistance`, `RRF` | `to_tsvector`, `<=>`, hand-written RRF |

The most interesting contrast is the last two rows:

- **Where embeddings are generated.** Cosmos DB embeds in application code and sends the vector
  with the query. PostgreSQL calls Azure OpenAI from within the SQL statement itself, so no vector
  ever crosses the wire.
- **Hybrid search.** Cosmos DB has a built-in `RRF()` rank-fusion function. PostgreSQL has no
  equivalent, so the notebook writes Reciprocal Rank Fusion out by hand with CTEs and a
  `FULL OUTER JOIN`.

Each search section starts with an ℹ️ markdown cell that shows the query shape and explains the
parts that aren't obvious from reading the SQL, followed by a 📚 References cell linking the
official Microsoft Learn docs.

## ☁️ Azure resources

| Resource | Used for | Configuration that matters |
| --- | --- | --- |
| **Microsoft Foundry** (Azure AI Services) | Embeddings + chat | Deployments for `text-embedding-3-small`, `text-embedding-3-large`, and a chat model |
| **Azure Cosmos DB for NoSQL** | Vector + full-text + hybrid search | NoSQL Vector Search and Full Text Search features enabled on the account |
| **Azure Database for PostgreSQL flexible server** | Vector + full-text + hybrid search | `vector`, `pg_diskann`, `azure_ai` on the extension allow-list; Entra ID auth; system-assigned managed identity |

### 🚀 Provisioning

```powershell
$RG       = "rg-ai-databases-demos"
$LOCATION = "swedencentral"

az group create --name $RG --location $LOCATION

# Cosmos DB for NoSQL, with vector search enabled
az cosmosdb create --name <cosmos-account> --resource-group $RG `
  --capabilities EnableNoSQLVectorSearch

# PostgreSQL flexible server with Entra ID authentication
az postgres flexible-server create --name <pg-server> --resource-group $RG `
  --location $LOCATION --tier Burstable --sku-name Standard_B2s `
  --active-directory-auth Enabled

# Allow the extensions the demo needs (this is the server allow-list,
# CREATE EXTENSION still has to run per-database — the notebook does that)
az postgres flexible-server parameter set --resource-group $RG --server-name <pg-server> `
  --name azure.extensions --value vector,pg_diskann,azure_ai

# Foundry / Azure AI Services account
az cognitiveservices account create --name <foundry-resource> --resource-group $RG `
  --location $LOCATION --kind AIServices --sku S0
```

Then, in the portal or CLI:

1. Enable **Full Text Search for NoSQL API** on the Cosmos DB account (Settings → Features).
2. Create the three model deployments on the Foundry resource and note the **deployment names** —
   those are what go in `.env`, not the model names.
3. Add yourself as the **Entra ID admin** on the PostgreSQL server.
4. Assign the PostgreSQL server a **system-assigned managed identity** and grant it
   **Cognitive Services OpenAI User** on the Foundry resource — this is what lets `azure_ai`
   call the embedding model without an API key.
5. Grant yourself the **Cosmos DB Built-in Data Contributor** role (data-plane RBAC is separate
   from control-plane RBAC).

## ⚙️ Getting started

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt

Copy-Item .env.example .env   # then fill in your values
azd auth login
```

Open `src/ai-db-demos.ipynb`, select the `.venv` kernel, and run the cells top to bottom.

## ⚠️ Notes and gotchas

These are the things that actually bit during development:

- **Embedding dimensions drive the index choice.** `text-embedding-3-large` returns 3,072
  dimensions, but `pg_diskann` — like `hnsw` and `ivfflat` — caps at **2,000**. The PostgreSQL
  section therefore uses `text-embedding-3-small` (1,536), which also matches the Cosmos DB
  vector policy. Switching models means clearing the column and re-embedding.
- **Rate limits.** Embedding 1,000 rows from inside PostgreSQL is 1,000 sequential HTTP calls.
  The notebook batches them 50 at a time, pauses between chunks, and backs off exponentially on
  `RateLimitReached`. Because each chunk commits independently and the loop targets
  `WHERE embeddings IS NULL`, re-running the cell resumes rather than restarting.
- **Allow-listed ≠ installed.** An extension appearing in `azure.extensions` only means you're
  *permitted* to install it; `CREATE EXTENSION` still has to run in each database.
- **Cosmos DB vector policies are immutable.** Changing dimensions or the distance function means
  recreating the container.
- **Clear notebook outputs before committing** so diffs stay reviewable.
