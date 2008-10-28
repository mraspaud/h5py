#+
# 
# This file is part of h5py, a low-level Python interface to the HDF5 library.
# 
# Copyright (C) 2008 Andrew Collette
# http://h5py.alfven.org
# License: BSD  (See LICENSE.txt for full license)
# 
# $Date$
# 
#-

include "config.pxi"
include "sync.pxi"

# Module for the new "H5O" functions introduced in HDF5 1.8.0.  Not even
# built with API compatibility level below 1.8.

# Pyrex compile-time imports
from h5 cimport init_hdf5, ObjectID, SmartStruct
from h5g cimport GroupID
from h5i cimport wrap_identifier
from h5p cimport PropID, pdefault
from utils cimport emalloc, efree

# Initialization
init_hdf5()

# === Giant H5O_info_t structure ==============================================

cdef class _ObjInfoBase(SmartStruct):

    cdef H5O_info_t *istr

cdef class _OHdrMesg(_ObjInfoBase):

    property present:
        def __get__(self):
            return self.istr[0].hdr.mesg.present
    property shared:
        def __get__(self):
            return self.istr[0].hdr.mesg.shared

    def _hash(self):
        return hash((self.present, self.shared))

cdef class _OHdrSpace(_ObjInfoBase):

    property total:
        def __get__(self):
            return self.istr[0].hdr.space.total
    property meta:
        def __get__(self):
            return self.istr[0].hdr.space.meta
    property mesg:
        def __get__(self):
            return self.istr[0].hdr.space.mesg
    property free:
        def __get__(self):
            return self.istr[0].hdr.space.free

    def _hash(self):
        return hash((self.total, self.meta, self.mesg, self.free))

cdef class _OHdr(_ObjInfoBase):

    cdef public _OHdrSpace space
    cdef public _OHdrMesg mesg

    property version:
        def __get__(self):
            return self.istr[0].hdr.version
    property nmesgs:
        def __get__(self):
            return self.istr[0].hdr.nmesgs

    def __init__(self):
        self.space = _OHdrSpace()
        self.mesg = _OHdrMesg()

    def _hash(self):
        return hash((self.version, self.nmesgs, self.space, self.mesg))

cdef class _ObjInfo(_ObjInfoBase):

    property fileno:
        def __get__(self):
            return self.istr[0].fileno
    property addr:
        def __get__(self):
            return self.istr[0].addr
    property type:
        def __get__(self):
            return <int>self.istr[0].type
    property rc:
        def __get__(self):
            return self.istr[0].rc

    def _hash(self):
        return hash((self.fileno, self.addr, self.type, self.rc))

cdef class ObjInfo(_ObjInfo):

    """
        Represents the H5O_info_t structure
    """

    cdef H5O_info_t infostruct
    cdef public _OHdr hdr

    def __init__(self):
        self.hdr = _OHdr()

        self.istr = &self.infostruct
        self.hdr.istr = &self.infostruct
        self.hdr.space.istr = &self.infostruct
        self.hdr.mesg.istr = &self.infostruct

    def __copy__(self):
        cdef ObjInfo newcopy
        newcopy = ObjInfo()
        newcopy.infostruct = self.infostruct
        return newcopy

@sync
def get_info(ObjectID loc not None, char* name=NULL, int index=-1, *,
        char* obj_name='.', int index_type=H5_INDEX_NAME, int order=H5_ITER_NATIVE,
        PropID lapl=None):
    """(ObjectID loc, STRING name=, INT index=, **kwds) => ObjInfo

    Get information describing an object in an HDF5 file.  Provide the object
    itself, or the containing group and exactly one of "name" or "index".

    STRING obj_name (".")
        When "index" is specified, look in this subgroup instead.
        Otherwise ignored.

    PropID lapl (None)
        Link access property list

    INT index_type (h5.INDEX_NAME)

    INT order (h5.ITER_NATIVE)
    """
    cdef ObjInfo info
    info = ObjInfo()

    if name != NULL and index >= 0:
        raise TypeError("At most one of name or index may be specified")
    elif name != NULL and index < 0:
        H5Oget_info_by_name(loc.id, name, &info.infostruct, pdefault(lapl)) 
    elif name == NULL and index >= 0:
        H5Oget_info_by_idx(loc.id, obj_name, <H5_index_t>index_type,
            <H5_iter_order_t>order, index, &info.infostruct, pdefault(lapl))
    else: 
        H5Oget_info(loc.id, &info.infostruct)

    return info

# === General object operations ===============================================

@sync
def open(ObjectID loc not None, char* name, PropID lapl=None):
    """(ObjectID loc, STRING name, PropID lapl=None) => ObjectID

    Open a group, dataset, or named datatype attached to an existing group.
    """
    return wrap_identifier(H5Oopen(loc.id, name, pdefault(lapl)))

@sync
def link(ObjectID obj not None, GroupID loc not None, char* name,
    PropID lcpl=None, PropID lapl=None):
    """(ObjectID obj, GroupID loc, STRING name, PropID lcpl=None,
    PropID lapl=None)

    Create a new hard link to an object.  Useful for objects created with
    h5g.create_anon or h5d.create_anon.
    """
    H5Olink(obj.id, loc.id, name, pdefault(lcpl), pdefault(lapl))

@sync
def copy(GroupID src_loc not None, char* src_name, GroupID dst_loc not None,
    char* dst_name, PropID copypl=None, PropID lcpl=None):
    """(GroupID src_loc, STRING src_name, GroupID dst_loc, STRING dst_name,
    PropID copypl=None, PropID lcpl=None)
    
    Copy a group, dataset or named datatype from one location to another.  The
    source and destination need not be in the same file.

    The default behavior is a recursive copy of the object and all objects
    below it.  This behavior is modified via the "copypl" property list.
    """
    H5Ocopy(src_loc.id, src_name, dst_loc.id, dst_name, pdefault(copypl),
        pdefault(lcpl))

@sync
def set_comment(ObjectID loc not None, char* comment, *, char* obj_name=".",
    PropID lapl=None):
    """(ObjectID loc, STRING comment, **kwds)

    Set the comment for any-file resident object.  Keywords:

    STRING obj_name (".")
        Set comment on this group member instead

    PropID lapl (None)
        Link access property list
    """
    H5Oset_comment_by_name(loc.id, obj_name, comment, pdefault(lapl))


@sync
def get_comment(ObjectID loc not None, char* comment, *, char* obj_name=".",
    PropID lapl=None):
    """(ObjectID loc, STRING comment, **kwds)

    Get the comment for any-file resident object.  Keywords:

    STRING obj_name (".")
        Set comment on this group member instead

    PropID lapl (None)
        Link access property list
    """
    cdef ssize_t size
    cdef char* buf

    size = H5Oget_comment_by_name(loc.id, obj_name, NULL, 0, pdefault(lapl))
    buf = <char*>emalloc(size+1)
    try:
        H5Oget_comment_by_name(loc.id, obj_name, buf, size+1, pdefault(lapl))
        pstring = buf
    finally:
        efree(buf)

    return pstring

# === Visit routines ==========================================================

cdef class _ObjectVisitor:

    cdef object func
    cdef object retval
    cdef ObjInfo objinfo

    def __init__(self, func):
        self.func = func
        self.retval = None
        self.objinfo = ObjInfo()

cdef herr_t cb_obj_iterate(hid_t obj, char* name, H5O_info_t *info, void* data) except 2:

    cdef _ObjectVisitor visit
    visit = <_ObjectVisitor>data

    visit.objinfo.infostruct = info[0]

    visit.retval = visit.func(name, visit.objinfo)

    if (visit.retval is None) or (not visit.retval):
        return 0
    return 1

cdef herr_t cb_obj_simple(hid_t obj, char* name, H5O_info_t *info, void* data) except 2:

    cdef _ObjectVisitor visit
    visit = <_ObjectVisitor>data

    visit.retval = visit.func(name)

    if (visit.retval is None) or (not visit.retval):
        return 0
    return 1

@sync
def visit(ObjectID loc not None, object func, *,
          int idx_type=H5_INDEX_NAME, int order=H5_ITER_NATIVE,
          char* obj_name=".", PropID lapl=None, bint info=0):
    """(ObjectID loc, CALLABLE func, **kwds) => <Return value from func>

    Iterate a function or callable object over all objects below the
    specified one.  Your callable should conform to the signature::

        func(STRING name) => Result

    or if the keyword argument "info" is True::
    
        func(STRING name, ObjInfo info) => Result

    Returning None or a logical False continues iteration; returning
    anything else aborts iteration and returns that value.  Keywords:

    BOOL info (False)
        Callback is func(STRING, Objinfo)

    STRING obj_name (".")
        Visit a subgroup of "loc" instead

    PropLAID lapl (None)
        Control how "obj_name" is interpreted

    INT idx_type (h5.INDEX_NAME)
        What indexing strategy to use

    INT order (h5.ITER_NATIVE)
        Order in which iteration occurs
    """
    cdef _ObjectVisitor visit = _ObjectVisitor(func)
    cdef H5O_iterate_t cfunc

    if info:
        cfunc = cb_obj_iterate
    else:
        cfunc = cb_obj_simple

    H5Ovisit_by_name(loc.id, obj_name, <H5_index_t>idx_type,
        <H5_iter_order_t>order, cfunc, <void*>visit, pdefault(lapl))

    return visit.retval







