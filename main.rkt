#lang racket/base
(provide gen-server%
         gen-server:start
         gen-server:call
         )
(require racket/class
         racket/match
         racket/future)

(define gen-server%
  (class object%
    (super-new)
    (define/public (init args)
      (error 'gen-server "init method must be overridden"))
    (define/public (handle-call msg from state)
      (error 'gen-server "handle-call method must be overridden"))
    (define/public (handle-cast msg state)
      (error 'gen-server "handle-cast method must be overridden"))
    (define/public (handle-info msg state)
      (void))
    (define/public (terminate reason state)
      (void))))

(struct ok (state))
(struct reply (response state))
(struct noreply (state))

(define (server-loop impl state)
  (match (thread-receive)
    [(list 'call from msg)
     (match-define (reply response new-state)
       (send impl handle-call msg from state))
     (thread-send from response)
     (server-loop impl new-state)]

    [(list 'cast msg)
     (match-define (noreply new-state)
       (send impl handle-cast msg state))
     (server-loop impl new-state)]

    [(list 'info msg)
     (match-define (noreply new-state)
       (send impl handle-info msg state))
     (server-loop impl new-state)]

    [(list 'stop reason)
     (send impl terminate reason state)]))

(define (gen-server:start impl init-args)
  (thread
    (lambda ()
      (match (send impl init init-args)
        [(ok initial-state)
          (server-loop impl initial-state)]
        [init-result
          (error 'gen-server-start "init must return (ok state), got: ~a" init-result)]))
    ))

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

      (define/override (init args)
        (match-define (list n) args)
        (ok (counter-state n)))

      (define/override (handle-call msg from state)
        (match msg
          ['increment
           (define new-val (add1 (counter-state-value state)))
           (reply new-val (counter-state new-val))]
          ['get
           (reply (counter-state-value state) state)]
          [(list 'add n)
           (define new-val (+ (counter-state-value state) n))
           (reply new-val (counter-state new-val))]))

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
  )
