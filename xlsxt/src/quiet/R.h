/*
 * R.h - NOT the R language's header: the one line of it libxlsxwriter needs.
 *
 * libxlsxwriter reports a refused call twice: by its return value, which the
 * shim turns into xlx_last_error(), and by printing a "[WARNING]: ..." line
 * on stderr. A library loaded into somebody's application has no business
 * writing to that application's stderr (a desktop app has no console to show
 * it, and a server's log is the server's). Upstream has exactly one switch
 * for "the host is not a console program": USE_R_LANG, which sends every
 * message through REprintf() from <R.h> instead of fprintf(stderr, ...).
 * CMakeLists.txt defines USE_R_LANG and puts this folder on the include
 * path, so the name resolves here, to a function that prints nothing.
 * Nothing upstream is patched, and nothing else in libxlsxwriter reads
 * USE_R_LANG (tools/check-pins.py holds that to the pinned source).
 */
#ifndef XLSXT_QUIET_R_H
#define XLSXT_QUIET_R_H

static inline void REprintf(const char *format, ...)
{
    (void)format;
}

#endif
