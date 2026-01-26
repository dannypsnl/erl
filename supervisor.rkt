#lang racket/base
(provide supervisor%
         supervisor:start
         supervisor:stop
         supervisor:which-children
         child-spec)
(require racket/class
         racket/match
         racket/async-channel)
(require "genserver.rkt")

(define (supervisor:start impl child-specs)
  (gen-server:start impl child-specs))
(define (supervisor:stop supervisor [reason 'normal])
  (gen-server:stop supervisor reason))
(define (supervisor:which-children supervisor)
  (gen-server:call supervisor 'which-children))

;; Child spec struct
;; start-thunk: a thunk that returns a running server
;; restart: 'permanent (always restart), 'temporary (never restart), 'transient (restart on abnormal exit)
(struct child-spec- (id start-thunk restart))
(define (child-spec #:id id #:start start-thunk #:restart [restart 'permanent])
  (child-spec- id start-thunk restart))

(struct sup-state (children child-specs monitor-thread))

(define supervisor%
  (class gen-server%
    (super-new)
    (inherit ok noreply reply)

    (define/private (start-child spec)
      (define id (child-spec--id spec))
      (define run (child-spec--start-thunk spec))
      (define server (run))
      (register id server)
      server)

    (define/private (start-all-children specs)
      (define children (make-hash))
      (define child-specs (make-hash))
      (for ([spec specs])
        (define id (child-spec--id spec))
        (hash-set! child-specs id spec)
        (hash-set! children id (start-child spec)))
      (values children child-specs))

    (define/private (make-monitor self-channel children)
      (thread
       (lambda ()
         (let loop ()
           ;; Build events for all children's thread-dead-evt
           (define evts
             (for/list ([(id server) (in-hash children)])
               (define thd (get-field running-server server))
               (handle-evt (thread-dead-evt thd)
                           (lambda (_) id))))
           (unless (null? evts)
             ;; Wait for any child to die
             (define dead-id (apply sync evts))
             ;; Notify supervisor via cast
             (async-channel-put self-channel (list 'cast (list 'child-died dead-id)))
             (loop))))))

    (define/private (restart-child id children child-specs)
      (define spec (hash-ref child-specs id))
      (define restart (child-spec--restart spec))
      (case restart
        [(permanent transient)
         (hash-set! children id (start-child spec))]
        [(temporary)
         (unregister id)
         (hash-remove! children id)]))

    (define/override (init specs)
      (define-values (children child-specs) (start-all-children specs))
      (define self-channel (get-field channel this))
      (define monitor (make-monitor self-channel children))
      (ok (sup-state children child-specs monitor)))

    (define/override (handle-call msg from state)
      (match msg
        ['which-children
         (reply from (hash-keys (sup-state-children state)) state)]))

    (define/override (handle-cast msg state)
      (match msg
        [(list 'child-died id)
         (define children (sup-state-children state))
         (define child-specs (sup-state-child-specs state))
         (restart-child id children child-specs)
         ;; Restart monitor with updated children
         (kill-thread (sup-state-monitor-thread state))
         (define new-monitor (make-monitor (get-field channel this) children))
         (noreply (sup-state children child-specs new-monitor))]
        [_ (noreply state)]))

    (define/override (terminate reason state)
      ;; Stop monitor thread
      (kill-thread (sup-state-monitor-thread state))
      ;; Stop and unregister all children
      (for ([(id server) (in-hash (sup-state-children state))])
        (unregister id)
        (gen-server:stop server 'shutdown)))))

(module+ test
  (require rackunit)

  (struct counter-state (value))
  (define my-counter%
    (class gen-server%
      (super-new)
      (inherit ok noreply reply)

      (define/override (init args)
        (match-define (list n) args)
        (ok (counter-state n)))

      (define/override (handle-call msg from state)
        (match msg
          ['get
           (reply from (counter-state-value state) state)]
          [_ (reply from 'unknown state)]))

      (define/override (handle-cast msg state)
        (match msg
          ['die (error "intentional crash")]
          [_ (noreply state)]))))

  ;; Test supervisor
  (define sup (supervisor:start
               (new supervisor%)
               (list (child-spec #:id 'counter1
                                 #:start (lambda () (gen-server:start (new my-counter%) '(10))))
                     (child-spec #:id 'counter2
                                 #:start (lambda () (gen-server:start (new my-counter%) '(20)))))))

  ;; Check children are running
  (define kids (supervisor:which-children sup))
  (check-equal? (length kids) 2)
  (check-not-false (member 'counter1 kids))
  (check-not-false (member 'counter2 kids))

  ;; Get the counter1 server and verify it works (using id directly)
  (check-equal? (gen-server:call 'counter1 'get) 10)
  (check-equal? (gen-server:call 'counter2 'get) 20)

  ;; Kill counter1 by causing an error (using id directly)
  (gen-server:cast! 'counter1 'die)

  ;; Wait for supervisor to detect and restart
  (sleep 0.1)

  ;; Verify counter1 is restarted (using id directly)
  (check-equal? (gen-server:call 'counter1 'get) 10)

  ;; Clean up
  (supervisor:stop sup))
