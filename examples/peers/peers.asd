;;;; peers.asd -- two Lisp images finding each other, over MultipeerConnectivity.

(defsystem "peers"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "peers:start"
  :description "MultipeerConnectivity from Lisp: each phone advertises and browses, invitations are answered by calling the block the framework handed over, and connected peers evaluate each other's forms."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "peers"))

  :bundle-identifier "org.asdf-ios-app.peers"
  :bundle-name "Peers"
  :bundle-executable "peers"
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment says how -- as sensors and closure-probe do.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "MultipeerConnectivity")
  :bundle-info-plist (("NSBonjourServices" . (:array "_lisp-peers._tcp" "_lisp-peers._udp"))
                      ("NSLocalNetworkUsageDescription" . "To find other Lisp images nearby."))

  ;; A device build must be signed. Read from the environment at the time
  ;; this file is read, so that nobody's identity is committed here.
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))
