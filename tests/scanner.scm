(define-module (tests scanner)
  ;; #:use-module ((wayland client display) #:prefix c:)
  #:use-module (wayland client protocol wayland)
  #:use-module (wayland scanner)
  #:use-module (wayland list)
  #:use-module (bytestructure-class)
  #:use-module (bytestructures guile)
  #:use-module (oop goops)
  #:use-module ((system foreign) #:prefix ffi:)
  #:use-module (srfi srfi-64)
  #:use-module (srfi srfi-34)
  #:use-module (srfi srfi-35))

(test-group "scanner"
  (test-error "guile-wayland-protocol-path: fail"
              'system-error
              (let ((m (make-fresh-user-module)))
                (module-use! m (resolve-interface
                                '(wayland client protocol wayland)))
                (module-use! m (resolve-interface '(wayland scanner)))
                (eval '(use-wayland-protocol ("idle.xml" #:type client)) m)))
  (test-assert "guile-wayland-protocol-path"
    (let ((m (make-fresh-user-module)))
      (module-use! m (resolve-interface '(wayland client protocol wayland)))
      (module-use! m (resolve-interface '(wayland scanner)))
      (parameterize ((guile-wayland-protocol-path
                      (list (dirname (current-filename)))))
        (eval '(use-wayland-protocol ("idle.xml" #:type client)) m)
        (module-defined?
         m
         '%org-kde-kwin-idle-struct))))

  (test-assert "client event object uses its declared interface"
    (let* ((called? #f)
           (listener
            (make <wl-surface-listener>
              #:enter
              (lambda (data surface output)
                (set! called?
                      (and (wl-surface? surface)
                           (wl-output? output)
                           (= (ffi:pointer-address (unwrap-wl-surface surface)) 1)
                           (= (ffi:pointer-address (unwrap-wl-output output)) 2))))))
           (enter-address
            (bytestructure-ref (get-bytestructure listener) 'enter))
           (enter
            (ffi:pointer->procedure ffi:void
                                    (ffi:make-pointer enter-address)
                                    (list '* '* '*))))
      (enter ffi:%null-pointer (ffi:make-pointer 1) (ffi:make-pointer 2))
      called?))

  (test-assert "generated listener callback survives forced GC"
    (let ((called? #f))
      (define (make-listener-and-entry-point)
        (let* ((listener
                (make <wl-surface-listener>
                  #:enter
                  (lambda (data surface output)
                    (set! called?
                          (and (wl-surface? surface)
                               (wl-output? output))))))
               (enter-address
                (bytestructure-ref (get-bytestructure listener) 'enter)))
          (values listener
                  (ffi:pointer->procedure ffi:void
                                          (ffi:make-pointer enter-address)
                                          (list '* '* '*)))))
      (call-with-values make-listener-and-entry-point
        (lambda (listener enter)
          ;; At this point the constructor's callback procedure and native
          ;; trampoline pointer are reachable only through LISTENER.
          (gc)
          (gc)
          (enter ffi:%null-pointer (ffi:make-pointer 1) (ffi:make-pointer 2))
          (and listener called?))))))
