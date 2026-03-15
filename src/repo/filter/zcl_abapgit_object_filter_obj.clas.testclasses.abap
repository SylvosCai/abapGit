CLASS ltcl_object_filter_obj DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS get_paths_with_paths    FOR TESTING RAISING cx_static_check.
    METHODS get_paths_without_paths FOR TESTING RAISING cx_static_check.

ENDCLASS.

CLASS ltcl_object_filter_obj IMPLEMENTATION.

  METHOD get_paths_with_paths.

    DATA lt_paths TYPE string_table.
    DATA lo_cut   TYPE REF TO zcl_abapgit_object_filter_obj.

    APPEND '/src/mypackage/' TO lt_paths.
    APPEND '/src/other/'     TO lt_paths.

    CREATE OBJECT lo_cut
      EXPORTING
        it_filter = VALUE #( )
        it_paths  = lt_paths.

    cl_abap_unit_assert=>assert_equals(
      exp = lt_paths
      act = lo_cut->zif_abapgit_object_filter~get_paths( )
      msg = 'get_paths should return paths supplied at construction' ).

  ENDMETHOD.

  METHOD get_paths_without_paths.

    DATA lo_cut TYPE REF TO zcl_abapgit_object_filter_obj.

    CREATE OBJECT lo_cut
      EXPORTING
        it_filter = VALUE #( ).

    cl_abap_unit_assert=>assert_initial(
      act = lo_cut->zif_abapgit_object_filter~get_paths( )
      msg = 'get_paths should return empty when no paths supplied' ).

  ENDMETHOD.

ENDCLASS.
