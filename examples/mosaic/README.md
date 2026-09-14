# mosaic

The packages of the running image as a mosaic, laid out by a Lisp
delegate that returns structures by value.

<img src="../../doc/screenshots/mosaic.png" width="300" alt="A grid of coloured rounded tiles of different sizes, each labelled with a package name and its symbol count, the largest tiles for the biggest packages.">

`UICollectionViewDelegateFlowLayout` asks its delegate for a `CGSize` per
item and a `UIEdgeInsets` per section, both returned by value. A Lisp
method returning a structure is the hardest thing the bridge does in the
inbound direction, and here it does it for every tile, on the phone,
through a libffi closure, with no C compiler anywhere. `UIEdgeInsets` is
declared with `objc:define-objc-struct`; `CGSize` is `cocoa:ns-size`, and
both are returned the same way, as a vector with one element per field.
The same vector goes the other way too: `setContentInset:` is given one
where it wants a UIEdgeInsets by value. This example is why the bridge
does that. Its first version had to return the insets as a pointer to
foreign memory filled in by hand, the only form the bridge took for a
declared structure, and the LispWorks manual's own way; the bridge now
writes any declared structure from a sequence, in both directions.

The same Lisp class is the data source. Each tile's area is proportional
to the package's symbol count, so the mosaic is a picture of the image
looking at itself.

```lisp
(asdf:make "mosaic")
(ios-app:run-in-simulator "mosaic")
```
