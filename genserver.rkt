#lang racket/base
(provide gen-server%
         gen-server:start
         gen-server:call
         gen-server:cast!
         gen-server:stop
         register
         unregister
         whereis)
(require racket/class
         racket/match
         racket/async-channel)
(require version/utils)

;; Global process registry
(define *registry* (make-hash))

(define (register id server)
  (hash-set! *registry* id server))

(define (unregister id)
  (hash-remove! *registry* id))

(define (whereis id)
  (hash-ref *registry* id #f))

(define (gen-server:start impl init-args)
  (send impl start init-args))

(define (resolve-server server-or-id)
  (if (symbol? server-or-id)
      (whereis server-or-id)
      server-or-id))

(define (gen-server:call server-or-id msg)
  (define server (resolve-server server-or-id))
  (define reply-channel (make-async-channel))
  (async-channel-put (get-field channel server) (list 'call reply-channel msg))
  (async-channel-get reply-channel))
(define (gen-server:cast! server-or-id msg)
  (define server (resolve-server server-or-id))
  (async-channel-put (get-field channel server) (list 'cast msg)))
(define (gen-server:stop server-or-id [reason 'normal])
  (define server (resolve-server server-or-id))
  (async-channel-put (get-field channel server) (list 'stop reason)))

(define gen-server%
  (class object%
    (super-new)

    (init-field [running-server #f]
                [channel #f])

    (define/private (server-loop state)
      (match (async-channel-get channel)
        [(list 'call from msg)
         (handle-call msg from state)]
        [(list 'cast msg)
         (handle-cast msg state)]
        [(list 'info msg)
         (handle-info msg state)]
        [(list 'stop reason)
         (terminate reason state)
         (kill-thread running-server)
         (set! channel #f)]))

    (define/public (ok state)
      (server-loop state))

    (define/public (reply from response state)
      ; reply response
      (async-channel-put from response)
      ; loop with new state
      (server-loop state))

    (define/public (noreply state)
      (server-loop state))

    (define/public (init args)
      (error 'gen-server "init method must be overridden"))
    (define/public (handle-call msg from state)
      (error 'gen-server "handle-call method must be overridden"))
    (define/public (handle-cast msg state)
      (error 'gen-server "handle-cast method must be overridden"))
    (define/public (handle-info msg state)
      (noreply state))
    (define/public (terminate reason state)
      (void))

    (define/public (start init-args)
      (set! channel (make-async-channel))
      (set! running-server
            (cond
              [(version<=? "9.0" (version))
               (thread
                #:pool 'own
                (lambda ()
                  (define initial-state (init init-args))
                  (server-loop initial-state)))]
              [else
               (thread
                (lambda ()
                  (define initial-state (init init-args))
                  (server-loop initial-state)))]))
      this)))

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
          ['increment
           (define new-val (add1 (counter-state-value state)))
           (reply from new-val (counter-state new-val))]
          ['get
           (reply from (counter-state-value state) state)]
          [(list 'add n)
           (define new-val (+ (counter-state-value state) n))
           (reply from new-val (counter-state new-val))]))

      (define/override (handle-cast msg state)
        (match msg
          ['inc
           (define new-val (add1 (counter-state-value state)))
           (noreply (counter-state new-val))]
          [_ (noreply state)]))

      (define/override (handle-info msg state)
        (noreply state))

      (define/override (terminate reason state)
        (void))))

  (define counter (gen-server:start (new my-counter%) '(1)))
  (check-equal? (gen-server:call counter 'get) 1)
  (check-equal? (gen-server:call counter `(add 5)) 6)

  (gen-server:cast! counter 'inc)
  (sleep 0.1)
  (check-equal? (gen-server:call counter 'get) 7)
  (check-equal? (gen-server:call counter 'get) 7)
  (check-equal? (gen-server:call counter `(add 5)) 12)

  (gen-server:stop counter)
  )
