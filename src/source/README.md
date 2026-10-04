# Source utilities

This folder holds types that help the rest of the compiler keep track of where
pieces of code came from.  The `LOCATION` class records file names and
line/column ranges.  It is used throughout diagnostics and in many passes that
need to correlate generated code back to the original source.  `BUILD_NUMBER`
tracks a monotonically increasing integer for incremental builds.  `SOURCE_LIBRARY`
and `SOURCE_LIBRARIES` record the source libraries declared with
`--library-source` and answer which library a source file belongs to.

If you need to add new kinds of source metadata, bear in mind the run-time cost as it's attached to every AST node
