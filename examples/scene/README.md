# scene

An application delegate of the app's own, using UIScene, with every
lifecycle event reported to Lisp. And an icon.

<img src="../../doc/screenshots/scene.png" width="300" alt="A log of scene lifecycle events with times: will-connect, interface-built, did-become-active, will-resign-active, did-enter-background, will-enter-foreground, did-become-active; above it a line counting returns to the foreground and seconds spent in the background.">

The delegate asdf-ios-app ships makes its window the pre-iOS 13 way, and
UIKit now warns at every launch that the UIScene lifecycle will soon be
required. `SceneAppDelegate.m` is the scene-based pair: the application
delegate only names the scene delegate, and the scene delegate makes the
window, boots the image, and calls `scene-ios:lifecycle` for each event.
Three options in `scene.asd` make that happen, none used by any other
example:

```lisp
:bundle-app-delegate "SceneAppDelegate"       ; replaces ECLAppDelegate
:bundle-objc-sources ("SceneAppDelegate.m")   ; compiled after the shim
:bundle-info-plist (("UIApplicationSceneManifest" . ...))  ; how UIKit finds the scene delegate
:bundle-icon "Icon.xcassets"                  ; compiled by actool
```

The Lisp keeps the log, counts returns to the foreground and seconds
spent away, and shows both, which is what a real app does with these
events: pause, save, and on return, refresh.

```lisp
(asdf:make "scene")
(ios-app:run-in-simulator "scene")
```

Switch to another app and back to see the events arrive.
