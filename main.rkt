#lang racket/base
(provide gen:server
         gen-server:start
         gen-server:call
         )
(require racket/generic
         racket/match)

(define-generics server
  (init server args)
  (handle-call server msg from state)
  (handle-cast server msg state)
  (handle-info server msg state)
  (terminate server reason state))

(struct ok (state))
(struct reply (response state))
(struct noreply (state))

(define (server-loop impl state)
  (match (thread-receive)
    [(list 'call from msg)
     (match-define (reply response new-state)
       (handle-call impl msg from state))
     (thread-send from response)
     (server-loop impl new-state)]

    [(list 'cast msg state)
     (match-define (noreply new-state)
       (handle-cast impl msg state))
     (server-loop impl new-state)]

    [(list 'info msg state)
     (match-define (noreply new-state)
       (handle-info impl msg state))
     (server-loop impl new-state)]

    [(list 'stop reason)
     (terminate impl reason state)]))

(define (gen-server:start impl init-args)
  (thread
    (lambda ()
      (match (init impl init-args)
        [(ok initial-state)
          (server-loop impl initial-state)]
        [init-result
          (error 'gen-server-start "init must return (ok state), got: ~a" init-result)]))
    #:pool 'own))

(define (gen-server:call server req)
  (thread-send server (list 'call (current-thread) req))
  (thread-receive))
(define (gen-server:cast! server req)
  (thread-send server (list 'cast req)))

(module+ test
  (require rackunit)

  (struct counter-state (value))
  (struct my-counter ()
    #:methods gen:server
    [(define (init _ args)
       (match-define (list n) args)
       (ok (counter-state n)))

     (define (handle-call _ msg from state)
       (match msg
         ['increment
          (define new-val (add1 (counter-state-value state)))
          (reply new-val (counter-state new-val))]
         ['get
          (reply (counter-state-value state) state)]
         [(list 'add n)
          (define new-val (+ (counter-state-value state) n))
          (reply new-val (counter-state new-val))]))

     (define (handle-cast _ msg state)
       (noreply state))

     (define (handle-info _ msg state)
       (noreply state))

     (define (terminate _ reason state)
       (void))])

  (define counter (gen-server:start (my-counter) '(1)))
  (check-equal? (gen-server:call counter 'get) 1)
  (check-equal? (gen-server:call counter `(add 5)) 6)
  )
