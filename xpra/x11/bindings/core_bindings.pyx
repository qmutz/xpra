# This file is part of Xpra.
# Copyright (C) 2008, 2009 Nathaniel Smith <njs@pobox.com>
# Copyright (C) 2010-2021 Antoine Martin <antoine@xpra.org>
# Xpra is released under the terms of the GNU GPL v2, or, at your option, any
# later version. See the file COPYING for details.

#cython: auto_pickle=False, language_level=3

from libc.stdlib cimport malloc, free       #pylint: disable=syntax-error
from libc.stdint cimport uintptr_t

from xpra.util import envbool
from xpra.os_util import strtobytes, is_X11
from xpra.log import Logger
log = Logger("x11", "bindings", "core")


###################################
# Headers, python magic
###################################
cdef extern from "X11/Xutil.h":
    pass

cdef extern from "X11/Xmd.h":
    ctypedef unsigned long CARD32

######
# Xlib primitives and constants
######

cdef extern from "X11/Xlib.h":
    int CurrentTime
    int MappingBusy
    int GrabModeAsync
    int AnyModifier

    ctypedef struct Display:
        pass
    ctypedef CARD32 Time
    ctypedef int Bool
    ctypedef int Status
    ctypedef CARD32 Atom

    Atom XInternAtom(Display * display, char * atom_name, Bool only_if_exists)
    Status XInternAtoms(Display *display, char **names, int count, Bool only_if_exists, Atom *atoms_return)
    char *XGetAtomName(Display *display, Atom atom)

    int XFree(void * data)

    void XGetErrorText(Display * display, int code, char * buffer_return, int length)

    int XUngrabKeyboard(Display * display, Time t)
    int XUngrabPointer(Display * display, Time t)

    int *XSynchronize(Display *display, Bool onoff)


from xpra.x11.bindings.display_source cimport get_display
from xpra.x11.bindings.display_source import get_display_name

cdef X11CoreBindingsInstance singleton = None
def X11CoreBindings():
    global singleton
    if singleton is None:
        singleton = X11CoreBindingsInstance()
    return singleton

#for debugging, we can hook this function which will log the caller:
def caller_logger(*args):
    import sys
    f = sys._getframe(1)
    c = f.f_code
    log.info("noop: %s %s %s %s", c.co_name, f.f_back, c.co_filename, f.f_lineno)

def noop(*args):
    pass

cdef object context_check = noop
def set_context_check(fn):
    global context_check
    context_check = fn


cdef class X11CoreBindingsInstance:

    def __cinit__(self):
        assert is_X11(), "cannot load X11 bindings with wayland under python3 / GTK3"
        self.display = get_display()
        assert self.display!=NULL, "display is not set!"
        dn = get_display_name()
        bstr = strtobytes(dn)
        self.display_name = bstr
        if envbool("XPRA_X_SYNC", False):
            XSynchronize(self.display, True)

    def context_check(self):
        global context_check
        context_check()

    def get_display_name(self):
        return self.display_name

    def __repr__(self):
        return "X11CoreBindings(%s)" % self.display_name

    cdef Atom xatom(self, str_or_int):
        """Returns the X atom corresponding to the given Python string or Python
        integer (assumed to already be an X atom)."""
        self.context_check()
        if isinstance(str_or_int, (int, long)):
            return <Atom> str_or_int
        bstr = strtobytes(str_or_int)
        cdef char* string = bstr
        assert self.display!=NULL, "display is closed"
        return XInternAtom(self.display, string, False)

    def intern_atoms(self, atom_names):
        cdef int count = len(atom_names)
        cdef char** names = <char **> malloc(sizeof(uintptr_t)*(count+1))
        assert names!=NULL
        cdef Atom* atoms_return = <Atom*> malloc(sizeof(Atom)*(count+1))
        assert atoms_return!=NULL
        from ctypes import create_string_buffer, addressof
        str_names = tuple(create_string_buffer(strtobytes(x)) for x in atom_names)
        cdef uintptr_t ptr = 0
        for i, x in enumerate(str_names):
            ptr = addressof(x)
            names[i] = <char*> ptr
        cdef Status s = XInternAtoms(self.display, names, count, 0, atoms_return)
        free(names)
        free(atoms_return)
        assert s!=0, "failed to intern some atoms"

    def get_xatom(self, str_or_int):
        return self.xatom(str_or_int)

    def XGetAtomName(self, Atom atom):
        self.context_check()
        cdef char *v = XGetAtomName(self.display, atom)
        if v==NULL:
            return None
        r = v[:]
        XFree(v)
        return r

    def get_error_text(self, code):
        assert self.display!=NULL, "display is closed"
        if type(code)!=int:
            return code
        cdef char[128] buffer
        XGetErrorText(self.display, code, buffer, 128)
        return (bytes(buffer[:128]).split(b"\0", 1)[0]).decode("latin1")

    def UngrabKeyboard(self, time=CurrentTime):
        assert self.display!=NULL, "display is closed"
        return XUngrabKeyboard(self.display, time)

    def UngrabPointer(self, time=CurrentTime):
        assert self.display!=NULL, "display is closed"
        return XUngrabPointer(self.display, time)
