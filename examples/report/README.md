# report

A PDF written by Lisp, previewed with Quick Look, offered by the share
sheet.

<img src="../../doc/screenshots/report.png" width="300" alt="A Quick Look preview of a one-page PDF titled The image, as a report, with a bar chart of package symbol counts in eight colours and a footer line.">

`UIGraphicsPDFRenderer` runs a block per document, and inside it the
ordinary drawing API works: strings draw themselves with attributes,
paths fill. The block is a Lisp closure and the data is the image's own
packages, so the report is Lisp's in every sense. `QLPreviewController`
then shows the file through a data source that is a Lisp class, and
`UIActivityViewController` offers it to whatever the phone has.

```lisp
(asdf:make "report")
(ios-app:run-in-simulator "report")
```

`REPORT_SHOW=preview` or `REPORT_SHOW=share` in the environment opens that
at launch, which is how the picture was taken.
