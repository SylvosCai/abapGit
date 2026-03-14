CLASS zcl_abapgit_object_filter_obj DEFINITION PUBLIC.
  PUBLIC SECTION.
    INTERFACES zif_abapgit_object_filter.

    METHODS constructor
      IMPORTING
        it_filter TYPE zif_abapgit_definitions=>ty_tadir_tt
        it_paths  TYPE string_table OPTIONAL.

  PRIVATE SECTION.
    DATA mt_filter TYPE zif_abapgit_definitions=>ty_tadir_tt.
    DATA mt_paths  TYPE string_table.
ENDCLASS.

CLASS zcl_abapgit_object_filter_obj IMPLEMENTATION.
  METHOD constructor.
    mt_filter = it_filter.
    mt_paths  = it_paths.
  ENDMETHOD.

  METHOD zif_abapgit_object_filter~get_filter.
    rt_filter = mt_filter.
  ENDMETHOD.

  METHOD zif_abapgit_object_filter~get_paths.
    rt_paths = mt_paths.
  ENDMETHOD.
ENDCLASS.
