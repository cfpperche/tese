<!-- vendored from open-design@c128ffd53bba3f3080b2d0b7d656d1634016e10a:design-templates/hyperframes/references/transitions/css-grid.md · do not edit -->
## Grid

### Grid Dissolve

Grid of colored cells covers the frame in a ripple from center. Scene swaps at 50% coverage. Cells fade out in ripple.

**12-cell** (4x3, each 480x270): standard
**120-cell** (12x10, each 160x108): dense variant — lower opacity (0.75), tighter ripple

Cells are created dynamically in JS, sorted by distance from center for ripple stagger.
