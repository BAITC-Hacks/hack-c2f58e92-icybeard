// echarts@6.1.0 ships full type declarations under types/dist/*.d.ts, but its
// package.json "exports" map does not attach a "types" condition to the
// "./core", "./components" and "./renderers" subpath entries (unlike
// "./charts", which does ship a matching charts.d.ts next to charts.js).
// Under TS "moduleResolution": "bundler" this makes tsc report TS7016 for
// every import from these subpaths, even though the code is correctly typed
// at runtime via echarts' own bundled types elsewhere in the package. This
// is an upstream packaging inconsistency in echarts 6.1.0 (verified: no
// newer 6.x exists on npm as of 2026-09-19), not a project bug.
//
// These shims silence the false-positive TS7016 without touching
// package.json/package-lock.json. If a future echarts release fixes its
// exports map, these declarations become redundant (harmless) rather than
// wrong, since `declare module` only loosens a stricter check.
declare module 'echarts/core'
declare module 'echarts/components'
declare module 'echarts/renderers'
