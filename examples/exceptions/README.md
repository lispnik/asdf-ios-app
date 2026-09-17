# exceptions

Three failures earned on purpose on a phone, and caught.

<img src="../../doc/screenshots/exceptions.png" width="300" alt="A screen listing an NSRangeException with its reason, an NSInvalidArgumentException, an NSError with NSCocoaErrorDomain 260, and a line saying the next send works.">

The objc library's `examples/exceptions.lisp`, on iOS. An `NSException`
raised inside a send used to end the app; the runtime's uncaught-exception
handler is the library's now, and the innermost send signals
`objc:objc-exception` with the name and reason. On a device that is a
static ECL image with libffi callbacks and no C compiler, which is the
build the mechanism was least sure of, so this earns an array past its
end, a selector nothing implements sent unresolved through
`performSelector:`, and a file that is not there through
`objc:invoke-with-error`, prints each to the kept console, and then sends
once more to show the app is still whole.
