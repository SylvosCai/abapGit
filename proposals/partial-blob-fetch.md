# Proposal: Partial Blob Fetch via Git Filter Protocol

**Date:** 2026-03-10
**Author:** CAIS (via abapgit-agent)
**Status:** Draft

---

## Problem

Every `abapgit-agent pull --files <one_file>` downloads the **entire repository pack**
from the git server, regardless of how many objects are actually needed.

Each invocation creates a new repo instance — `mt_remote` starts empty and
`mv_request_remote_refresh` is `true` — so `fetch_remote` runs unconditionally
on every pull. For a 1000-object enterprise package the pack can be tens to
hundreds of megabytes, and the ABAP-side pack decode adds significant CPU time
on top of the network transfer.

The filter work (filtered-deserialize-checks proposal) already eliminates the
post-fetch overhead — only the requested objects are compared and deserialized.
But the fetch itself remains a full repository download.

---

## Root Cause

The bottleneck is in the git upload-pack request in
`zcl_abapgit_git_transport=>upload_pack`:

```abap
lv_capa = 'side-band-64k no-progress multi_ack'.
lv_line = 'want' && ` ` && <lv_hash> && ` ` && lv_capa && newline.
" ...
lv_buffer = lv_buffer && '0000' && '0009done' && newline.
```

The client sends a `want <commit-sha>` with no filter specification. The server
responds with a pack file containing **every object** in the commit tree —
all commits, all trees, and all blobs (file content). There is no mechanism in
the current request to limit what the server sends.

---

## Git Partial Clone Protocol

Git 2.17 (April 2018) introduced the **`filter` capability** in the upload-pack
protocol (documented in `gitprotocol-v2` and `pack-protocol`).

When the server advertises `filter` in the `info/refs` capabilities, the client
can add a `filter` line to its upload-pack request. The most useful filter for
abapGit:

**`filter blob:none`** — server sends all commit and tree objects (the full
directory structure, filenames, and blob SHAs) but **zero blob content** (no
actual file data). The resulting pack is a fraction of the full pack size.

The client then makes a **second targeted request** for only the blob SHAs it
actually needs, passing them as individual `want` lines:

```
want <blob-sha-of-zcl_foo.clas.abap>
want <blob-sha-of-zcl_foo.clas.xml>
0000
done
```

The server returns only those specific blobs.

---

## Proposed Two-Phase Fetch

```
Current (one round-trip):
  upload_pack(want <commit>)  →  server sends ALL objects (commit + trees + blobs)
  walk()                      →  extract all N files into mt_remote

Proposed (two round-trips when filter is active):
  Phase 1: upload_pack(want <commit>, filter blob:none)
           →  server sends commit + trees only (lightweight pack)
           walk_for_blobs()  →  collect (path, filename, blob_sha) for matching files only

  Phase 2: upload_pack(want <blob_sha_1>, want <blob_sha_2>, ...)
           →  server sends only the requested blobs
           assemble files  →  pair blob data with (path, filename) from Phase 1
```

Phase 1 pack: kilobytes (tree structure only).
Phase 2 pack: only the files for the requested objects (1–few files).
Combined: orders of magnitude smaller than the full pack for large repositories.

---

## Fallback Strategy

Not all servers support `filter`. The server advertises supported capabilities
in the `info/refs` response, which `branch_list` already fetches and parses
into a `zcl_abapgit_git_branch_list` object.

```
If server advertises 'filter' capability AND ii_obj_filter is supplied
  → use two-phase fetch (this proposal)
Else
  → fall back to current single-phase full fetch (no behavior change)
```

This makes the optimization **fully transparent and backward-compatible**.
Existing callers that pass no filter always use the current path.

### Server compatibility

| Provider | Supports `filter`? | Notes |
|---|---|---|
| GitHub | Yes | Since ~2020 |
| GitLab | Yes | Since ~2021 |
| Gitea / Forgejo | Yes | Since ~2022 |
| Azure DevOps | Yes | |
| Self-hosted Git | Requires Git ≥ 2.17 | `uploadpack.allowFilter = true` |

---

## Files to Change

| File | Change |
|------|--------|
| `src/git/zcl_abapgit_git_transport.clas.abap` | (1) Expose server capabilities from `branch_list`; (2) Add optional `iv_filter` to `upload_pack`; (3) Thread filter into `upload_pack_by_branch` / `upload_pack_by_commit` when server supports it |
| `src/git/zcl_abapgit_git_porcelain.clas.abap` | (4) Add `walk_for_blobs` to collect blob SHAs without requiring blob data; (5) Modify `pull` to do two-phase fetch when filter is active |
| `src/repo/zcl_abapgit_repo_online.clas.abap` | (6) Pass `ii_obj_filter` from `fetch_remote` into `pull_by_branch` / `pull_by_commit` |

---

## Detailed Changes

### Change 1 — `zcl_abapgit_git_transport`: expose capabilities from `branch_list`

`branch_list` already fetches the `info/refs` response. The first ref line
contains the server capability list (everything after the NUL byte on the first
pktline). Expose it as an additional export:

```abap
" Before:
CLASS-METHODS branch_list
  IMPORTING iv_url     TYPE string
            iv_service TYPE string
  EXPORTING eo_client       TYPE REF TO zcl_abapgit_http_client
            ei_branch_list  TYPE REF TO zif_abapgit_git_branch_list.

" After:
CLASS-METHODS branch_list
  IMPORTING iv_url     TYPE string
            iv_service TYPE string
  EXPORTING eo_client        TYPE REF TO zcl_abapgit_http_client
            ei_branch_list   TYPE REF TO zif_abapgit_git_branch_list
            ev_capabilities  TYPE string.        " ← new, raw capability string
```

---

### Change 2 — `zcl_abapgit_git_transport=>upload_pack`: add optional `iv_filter`

The `deepen` feature already shows the exact pattern:

```abap
" Before:
lv_capa = 'side-band-64k no-progress multi_ack'.

" After:
lv_capa = 'side-band-64k no-progress multi_ack'.
IF iv_filter IS NOT INITIAL.
  lv_capa = lv_capa && ' filter'.
ENDIF.
```

```abap
" After the want lines, before 0000:
IF iv_filter IS NOT INITIAL.
  lv_buffer = lv_buffer && zcl_abapgit_git_utils=>pkt_string(
    |filter { iv_filter }| && cl_abap_char_utilities=>newline ).
ENDIF.
```

---

### Change 3 — `upload_pack_by_branch` / `upload_pack_by_commit`: detect and thread filter

```abap
" In upload_pack_by_branch:
find_branch( ... IMPORTING eo_client = lo_client ev_branch = ev_branch
                           ev_capabilities = lv_capabilities ).   " ← new

IF iv_filter IS NOT INITIAL AND lv_capabilities CS 'filter'.
  lv_filter = iv_filter.   " server supports it, use it
ENDIF.

et_objects = upload_pack( io_client       = lo_client
                          iv_url          = iv_url
                          iv_deepen_level = iv_deepen_level
                          it_hashes       = lt_hashes
                          iv_filter       = lv_filter ).   " ← new
```

---

### Change 4 — `zcl_abapgit_git_porcelain`: add `walk_for_blobs`

A new private method that walks the tree structure (available after Phase 1)
and returns the blob SHAs only for files whose names match the filter:

```abap
" New method:
CLASS-METHODS walk_for_blobs
  IMPORTING
    !it_objects    TYPE zif_abapgit_definitions=>ty_objects_tt
    !iv_sha1       TYPE zif_abapgit_git_definitions=>ty_sha1
    !iv_path       TYPE string
    !ii_obj_filter TYPE REF TO zif_abapgit_object_filter OPTIONAL
  CHANGING
    !ct_stubs      TYPE zif_abapgit_git_definitions=>ty_files_tt   " path+filename+sha1, no data
  RAISING
    zcx_abapgit_exception.
```

This is identical to `walk` but:
- Does NOT raise an exception when a blob is missing from `it_objects` (expected
  in Phase 1 — blobs were filtered out by the server)
- Stores `path`, `filename`, and `sha1` in `ct_stubs` with empty `data`
- When `ii_obj_filter` is supplied, only appends stubs for files that match
  (using the same filename-to-object mapping already in `zcl_abapgit_repo_filter`)
- When `ii_obj_filter` is initial, appends stubs for all files (for a complete
  tree listing without downloading blobs)

---

### Change 5 — `zcl_abapgit_git_porcelain=>pull`: two-phase fetch

```abap
" Before:
METHOD pull.
  ls_commit = zcl_abapgit_git_pack=>decode_commit( ... ).
  walk( EXPORTING it_objects = it_objects
                  iv_sha1    = ls_commit-tree
                  iv_path    = '/'
        CHANGING  ct_files   = rt_files ).
ENDMETHOD.

" After:
METHOD pull.
  ls_commit = zcl_abapgit_git_pack=>decode_commit( ... ).

  IF ii_obj_filter IS INITIAL OR iv_url IS INITIAL.
    " No filter or no URL (offline) → existing full walk
    walk( EXPORTING it_objects = it_objects
                    iv_sha1    = ls_commit-tree
                    iv_path    = '/'
          CHANGING  ct_files   = rt_files ).
    RETURN.
  ENDIF.

  " Phase 1 result: tree structure only, no blob data
  " Collect stub entries (path + filename + blob sha1) for requested objects
  walk_for_blobs( EXPORTING it_objects    = it_objects
                             iv_sha1       = ls_commit-tree
                             iv_path       = '/'
                             ii_obj_filter = ii_obj_filter
                 CHANGING   ct_stubs      = lt_stubs ).

  " Phase 2: fetch only the needed blobs by SHA
  LOOP AT lt_stubs ASSIGNING <ls_stub>.
    APPEND <ls_stub>-sha1 TO lt_blob_hashes.
  ENDLOOP.

  lt_blob_objects = upload_pack_blobs(
    iv_url    = iv_url
    it_hashes = lt_blob_hashes ).

  " Assemble final file list: stubs + blob data
  LOOP AT lt_stubs ASSIGNING <ls_stub>.
    READ TABLE lt_blob_objects INTO ls_obj WITH KEY sha1 = <ls_stub>-sha1.
    IF sy-subrc = 0.
      <ls_stub>-data = ls_obj-data.
    ENDIF.
  ENDLOOP.

  rt_files = lt_stubs.
ENDMETHOD.
```

A new private method `upload_pack_blobs` wraps the second `upload_pack` call,
reusing the existing HTTP client and pack decode infrastructure.

---

### Change 6 — `zcl_abapgit_repo_online=>fetch_remote`: pass filter

```abap
" Before:
IF get_selected_commit( ) IS INITIAL.
  ls_pull = zcl_abapgit_git_porcelain=>pull_by_branch(
    iv_url         = get_url( )
    iv_branch_name = get_selected_branch( ) ).

" After:
IF get_selected_commit( ) IS INITIAL.
  ls_pull = zcl_abapgit_git_porcelain=>pull_by_branch(
    iv_url         = get_url( )
    iv_branch_name = get_selected_branch( )
    ii_obj_filter  = ii_obj_filter ).     " ← new, threaded from caller
```

`fetch_remote` itself needs a new optional `ii_obj_filter` parameter.
`get_files_remote` in `zcl_abapgit_repo_online` already receives
`ii_obj_filter` and calls `fetch_remote` — it would pass the filter through.

---

## Special Files: `.abapgit` and `.apack-manifest.yml`

`find_remote_dot_abapgit` reads `mt_remote` directly and requires `.abapgit`
to be present. With a filtered `mt_remote` this would silently miss the file.

**Solution**: `walk_for_blobs` always includes root-level dot-files regardless
of the object filter:

```abap
" In walk_for_blobs, when processing root path ('/'):
IF iv_path = '/' AND <ls_node>-name+0(1) = '.'.
  " Always include .abapgit, .apack-manifest.yml, etc.
  APPEND stub TO ct_stubs.
  CONTINUE.
ENDIF.
```

This ensures repository configuration is always available in `mt_remote`
regardless of which objects are filtered.

---

## Performance Impact

For a 1000-object repository (typical enterprise package):

| Phase | Before | After (with filter) |
|-------|--------|---------------------|
| HTTP download | Full pack (~50–200 MB) | Phase 1: tree pack (~100 KB) + Phase 2: 1–few blobs (~50 KB) |
| Pack decode (`zcl_abapgit_git_pack=>decode`) | All N objects | Phase 1: tree objects only; Phase 2: 1–few blobs |
| `mt_remote` size | All N files | Only requested files + dot-files |
| HTTP round-trips | 1 | 2 |

The extra round-trip cost is negligible compared to the savings on pack size
for large repositories.

No change for full pulls (no filter passed) or offline repositories.

---

## Backward Compatibility

- All new parameters are `OPTIONAL` — existing callers unchanged
- Filter only activates when **both** conditions are true:
  - Caller passes `ii_obj_filter`
  - Server advertises `filter` capability
- If either condition is false → current full-fetch behavior

---

## Related Code Paths

| Class | Method | Notes |
|-------|--------|-------|
| `zcl_abapgit_git_transport` | `upload_pack` | Add `iv_filter`, add `filter` pktline |
| `zcl_abapgit_git_transport` | `branch_list` | Expose `ev_capabilities` |
| `zcl_abapgit_git_transport` | `upload_pack_by_branch` | Detect `filter` cap, thread through |
| `zcl_abapgit_git_transport` | `upload_pack_by_commit` | Same |
| `zcl_abapgit_git_porcelain` | `pull` | Two-phase logic |
| `zcl_abapgit_git_porcelain` | `walk_for_blobs` | New — tree walk without blob data |
| `zcl_abapgit_git_porcelain` | `upload_pack_blobs` | New — second round-trip for blobs |
| `zcl_abapgit_git_porcelain` | `pull_by_branch` | Thread `ii_obj_filter` and `iv_url` |
| `zcl_abapgit_git_porcelain` | `pull_by_commit` | Same |
| `zcl_abapgit_repo_online` | `fetch_remote` | Accept and pass `ii_obj_filter` |
| `zcl_abapgit_repo_online` | `get_files_remote` | Pass filter to `fetch_remote` |
