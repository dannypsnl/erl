#lang racket/base
(provide gen-server%
         gen-server:start
         gen-server:call
         gen-server:cast!
         )
(require racket/class
         racket/match
         racket/future)

(define gen-server%
  (class object%
    (super-new)

    (init-field [running-server #f])

    (define/private (server-loop state)
      (match (thread-receive)
        [(list 'call from msg)
         (handle-call msg from state)]
        [(list 'cast msg)
         (handle-cast msg state)]
        [(list 'info msg)
         (handle-info msg state)]
        [(list 'stop reason)
         (terminate reason state)
         (kill-thread running-server)]))

    (define/public (ok state)
      (server-loop state))

    (define/public (reply from response state)
      ; reply response
      (thread-send from response)
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
      (set-field! running-server this
        (thread
          (lambda ()
            (define initial-state (init init-args))
            (server-loop initial-state))))
      running-server)))

(define (gen-server:start impl init-args)
  (send impl start init-args))

(define (gen-server:call server msg)
  (thread-send server (list 'call (current-thread) msg))
  (thread-receive))
(define (gen-server:cast! server msg)
  (thread-send server (list 'cast msg)))

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
  )
