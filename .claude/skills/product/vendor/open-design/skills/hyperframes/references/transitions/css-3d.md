<!-- vendored from open-design@c128ffd53bba3f3080b2d0b7d656d1634016e10a:design-templates/hyperframes/references/transitions/css-3d.md · do not edit -->
## 3D

### 3D Card Flip

180° Y-axis rotation. Requires CSS: `backface-visibility: hidden; transform-style: preserve-3d;` on both scene-inners. Parent needs `perspective: 1200px`.

```js
tl.set(new, { rotationY: -180, opacity: 1 }, T);
tl.to(old, { rotationY: 180, duration: 0.6, ease: "power2.inOut" }, T);
tl.to(new, { rotationY: 0, duration: 0.6, ease: "power2.inOut" }, T);
tl.set(old, { opacity: 0 }, T + 0.6);
```
