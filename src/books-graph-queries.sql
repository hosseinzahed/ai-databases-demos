
-- =============================================================================
-- books_graph — Apache AGE queries for the PostgreSQL extension for VS Code
-- =============================================================================
-- Companion to src/ai-db-demos.ipynb. The notebook builds the graph; these
-- queries explore it in the extension's interactive node-edge visualizer.
--
-- Prerequisite: run the notebook's Graph Search build cells first, so that
-- books_graph exists and is populated.
--
-- The visualizer only renders a result when the query:
--   1. returns whole vertices and edges (RETURN a, r, b) rather than scalar
--      properties -- a query returning b.title comes back as plain text and
--      reports "The query returned no graphable data";
--   2. has disp_label set on each node, or nodes show internal IDs instead of
--      names (the notebook's build cell sets it);
--   3. declares one AS (...) column per returned object, including every
--      intermediate node and edge in a multi-hop pattern.
--
-- Column names are quoted throughout because "similar", "count", "order" and
-- "type" are PostgreSQL reserved words and fail with a bare syntax error.
--
-- What this file creates (run the DDL once; after that just run the SELECTs
-- under "Everyday use" at the bottom):
--   public.books_graph_similar          view     Book -SIMILAR_TO-> Book
--   public.books_graph_authors          view     Author -WROTE-> Book -SIMILAR_TO-> Book
--   public.books_graph_neighbourhood()  function one seed book's neighbourhood
--
-- Caveat: AGE documents cypher() inside plpgsql functions and its own test
-- suite covers that, so the function is on a supported path. It does not
-- document cypher() inside a VIEW. The two views are expected to work but are
-- unverified -- if CREATE VIEW errors, wrap that query in a function the same
-- way books_graph_neighbourhood does.
-- =============================================================================


-- Session setup ---------------------------------------------------------------
-- ag_catalog holds cypher(), the agtype type and its operators. This is
-- per connection, so re-run it whenever the extension reconnects.
-- Note: no LOAD 'age' -- Azure preloads the library and LOAD raises a
-- privilege error.
SET search_path = ag_catalog, "$user", public;


-- Sanity check ----------------------------------------------------------------
-- Scalar output, so these two deliberately do NOT render. They exist to tell
-- "empty graph" apart from "wrong query shape". If either returns 0, the graph
-- was never built (or was wiped) -- re-run the notebook build cells.
SELECT * FROM cypher('books_graph', $$
    MATCH (n) RETURN count(n)
$$) AS ("nodes" agtype);

SELECT * FROM cypher('books_graph', $$
    MATCH ()-[r:SIMILAR_TO]->() RETURN count(r)
$$) AS ("similar_to_edges" agtype);


-- 1. The semantic layer -------------------------------------------------------
-- Book -> Book edges derived from the embeddings, which is the one relationship
-- no JOIN could produce.
--
-- Explicitly created in public: with ag_catalog first on the search_path, an
-- unqualified CREATE VIEW would land inside the extension's own schema.
-- Everything is schema-qualified so the view does not depend on search_path
-- once it exists.
CREATE OR REPLACE VIEW public.books_graph_similar AS
SELECT * FROM ag_catalog.cypher('books_graph', $cypher$
    MATCH (b:Book)-[s:SIMILAR_TO]->(n:Book)
    RETURN b, s, n
$cypher$) AS ("b"   ag_catalog.agtype,
              "s"   ag_catalog.agtype,
              "n"   ag_catalog.agtype);


-- 2. Authors joined in --------------------------------------------------------
-- Three hops: who wrote a book, and where that book points semantically.
-- Plain MATCH rather than OPTIONAL MATCH, so no column comes back null --
-- a null vertex or edge gives the visualizer nothing to draw for that row.
CREATE OR REPLACE VIEW public.books_graph_authors AS
SELECT * FROM ag_catalog.cypher('books_graph', $cypher$
    MATCH (a:Author)-[w:WROTE]->(b:Book)-[s:SIMILAR_TO]->(n:Book)
    RETURN a, w, b, s, n
$cypher$) AS ("a"   ag_catalog.agtype,
              "w"   ag_catalog.agtype,
              "b"   ag_catalog.agtype,
              "s"   ag_catalog.agtype,
              "n"   ag_catalog.agtype);


-- 3. One book's neighbourhood -------------------------------------------------
-- The shape the notebook draws as SVG. A view can't take an argument, so this
-- one is a function.
--
-- cypher()'s third argument must be a bind parameter, never a literal. Inside
-- plpgsql a declared agtype variable satisfies that, which is why this works
-- here without the PREPARE/EXECUTE dance the notebook's Python helper needs.
--
-- json_build_object escapes the title for us. Building the JSON with format()
-- and %s would break on any title containing an apostrophe -- and this dataset
-- has "Hallowe'en Party" and "Mrs McGinty's Dead".
CREATE OR REPLACE FUNCTION public.books_graph_neighbourhood(seed_title text)
RETURNS TABLE ("seed" ag_catalog.agtype,
               "s"    ag_catalog.agtype,
               "n"    ag_catalog.agtype,
               "w"    ag_catalog.agtype,
               "a"    ag_catalog.agtype)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    params ag_catalog.agtype;
BEGIN
    params := json_build_object('title', seed_title)::text::ag_catalog.agtype;

    RETURN QUERY
    SELECT * FROM ag_catalog.cypher('books_graph', $cypher$
        MATCH (seed:Book {title: $title})-[s:SIMILAR_TO]->(n:Book)
        MATCH (n)<-[w:WROTE]-(a:Author)
        RETURN seed, s, n, w, a
    $cypher$, params) AS ("seed" ag_catalog.agtype,
                          "s"    ag_catalog.agtype,
                          "n"    ag_catalog.agtype,
                          "w"    ag_catalog.agtype,
                          "a"    ag_catalog.agtype);
END;
$function$;


-- =============================================================================
-- Everyday use -- this is what to run during the demo
-- =============================================================================

-- LIMIT lives at the call site, not in the view: 1,500 SIMILAR_TO edges at once
-- makes an unreadable hairball. Raise it to show the graph growing.
SELECT * FROM public.books_graph_similar LIMIT 40;

SELECT * FROM public.books_graph_authors LIMIT 25;

-- Only the first 300 books are projected into the graph, so pick a title that
-- is actually present. Scalar output, will not render.
SELECT * FROM ag_catalog.cypher('books_graph', $cypher$
    MATCH (b:Book)-[:SIMILAR_TO]->() RETURN b.title LIMIT 10
$cypher$) AS ("title" ag_catalog.agtype);

SELECT * FROM public.books_graph_neighbourhood('PASTE A TITLE FROM ABOVE');


-- Troubleshooting -------------------------------------------------------------
-- Nodes showing internal IDs instead of titles? The graph predates disp_label.
-- Backfill it without rebuilding:
--
-- SELECT * FROM cypher('books_graph', $$ MATCH (b:Book)     SET b.disp_label = b.title $$) AS ("r" agtype);
-- SELECT * FROM cypher('books_graph', $$ MATCH (n:Author)   SET n.disp_label = n.name  $$) AS ("r" agtype);
-- SELECT * FROM cypher('books_graph', $$ MATCH (n:Category) SET n.disp_label = n.name  $$) AS ("r" agtype);
-- SELECT * FROM cypher('books_graph', $$ MATCH (n:Decade)   SET n.disp_label = n.name  $$) AS ("r" agtype);
--
-- Changing a view's column list? CREATE OR REPLACE cannot do that -- drop first:
--
-- DROP VIEW IF EXISTS public.books_graph_similar, public.books_graph_authors;
-- DROP FUNCTION IF EXISTS public.books_graph_neighbourhood(text);
