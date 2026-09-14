# traits

Dark mode, Dynamic Type, the size class and the scale, answered from
Lisp.

<p>
<img src="../../doc/screenshots/traits.png" width="220" alt="Ten coloured tiles in five columns on a light background, under a line reading light, text L, compact width, 3x, 0 changes.">
<img src="../../doc/screenshots/traits-dark.png" width="220" alt="The same screen dark, with a brighter palette and the line now reading dark and 1 change.">
<img src="../../doc/screenshots/traits-large.png" width="220" alt="The same screen dark and with the largest accessibility text: three bigger tiles per row, a larger status line, and a count of two changes.">
</p>

The trait collection carries what the system decided about an app's
surroundings, and since iOS 17 a view can register a block for changes to
the traits it cares about, no subclass needed. The block is a Lisp
closure, and everything on screen follows from the traits Lisp reads: the
palette per appearance, the type size, the number of columns.

```lisp
(asdf:make "traits")
(ios-app:run-in-simulator "traits")
```

The simulator flips them from the command line, which is how the
pictures were taken:

```
xcrun simctl ui booted appearance dark
xcrun simctl ui booted content_size extra-extra-extra-large
```
