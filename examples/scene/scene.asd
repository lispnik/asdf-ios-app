;;;; scene.asd -- an app with a delegate of its own, using UIScene.

(defsystem "scene"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "scene-ios:start"
  :description "A scene-based application delegate in the app's own Objective-C, with every lifecycle event reported to Lisp; and an icon."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "scene"))

  :bundle-identifier "org.asdf-ios-app.scene"
  :bundle-name "Scene"
  :bundle-executable "scene"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait :landscape-left :landscape-right)

  ;; The app's own delegate replaces the shipped ECLAppDelegate: named
  ;; here, compiled from the source named below, after the shipped shim.
  :bundle-app-delegate "SceneAppDelegate"
  :bundle-objc-sources ("SceneAppDelegate.m")

  ;; UIKit looks for the scene delegate through this manifest; the name
  ;; matches the configuration SceneAppDelegate returns.  Merged over the
  ;; generated Info.plist.
  :bundle-info-plist
  (("UIApplicationSceneManifest"
    . (:dict ("UIApplicationSupportsMultipleScenes" . :false)
             ("UISceneConfigurations"
              . (:dict ("UIWindowSceneSessionRoleApplication"
                        . (:array (:dict ("UISceneConfigurationName" . "Default")
                                         ("UISceneDelegateClassName" . "SceneDelegate")))))))))

  ;; An icon, compiled by actool from the asset catalogue.
  :bundle-icon "Icon.xcassets")
