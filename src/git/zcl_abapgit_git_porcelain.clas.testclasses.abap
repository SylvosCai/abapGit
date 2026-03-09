CLASS ltcl_git_porcelain DEFINITION DEFERRED.
CLASS zcl_abapgit_git_porcelain DEFINITION LOCAL FRIENDS ltcl_git_porcelain.

CLASS ltcl_git_porcelain DEFINITION FOR TESTING RISK LEVEL HARMLESS DURATION SHORT FINAL.

  PRIVATE SECTION.
    METHODS:
      setup,
      append
        IMPORTING iv_path TYPE string
                  iv_name TYPE string,
      single_file FOR TESTING
        RAISING zcx_abapgit_exception,
      two_files_same_path FOR TESTING
        RAISING zcx_abapgit_exception,
      root_empty FOR TESTING
        RAISING zcx_abapgit_exception,
      namespaces FOR TESTING
        RAISING zcx_abapgit_exception,
      more_sub FOR TESTING
        RAISING zcx_abapgit_exception,
      sub FOR TESTING
        RAISING zcx_abapgit_exception,
      walk_for_blobs_single FOR TESTING
        RAISING zcx_abapgit_exception,
      walk_for_blobs_subdir FOR TESTING
        RAISING zcx_abapgit_exception,
      pull_full_walk_no_filter FOR TESTING
        RAISING zcx_abapgit_exception,
      filter_stubs_keeps_match FOR TESTING
        RAISING zcx_abapgit_exception,
      filter_stubs_removes_no_match FOR TESTING
        RAISING zcx_abapgit_exception.

    METHODS build_tree_object
      IMPORTING
        it_nodes        TYPE zcl_abapgit_git_pack=>ty_nodes_tt
      CHANGING
        ct_objects      TYPE zif_abapgit_definitions=>ty_objects_tt
      RETURNING
        VALUE(rv_sha1)  TYPE zif_abapgit_git_definitions=>ty_sha1
      RAISING
        zcx_abapgit_exception.

    DATA: mt_expanded TYPE zif_abapgit_git_definitions=>ty_expanded_tt,
          mt_trees    TYPE zcl_abapgit_git_porcelain=>ty_trees_tt.

ENDCLASS.

CLASS ltcl_git_porcelain IMPLEMENTATION.

  METHOD setup.
    CLEAR mt_expanded.
    CLEAR mt_trees.
  ENDMETHOD.

  METHOD append.

    FIELD-SYMBOLS: <ls_expanded> LIKE LINE OF mt_expanded.


    APPEND INITIAL LINE TO mt_expanded ASSIGNING <ls_expanded>.
    <ls_expanded>-path  = iv_path.
    <ls_expanded>-name  = iv_name.
    <ls_expanded>-sha1  = 'a'.
    <ls_expanded>-chmod = zif_abapgit_git_definitions=>c_chmod-file.

  ENDMETHOD.

  METHOD build_tree_object.

    DATA ls_obj  LIKE LINE OF ct_objects.
    DATA lv_data TYPE xstring.

    lv_data = zcl_abapgit_git_pack=>encode_tree( it_nodes ).

    ls_obj-data = lv_data.
    ls_obj-type = zif_abapgit_git_definitions=>c_type-tree.
    ls_obj-sha1 = zcl_abapgit_hash=>sha1_tree( lv_data ).

    APPEND ls_obj TO ct_objects.
    rv_sha1 = ls_obj-sha1.

  ENDMETHOD.

  METHOD single_file.

    append( iv_path = '/'
            iv_name = 'foobar.txt' ).

    mt_trees = zcl_abapgit_git_porcelain=>build_trees( mt_expanded ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( mt_trees )
      exp = 1 ).

  ENDMETHOD.

  METHOD two_files_same_path.

    append( iv_path = '/'
            iv_name = 'foo.txt' ).

    append( iv_path = '/'
            iv_name = 'bar.txt' ).

    mt_trees = zcl_abapgit_git_porcelain=>build_trees( mt_expanded ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( mt_trees )
      exp = 1 ).

  ENDMETHOD.

  METHOD sub.

    append( iv_path = '/'
            iv_name = 'foo.txt' ).

    append( iv_path = '/sub/'
            iv_name = 'bar.txt' ).

    mt_trees = zcl_abapgit_git_porcelain=>build_trees( mt_expanded ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( mt_trees )
      exp = 2 ).

  ENDMETHOD.

  METHOD more_sub.

    FIELD-SYMBOLS: <ls_tree> LIKE LINE OF mt_trees.

    append( iv_path = '/src/foo_a/foo_a1/'
            iv_name = 'a1.txt' ).

    append( iv_path = '/src/foo_a/foo_a2/'
            iv_name = 'a2.txt' ).

    mt_trees = zcl_abapgit_git_porcelain=>build_trees( mt_expanded ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( mt_trees )
      exp = 5 ).

    LOOP AT mt_trees ASSIGNING <ls_tree>.
      cl_abap_unit_assert=>assert_not_initial( <ls_tree>-data ).
    ENDLOOP.

  ENDMETHOD.

  METHOD namespaces.

    FIELD-SYMBOLS: <ls_tree> LIKE LINE OF mt_trees.

    append( iv_path = '/src/#foo#a/#foo#a1/'
            iv_name = 'a1.txt' ).

    append( iv_path = '/src/#foo#a/#foo#a2/'
            iv_name = 'a2.txt' ).

    mt_trees = zcl_abapgit_git_porcelain=>build_trees( mt_expanded ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( mt_trees )
      exp = 5 ).

    LOOP AT mt_trees ASSIGNING <ls_tree>.
      cl_abap_unit_assert=>assert_not_initial( <ls_tree>-data ).
    ENDLOOP.

  ENDMETHOD.

  METHOD root_empty.

    append( iv_path = '/sub/'
            iv_name = 'bar.txt' ).

    mt_trees = zcl_abapgit_git_porcelain=>build_trees( mt_expanded ).

* so 2 total trees are expected: '/' and '/sub/'
    cl_abap_unit_assert=>assert_equals(
      act = lines( mt_trees )
      exp = 2 ).

  ENDMETHOD.

  METHOD walk_for_blobs_single.
    " walk_for_blobs on a tree with one file node (no blob object present)
    " should yield exactly one stub with correct path/filename/sha1 and empty data

    DATA lt_objects TYPE zif_abapgit_definitions=>ty_objects_tt.
    DATA lt_nodes   TYPE zcl_abapgit_git_pack=>ty_nodes_tt.
    DATA ls_node    LIKE LINE OF lt_nodes.
    DATA lt_stubs   TYPE zif_abapgit_git_definitions=>ty_files_tt.
    DATA ls_stub    LIKE LINE OF lt_stubs.
    DATA lv_tree_sha TYPE zif_abapgit_git_definitions=>ty_sha1.
    DATA lv_blob_sha TYPE zif_abapgit_git_definitions=>ty_sha1.

    lv_blob_sha = 'aabbccddeeff00112233445566778899aabbccdd'.

    ls_node-chmod = zif_abapgit_git_definitions=>c_chmod-file.
    ls_node-name  = 'zcl_test.clas.abap'.
    ls_node-sha1  = lv_blob_sha.
    APPEND ls_node TO lt_nodes.

    lv_tree_sha = build_tree_object(
      EXPORTING it_nodes  = lt_nodes
      CHANGING  ct_objects = lt_objects ).

    zcl_abapgit_git_porcelain=>walk_for_blobs(
      EXPORTING it_objects = lt_objects
                iv_sha1    = lv_tree_sha
                iv_path    = '/'
      CHANGING  ct_stubs   = lt_stubs ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_stubs )
      exp = 1
      msg = 'Exactly one stub expected' ).

    READ TABLE lt_stubs INTO ls_stub INDEX 1.
    cl_abap_unit_assert=>assert_equals(
      act = ls_stub-path
      exp = '/'
      msg = 'Path must be root' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_stub-filename
      exp = 'zcl_test.clas.abap'
      msg = 'Filename must match node name' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_stub-sha1
      exp = lv_blob_sha
      msg = 'SHA1 must match blob SHA1' ).
    cl_abap_unit_assert=>assert_initial(
      act = ls_stub-data
      msg = 'Data must be empty (blob not fetched in phase 1)' ).

  ENDMETHOD.

  METHOD walk_for_blobs_subdir.
    " walk_for_blobs on a root tree with one dot-file and one subdirectory
    " should yield two stubs: one in '/' and one in '/src/'

    DATA lt_objects  TYPE zif_abapgit_definitions=>ty_objects_tt.
    DATA lt_nodes    TYPE zcl_abapgit_git_pack=>ty_nodes_tt.
    DATA ls_node     LIKE LINE OF lt_nodes.
    DATA lt_stubs    TYPE zif_abapgit_git_definitions=>ty_files_tt.
    DATA lv_root_sha TYPE zif_abapgit_git_definitions=>ty_sha1.
    DATA lv_sub_sha  TYPE zif_abapgit_git_definitions=>ty_sha1.
    DATA lv_dot_sha  TYPE zif_abapgit_git_definitions=>ty_sha1.
    DATA lv_sub_file_sha TYPE zif_abapgit_git_definitions=>ty_sha1.

    lv_dot_sha      = '1111111111111111111111111111111111111111'.
    lv_sub_file_sha = '2222222222222222222222222222222222222222'.

    " Build sub-tree with one file
    CLEAR lt_nodes.
    ls_node-chmod = zif_abapgit_git_definitions=>c_chmod-file.
    ls_node-name  = 'zcl_sub.clas.xml'.
    ls_node-sha1  = lv_sub_file_sha.
    APPEND ls_node TO lt_nodes.

    lv_sub_sha = build_tree_object(
      EXPORTING it_nodes   = lt_nodes
      CHANGING  ct_objects = lt_objects ).

    " Build root tree with one dot-file and one subdir
    CLEAR lt_nodes.
    ls_node-chmod = zif_abapgit_git_definitions=>c_chmod-file.
    ls_node-name  = '.abapgit.xml'.
    ls_node-sha1  = lv_dot_sha.
    APPEND ls_node TO lt_nodes.

    ls_node-chmod = zif_abapgit_git_definitions=>c_chmod-dir.
    ls_node-name  = 'src'.
    ls_node-sha1  = lv_sub_sha.
    APPEND ls_node TO lt_nodes.

    lv_root_sha = build_tree_object(
      EXPORTING it_nodes   = lt_nodes
      CHANGING  ct_objects = lt_objects ).

    zcl_abapgit_git_porcelain=>walk_for_blobs(
      EXPORTING it_objects = lt_objects
                iv_sha1    = lv_root_sha
                iv_path    = '/'
      CHANGING  ct_stubs   = lt_stubs ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_stubs )
      exp = 2
      msg = 'Two stubs expected: one root file + one subdir file' ).

    " Verify root file stub
    READ TABLE lt_stubs WITH KEY path = '/' filename = '.abapgit.xml' TRANSPORTING NO FIELDS.
    cl_abap_unit_assert=>assert_subrc(
      act = sy-subrc
      msg = 'Root .abapgit.xml stub must be present' ).

    " Verify subdir file stub
    READ TABLE lt_stubs WITH KEY path = '/src/' filename = 'zcl_sub.clas.xml' TRANSPORTING NO FIELDS.
    cl_abap_unit_assert=>assert_subrc(
      act = sy-subrc
      msg = 'Subdir zcl_sub.clas.xml stub must be present' ).

  ENDMETHOD.

  METHOD pull_full_walk_no_filter.
    " pull without iv_filter/iv_url should use full walk and populate blob data

    DATA lt_objects  TYPE zif_abapgit_definitions=>ty_objects_tt.
    DATA ls_obj      LIKE LINE OF lt_objects.
    DATA lt_nodes    TYPE zcl_abapgit_git_pack=>ty_nodes_tt.
    DATA ls_node     LIKE LINE OF lt_nodes.
    DATA lt_files    TYPE zif_abapgit_git_definitions=>ty_files_tt.
    DATA ls_file     LIKE LINE OF lt_files.
    DATA lv_blob_sha TYPE zif_abapgit_git_definitions=>ty_sha1.
    DATA lv_tree_sha TYPE zif_abapgit_git_definitions=>ty_sha1.
    DATA lv_commit_sha TYPE zif_abapgit_git_definitions=>ty_sha1.
    DATA lv_blob_data TYPE xstring.
    DATA ls_commit   TYPE zcl_abapgit_git_pack=>ty_commit.

    " Build blob
    lv_blob_data = zcl_abapgit_convert=>string_to_xstring_utf8( 'hello abapgit' ).
    lv_blob_sha  = zcl_abapgit_hash=>sha1_blob( lv_blob_data ).

    ls_obj-sha1 = lv_blob_sha.
    ls_obj-type = zif_abapgit_git_definitions=>c_type-blob.
    ls_obj-data = lv_blob_data.
    APPEND ls_obj TO lt_objects.

    " Build tree pointing to blob
    ls_node-chmod = zif_abapgit_git_definitions=>c_chmod-file.
    ls_node-name  = 'readme.txt'.
    ls_node-sha1  = lv_blob_sha.
    APPEND ls_node TO lt_nodes.

    lv_tree_sha = build_tree_object(
      EXPORTING it_nodes   = lt_nodes
      CHANGING  ct_objects = lt_objects ).

    " Build commit pointing to tree
    ls_commit-tree      = lv_tree_sha.
    ls_commit-author    = 'Test User <test@example.com> 0 +0000'.
    ls_commit-committer = 'Test User <test@example.com> 0 +0000'.
    ls_commit-body      = 'test commit'.

    ls_obj-data = zcl_abapgit_git_pack=>encode_commit( ls_commit ).
    ls_obj-type = zif_abapgit_git_definitions=>c_type-commit.
    ls_obj-sha1 = zcl_abapgit_hash=>sha1_commit( ls_obj-data ).
    APPEND ls_obj TO lt_objects.
    lv_commit_sha = ls_obj-sha1.

    " Call pull without filter → should use full walk
    lt_files = zcl_abapgit_git_porcelain=>pull(
      iv_commit  = lv_commit_sha
      it_objects = lt_objects ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_files )
      exp = 1
      msg = 'Exactly one file expected from full walk' ).

    READ TABLE lt_files INTO ls_file INDEX 1.
    cl_abap_unit_assert=>assert_equals(
      act = ls_file-filename
      exp = 'readme.txt'
      msg = 'Filename must match tree node' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = ls_file-data
      msg = 'Blob data must be populated by full walk' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_file-data
      exp = lv_blob_data
      msg = 'Blob data must match original content' ).

  ENDMETHOD.

  METHOD filter_stubs_keeps_match.
    " filter_stubs with a matching filename keeps the stub

    DATA lt_stubs        TYPE zif_abapgit_git_definitions=>ty_files_tt.
    DATA ls_stub         LIKE LINE OF lt_stubs.
    DATA lt_wanted_files TYPE string_table.

    ls_stub-filename = 'zcl_myclass.clas.abap'.
    ls_stub-path     = '/'.
    ls_stub-sha1     = '1111111111111111111111111111111111111111'.
    APPEND ls_stub TO lt_stubs.

    APPEND 'zcl_myclass.clas.abap' TO lt_wanted_files.

    zcl_abapgit_git_porcelain=>filter_stubs(
      EXPORTING it_wanted_files = lt_wanted_files
      CHANGING  ct_stubs        = lt_stubs ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_stubs )
      exp = 1
      msg = 'Matching stub must be kept' ).

  ENDMETHOD.

  METHOD filter_stubs_removes_no_match.
    " filter_stubs removes non-matching stubs and is case-insensitive

    DATA lt_stubs        TYPE zif_abapgit_git_definitions=>ty_files_tt.
    DATA ls_stub         LIKE LINE OF lt_stubs.
    DATA lt_wanted_files TYPE string_table.

    " Stub 1: matches (uppercase in stub, lowercase in wanted list)
    ls_stub-filename = 'ZCL_MYCLASS.clas.abap'.
    ls_stub-path     = '/'.
    ls_stub-sha1     = '1111111111111111111111111111111111111111'.
    APPEND ls_stub TO lt_stubs.

    " Stub 2: no match
    ls_stub-filename = 'zcl_other.clas.abap'.
    ls_stub-sha1     = '2222222222222222222222222222222222222222'.
    APPEND ls_stub TO lt_stubs.

    APPEND 'zcl_myclass.clas.abap' TO lt_wanted_files.

    zcl_abapgit_git_porcelain=>filter_stubs(
      EXPORTING it_wanted_files = lt_wanted_files
      CHANGING  ct_stubs        = lt_stubs ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_stubs )
      exp = 1
      msg = 'Only matching stub must remain' ).

    READ TABLE lt_stubs INTO ls_stub INDEX 1.
    cl_abap_unit_assert=>assert_char_cp(
      act = to_lower( ls_stub-filename )
      exp = 'zcl_myclass*'
      msg = 'Remaining stub must be the matching one' ).

  ENDMETHOD.

ENDCLASS.
