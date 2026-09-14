;;;; agenda.asd -- the calendar and the contacts, from Lisp.

(defsystem "agenda"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "agenda:start"
  :description "EventKit and Contacts from Lisp: access asked for through blocks, events created and listed, contacts enumerated through a block and grouped in Lisp."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "agenda"))

  :bundle-identifier "org.asdf-ios-app.agenda"
  :bundle-name "Agenda"
  :bundle-executable "agenda"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "EventKit" "Contacts")
  :bundle-info-plist (("NSCalendarsFullAccessUsageDescription" . "To list the week and add an event from Lisp.")
                      ("NSContactsUsageDescription" . "To group the contacts by initial in Lisp.")))
