CLASS zcl_abapgit_gitv2_porcelain DEFINITION
  PUBLIC
  CREATE PRIVATE
  GLOBAL FRIENDS zcl_abapgit_git_factory .

  PUBLIC SECTION.

    INTERFACES zif_abapgit_gitv2_porcelain.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS:
      BEGIN OF c_service,
        receive TYPE string VALUE 'receive',                "#EC NOTEXT
        upload  TYPE string VALUE 'upload',                 "#EC NOTEXT
      END OF c_service .

    CONSTANTS c_flush_pkt TYPE c LENGTH 4 VALUE '0000'.
    CONSTANTS c_delim_pkt TYPE c LENGTH 4 VALUE '0001'.

    CLASS-METHODS get_request_uri
      IMPORTING
        iv_url        TYPE string
        iv_service    TYPE string
      RETURNING
        VALUE(rv_uri) TYPE string
      RAISING
        zcx_abapgit_exception.

    CLASS-METHODS send_command
      IMPORTING
        iv_url             TYPE string
        iv_service         TYPE string
        iv_command         TYPE string
        it_arguments       TYPE string_table OPTIONAL
      RETURNING
        VALUE(rv_response) TYPE xstring
      RAISING
        zcx_abapgit_exception.

    CLASS-METHODS decode_pack
      IMPORTING
        iv_xstring        TYPE xstring
      RETURNING
        VALUE(rt_objects) TYPE zif_abapgit_definitions=>ty_objects_tt
      RAISING
        zcx_abapgit_exception.

    CLASS-METHODS walk_tree_for_paths
      IMPORTING
        !iv_url          TYPE string
        !iv_base         TYPE string
        !iv_tree_sha1    TYPE zif_abapgit_git_definitions=>ty_sha1
        !it_wanted_paths TYPE string_table OPTIONAL
      CHANGING
        !ct_expanded     TYPE zif_abapgit_git_definitions=>ty_expanded_tt
      RAISING
        zcx_abapgit_exception.

    CLASS-METHODS path_needed
      IMPORTING
        !iv_path              TYPE string
        !it_wanted_paths      TYPE string_table OPTIONAL
      RETURNING
        VALUE(rv_needed)      TYPE abap_bool.

    CLASS-METHODS fetch_commit_only
      IMPORTING
        !iv_url      TYPE string
        !iv_sha1     TYPE zif_abapgit_git_definitions=>ty_sha1
      RETURNING
        VALUE(rv_data) TYPE xstring
      RAISING
        zcx_abapgit_exception.

    CLASS-METHODS fetch_tree_nodes
      IMPORTING
        !iv_url        TYPE string
        !iv_tree_sha1  TYPE zif_abapgit_git_definitions=>ty_sha1
      RETURNING
        VALUE(rt_nodes) TYPE zcl_abapgit_git_pack=>ty_nodes_tt
      RAISING
        zcx_abapgit_exception.

ENDCLASS.



CLASS zcl_abapgit_gitv2_porcelain IMPLEMENTATION.


  METHOD decode_pack.

    DATA lv_xstring TYPE xstring.
    DATA lv_contents  TYPE xstring.
    DATA lv_pack      TYPE xstring.
    DATA lv_pktlen    TYPE i.
    DATA lv_hex4      TYPE xstring.

    lv_xstring = iv_xstring.

* The data transfer of the packfile is always multiplexed, using the same semantics of the
* side-band-64k capability from protocol version 1
    WHILE xstrlen( lv_xstring ) > 0.
      lv_hex4 = lv_xstring(4).
      lv_pktlen = zcl_abapgit_git_utils=>length_utf8_hex( lv_hex4 ).
      IF lv_pktlen = 0.
        EXIT.
      ELSEIF lv_pktlen = 1.
* its a delimiter package
        lv_xstring = lv_xstring+4.
        CONTINUE.
      ENDIF.
      lv_contents = lv_xstring(lv_pktlen).
      IF lv_contents+4(1) = '01'.
        CONCATENATE lv_pack lv_contents+5 INTO lv_pack IN BYTE MODE.
      ENDIF.
      lv_xstring = lv_xstring+lv_pktlen.
    ENDWHILE.

    rt_objects = zcl_abapgit_git_pack=>decode( lv_pack ).

  ENDMETHOD.


  METHOD get_request_uri.
    rv_uri = zcl_abapgit_url=>path_name( iv_url ) && |/info/refs?service=git-{ iv_service }-pack|.
  ENDMETHOD.


  METHOD send_command.

    CONSTANTS lc_content_regex TYPE string VALUE '^[0-9a-f]{4}#'.

    DATA lo_client   TYPE REF TO zcl_abapgit_http_client.
    DATA lv_cmd_pkt  TYPE string.
    DATA lt_headers  TYPE zcl_abapgit_http=>ty_headers.
    DATA ls_header   LIKE LINE OF lt_headers.
    DATA lv_argument TYPE string.


    ls_header-key   = 'Git-Protocol'.
    ls_header-value = 'version=2'.
    APPEND ls_header TO lt_headers.
    ls_header-key   = '~request_uri'.
    ls_header-value = get_request_uri( iv_url     = iv_url
                                       iv_service = iv_service ).
    APPEND ls_header TO lt_headers.

    lo_client = zcl_abapgit_http=>create_by_url(
      iv_url     = iv_url
      it_headers = lt_headers ).

    lo_client->check_smart_response(
      iv_expected_content_type = |application/x-git-{ iv_service }-pack-advertisement|
      iv_content_regex         = lc_content_regex ).

    lv_cmd_pkt = zcl_abapgit_git_utils=>pkt_string( |command={ iv_command }\n| )
      && zcl_abapgit_git_utils=>pkt_string( |agent={ zcl_abapgit_http=>get_agent( ) }\n| ).
    IF lines( it_arguments ) > 0.
      lv_cmd_pkt = lv_cmd_pkt && c_delim_pkt.
      LOOP AT it_arguments INTO lv_argument.
        lv_cmd_pkt = lv_cmd_pkt && zcl_abapgit_git_utils=>pkt_string( lv_argument ).
      ENDLOOP.
    ENDIF.
    lv_cmd_pkt = lv_cmd_pkt && c_flush_pkt.

    lo_client->set_header(
      iv_key   = '~request_uri'
      iv_value = zcl_abapgit_url=>path_name( iv_url ) && |/git-{ iv_service }-pack| ).

    lo_client->set_header(
      iv_key   = '~request_method'
      iv_value = 'POST' ).

    lo_client->set_header(
      iv_key   = 'Content-Type'
      iv_value = |application/x-git-{ iv_service }-pack-request| ).

    lo_client->set_header(
      iv_key   = 'Accept'
      iv_value = |application/x-git-{ iv_service }-pack-result| ).

    rv_response = lo_client->send_receive_close( zcl_abapgit_convert=>string_to_xstring_utf8( lv_cmd_pkt ) ).

  ENDMETHOD.


  METHOD zif_abapgit_gitv2_porcelain~commits_last_year.
* including trees
    DATA lv_xstring   TYPE xstring.
    DATA lt_arguments TYPE string_table.
    DATA lv_argument  TYPE string.
    DATA lv_sha1      LIKE LINE OF it_sha1.


    ASSERT lines( it_sha1 ) > 0.

    lv_argument = |deepen-since { zcl_abapgit_git_time=>get_one_year_ago( ) }|.
    APPEND lv_argument TO lt_arguments.
    LOOP AT it_sha1 INTO lv_sha1.
      lv_argument = |want { lv_sha1 }|.
      APPEND lv_argument TO lt_arguments.
    ENDLOOP.
* 'filter object:type=commit' doesn't work on github
    APPEND 'filter blob:none' TO lt_arguments.
    APPEND 'no-progress' TO lt_arguments.
    APPEND 'done' TO lt_arguments.

    lv_xstring = send_command(
      iv_url       = iv_url
      iv_service   = c_service-upload
      iv_command   = |fetch|
      it_arguments = lt_arguments ).

    rt_objects = decode_pack( lv_xstring ).

  ENDMETHOD.


  METHOD zif_abapgit_gitv2_porcelain~fetch_blob.

    DATA lv_xstring   TYPE xstring.
    DATA lt_arguments TYPE string_table.
    DATA lv_argument  TYPE string.
    DATA lt_objects   TYPE zif_abapgit_definitions=>ty_objects_tt.
    DATA ls_object    LIKE LINE OF lt_objects.


    ASSERT iv_sha1 IS NOT INITIAL.

    lv_argument = |want { iv_sha1 }|.
    APPEND lv_argument TO lt_arguments.
    APPEND 'no-progress' TO lt_arguments.
    APPEND 'done' TO lt_arguments.

    lv_xstring = send_command(
      iv_url       = iv_url
      iv_service   = c_service-upload
      iv_command   = |fetch|
      it_arguments = lt_arguments ).

    lt_objects = decode_pack( lv_xstring ).
    IF lines( lt_objects ) <> 1.
      zcx_abapgit_exception=>raise( |Blob { iv_sha1 } not found in response.| ).
    ENDIF.

    READ TABLE lt_objects INTO ls_object INDEX 1.
    ASSERT sy-subrc = 0.
    rv_blob = ls_object-data.

  ENDMETHOD.


  METHOD zif_abapgit_gitv2_porcelain~fetch_blobs.

    DATA lv_xstring   TYPE xstring.
    DATA lt_arguments TYPE string_table.
    DATA lv_argument  TYPE string.
    DATA lv_sha1      LIKE LINE OF it_sha1.


    ASSERT lines( it_sha1 ) > 0.

    LOOP AT it_sha1 INTO lv_sha1.
      lv_argument = |want { lv_sha1 }|.
      APPEND lv_argument TO lt_arguments.
    ENDLOOP.
    APPEND 'no-progress' TO lt_arguments.
    APPEND 'done' TO lt_arguments.

    lv_xstring = send_command(
      iv_url       = iv_url
      iv_service   = c_service-upload
      iv_command   = |fetch|
      it_arguments = lt_arguments ).

    rt_objects = decode_pack( lv_xstring ).

  ENDMETHOD.


  METHOD zif_abapgit_gitv2_porcelain~list_branches.
    DATA lv_xstring   TYPE xstring.
    DATA lt_arguments TYPE string_table.
    DATA lv_argument  TYPE string.
    DATA lv_data      TYPE string.

    IF iv_prefix IS NOT INITIAL.
      lv_argument = |ref-prefix { iv_prefix }|.
      APPEND lv_argument TO lt_arguments.
    ENDIF.

    lv_xstring = send_command(
      iv_url       = iv_url
      iv_service   = c_service-upload
      iv_command   = |ls-refs|
      it_arguments = lt_arguments ).

    " add dummy packet so the v1 branch parsing can be reused
    lv_data = |0004\n{ zcl_abapgit_convert=>xstring_to_string_utf8_raw( lv_xstring ) }|.

    CREATE OBJECT ro_list TYPE zcl_abapgit_git_branch_list
      EXPORTING
        iv_data = lv_data.

  ENDMETHOD.


  METHOD zif_abapgit_gitv2_porcelain~list_trees_for_paths.

    " Targeted tree walk: walks the commit tree one level at a time,
    " fetching only the tree objects along the path to the wanted files.
    " Each tree is fetched with filter blob:none to avoid blob data.
    " For leaf directories this is a single small object; intermediate
    " directories also fetch their subtrees, but those are tree-only packs
    " which are smaller and faster to decode than full blob packs.

    DATA: lv_commit_data TYPE xstring,
          ls_commit      TYPE zcl_abapgit_git_pack=>ty_commit,
          lt_root_nodes  TYPE zcl_abapgit_git_pack=>ty_nodes_tt,
          lv_tree_data   TYPE xstring,
          ls_exp         LIKE LINE OF rt_expanded,
          lv_sub_path    TYPE string.

    FIELD-SYMBOLS: <ls_node> LIKE LINE OF lt_root_nodes.

    " 1. Fetch just the commit object (filter tree:0 = no trees, no blobs)
    lv_commit_data = fetch_commit_only(
      iv_url  = iv_url
      iv_sha1 = iv_sha1 ).
    ls_commit = zcl_abapgit_git_pack=>decode_commit( lv_commit_data ).

    " 2. Fetch root tree with filter blob:none (trees but no blobs)
    lt_root_nodes = fetch_tree_nodes(
      iv_url       = iv_url
      iv_tree_sha1 = ls_commit-tree ).

    " 3. Walk root tree: always include root-level files; recurse into dirs
    "    that are a prefix of a wanted path (or all dirs if no filter)
    LOOP AT lt_root_nodes ASSIGNING <ls_node>.
      CASE <ls_node>-chmod.
        WHEN zif_abapgit_git_definitions=>c_chmod-dir.
          lv_sub_path = '/' && <ls_node>-name && '/'.
          IF path_needed( iv_path          = lv_sub_path
                          it_wanted_paths  = it_wanted_paths ).
            walk_tree_for_paths(
              EXPORTING
                iv_url          = iv_url
                iv_base         = lv_sub_path
                iv_tree_sha1    = <ls_node>-sha1
                it_wanted_paths = it_wanted_paths
              CHANGING
                ct_expanded     = rt_expanded ).
          ENDIF.
        WHEN OTHERS.
          " Always include root-level files (.abapgit.xml etc.)
          CLEAR ls_exp.
          ls_exp-path  = '/'.
          ls_exp-name  = <ls_node>-name.
          ls_exp-sha1  = <ls_node>-sha1.
          ls_exp-chmod = <ls_node>-chmod.
          APPEND ls_exp TO rt_expanded.
      ENDCASE.
    ENDLOOP.

  ENDMETHOD.


  METHOD zif_abapgit_gitv2_porcelain~list_no_blobs.

    DATA lt_sha1    TYPE zif_abapgit_git_definitions=>ty_sha1_tt.
    DATA lt_objects TYPE zif_abapgit_definitions=>ty_objects_tt.

    ASSERT iv_sha1 IS NOT INITIAL.
    APPEND iv_sha1 TO lt_sha1.

    lt_objects = zif_abapgit_gitv2_porcelain~list_no_blobs_multi(
      iv_url  = iv_url
      it_sha1 = lt_sha1 ).

    rt_expanded = zcl_abapgit_git_porcelain=>full_tree(
      it_objects = lt_objects
      iv_parent  = iv_sha1 ).

  ENDMETHOD.


  METHOD zif_abapgit_gitv2_porcelain~list_no_blobs_multi.

    DATA lv_xstring   TYPE xstring.
    DATA lt_arguments TYPE string_table.
    DATA lv_argument  TYPE string.
    DATA lv_sha1      LIKE LINE OF it_sha1.


    ASSERT lines( it_sha1 ) > 0.

    APPEND 'deepen 1' TO lt_arguments.
    LOOP AT it_sha1 INTO lv_sha1.
      lv_argument = |want { lv_sha1 }|.
      APPEND lv_argument TO lt_arguments.
    ENDLOOP.
    APPEND 'filter blob:none' TO lt_arguments.
    APPEND 'no-progress' TO lt_arguments.
    APPEND 'done' TO lt_arguments.

    lv_xstring = send_command(
      iv_url       = iv_url
      iv_service   = c_service-upload
      iv_command   = |fetch|
      it_arguments = lt_arguments ).

    rt_objects = decode_pack( lv_xstring ).

  ENDMETHOD.


  METHOD path_needed.

    DATA lv_wanted TYPE string.

    " No filter → all paths are needed
    IF it_wanted_paths IS INITIAL.
      rv_needed = abap_true.
      RETURN.
    ENDIF.

    " A directory iv_path is needed if:
    " (a) it is an ancestor of a wanted path  (iv_path is prefix of wanted)
    " (b) it is the wanted path itself or a descendant (wanted is prefix of iv_path)
    " Examples with iv_path = '/src/' and wanted = '/src/pkg/sub/':
    "   (a) '/src/' CP '/src/*'  → true  (iv_path is ancestor of wanted)
    " Examples with iv_path = '/src/pkg/sub/' and wanted = '/src/':
    "   (b) '/src/pkg/sub/' CP '/src/*' → true  (wanted is ancestor of iv_path)
    LOOP AT it_wanted_paths INTO lv_wanted.
      IF lv_wanted CP iv_path && '*'   " iv_path is prefix of wanted
          OR iv_path CP lv_wanted && '*'.  " wanted is prefix of iv_path
        rv_needed = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD walk_tree_for_paths.

    DATA: lt_nodes    TYPE zcl_abapgit_git_pack=>ty_nodes_tt,
          ls_exp      LIKE LINE OF ct_expanded,
          lv_sub_path TYPE string.

    FIELD-SYMBOLS: <ls_node> LIKE LINE OF lt_nodes.

    lt_nodes = fetch_tree_nodes(
      iv_url       = iv_url
      iv_tree_sha1 = iv_tree_sha1 ).

    LOOP AT lt_nodes ASSIGNING <ls_node>.
      CASE <ls_node>-chmod.
        WHEN zif_abapgit_git_definitions=>c_chmod-dir.
          lv_sub_path = iv_base && <ls_node>-name && '/'.
          IF path_needed( iv_path          = lv_sub_path
                          it_wanted_paths  = it_wanted_paths ).
            walk_tree_for_paths(
              EXPORTING
                iv_url          = iv_url
                iv_base         = lv_sub_path
                iv_tree_sha1    = <ls_node>-sha1
                it_wanted_paths = it_wanted_paths
              CHANGING
                ct_expanded     = ct_expanded ).
          ENDIF.
        WHEN OTHERS.
          CLEAR ls_exp.
          ls_exp-path  = iv_base.
          ls_exp-name  = <ls_node>-name.
          ls_exp-sha1  = <ls_node>-sha1.
          ls_exp-chmod = <ls_node>-chmod.
          APPEND ls_exp TO ct_expanded.
      ENDCASE.
    ENDLOOP.

  ENDMETHOD.


  METHOD fetch_commit_only.

    " Fetch just the commit object without trees or blobs.
    " Uses filter tree:0 so the server sends only the commit itself.

    DATA lv_xstring   TYPE xstring.
    DATA lt_arguments TYPE string_table.
    DATA lt_objects   TYPE zif_abapgit_definitions=>ty_objects_tt.
    DATA ls_object    LIKE LINE OF lt_objects.

    APPEND |want { iv_sha1 }| TO lt_arguments.
    APPEND 'filter tree:0'    TO lt_arguments.
    APPEND 'no-progress'      TO lt_arguments.
    APPEND 'done'             TO lt_arguments.

    lv_xstring = send_command(
      iv_url       = iv_url
      iv_service   = c_service-upload
      iv_command   = |fetch|
      it_arguments = lt_arguments ).

    lt_objects = decode_pack( lv_xstring ).
    READ TABLE lt_objects INTO ls_object
      WITH KEY type COMPONENTS type = zif_abapgit_git_definitions=>c_type-commit.
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( |Commit { iv_sha1 } not found in response| ).
    ENDIF.
    rv_data = ls_object-data.

  ENDMETHOD.


  METHOD fetch_tree_nodes.

    " Fetch a tree object by SHA1 with filter blob:none so only tree objects
    " (not blob content) are transferred.  For leaf directories the pack
    " contains just this one tree; for intermediate directories it contains
    " this tree plus its subtrees.  Decode and return the direct node list.

    DATA lv_xstring   TYPE xstring.
    DATA lt_arguments TYPE string_table.
    DATA lt_objects   TYPE zif_abapgit_definitions=>ty_objects_tt.
    DATA ls_object    LIKE LINE OF lt_objects.

    APPEND |want { iv_tree_sha1 }| TO lt_arguments.
    APPEND 'filter blob:none'      TO lt_arguments.
    APPEND 'no-progress'           TO lt_arguments.
    APPEND 'done'                  TO lt_arguments.

    lv_xstring = send_command(
      iv_url       = iv_url
      iv_service   = c_service-upload
      iv_command   = |fetch|
      it_arguments = lt_arguments ).

    lt_objects = decode_pack( lv_xstring ).
    READ TABLE lt_objects INTO ls_object
      WITH KEY type COMPONENTS
        type = zif_abapgit_git_definitions=>c_type-tree
        sha1 = iv_tree_sha1.
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( |Tree { iv_tree_sha1 } not found in response| ).
    ENDIF.
    rt_nodes = zcl_abapgit_git_pack=>decode_tree( ls_object-data ).

  ENDMETHOD.
ENDCLASS.
