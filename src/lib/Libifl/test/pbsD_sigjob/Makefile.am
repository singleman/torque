PROG_ROOT = ../..

AM_CFLAGS = -g -DTEST_FUNCTION -I${PROG_ROOT}/ -I${PROG_ROOT}/${PBS_MACH} --coverage

lib_LTLIBRARIES = libpbsD_sigjob.la

AM_LDFLAGS = @CHECK_LIBS@ ${lib_LTLIBRARIES}

check_PROGRAMS = test_pbsD_sigjob

libpbsD_sigjob_la_SOURCES = scaffolding.c ${PROG_ROOT}/pbsD_sigjob.c
libpbsD_sigjob_la_LDFLAGS = @CHECK_LIBS@ -shared -lgcov

test_pbsD_sigjob_SOURCES = test_pbsD_sigjob.c

check_SCRIPTS = ${PROG_ROOT}/../../test/coverage_run.sh

TESTS = ${check_PROGRAMS} ${check_SCRIPTS} 

CLEANFILES = *.gcno *.gcda *.gcov core *.lo
