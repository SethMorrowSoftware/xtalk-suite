# Test models

`teapot.obj` is the Utah teapot: 3644 points and 6320 triangles, modelled by Martin Newell at
the University of Utah in 1975 and passed around freely as a standard test object ever since.
This copy is the triangulated one from the common-3d-test-models collection
(github.com/alecjacobson/common-3d-test-models, `data/teapot.obj`), unchanged; its SHA-256 is
in the header generated from it. Neither the collection nor the original data carries a
written licence: it is used here as the long-standing public test model it is, for tests only,
and no library or package built from this member contains it.

`tests/teapot_model.h` is this file as C arrays (`tools/build-test-model.py`; a gate holds the
two together), because the native tests also run where there is no file to open. The engine
self-test reads the `.obj` itself, the way a stack would.
