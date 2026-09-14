;;;; opener.asd -- an app that owns a URL scheme and a document type.

(defsystem "opener"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "opener:start"
  :description "lisp:// links and .lisp documents open this app, and the delegate hands each to Lisp."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "opener"))

  :bundle-identifier "org.asdf-ios-app.opener"
  :bundle-name "Opener"
  :bundle-executable "opener"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)

  ;; The scheme: lisp://... links open this app.
  :bundle-url-schemes ("lisp")

  ;; The document type: .lisp files offer this app in Files and share
  ;; sheets.  LSItemContentTypes names a type this app also declares, as
  ;; UTExportedTypeDeclarations, so that the extension is known to the
  ;; system at all.
  :bundle-document-types
  ((:dict ("CFBundleTypeName" . "Lisp source")
          ("LSHandlerRank" . "Owner")
          ("LSItemContentTypes" . (:array "org.asdf-ios-app.lisp-source"))))
  :bundle-info-plist
  (("UTExportedTypeDeclarations"
    . (:array (:dict ("UTTypeIdentifier" . "org.asdf-ios-app.lisp-source")
                     ("UTTypeDescription" . "Lisp source")
                     ("UTTypeConformsTo" . (:array "public.plain-text" "public.source-code"))
                     ("UTTypeTagSpecification"
                      . (:dict ("public.filename-extension" . (:array "lisp" "asd")))))))
   ("UIApplicationSceneManifest"
    . (:dict ("UIApplicationSupportsMultipleScenes" . :false)
             ("UISceneConfigurations"
              . (:dict ("UIWindowSceneSessionRoleApplication"
                        . (:array (:dict ("UISceneConfigurationName" . "Default")
                                         ("UISceneDelegateClassName" . "OpenerSceneDelegate")))))))))

  ;; The delegate that receives the URLs: the app's own, scene based.
  :bundle-app-delegate "OpenerAppDelegate"
  :bundle-objc-sources ("OpenerDelegate.m"))
