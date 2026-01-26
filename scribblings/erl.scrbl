#lang scribble/manual
@require[@for-label[erl
                    racket/base
                    racket/class]]

@title{erl}
@author{dannypsnl}

@defmodule[erl]

Erlang-style genserver abstractions for Racket.

@section{Generic Server}

The generic server (gen-server) pattern provides a standardized way to implement server processes
with synchronous and asynchronous messaging.
@nested[#:style 'inset]{
  @bold{Warning:}
  Don't call @racket[init], @racket[handle-call], @racket[handle-cast], @racket[handle-info], and @racket[terminate] directly.
  Override them in your implementation and use @racket[gen-server:start], @racket[gen-server:call], etc. to interact with servers.
  Don't override @racket[ok], @racket[reply], and @racket[noreply]; inherit them using @racket[inherit] instead.
}

@defclass[gen-server% object% ()]{

Base class for implementing genservers. Subclasses must override @racket[init] and
typically override @racket[handle-call] and @racket[handle-cast] to handle messages.

@defmethod[(init [args any/c]) any/c]{
  Initialization callback that must be overridden. Called when the server starts.

  @racket[args] is the initialization argument passed to @racket[gen-server:start].

  Should return the initial state by calling @racket[(ok state)].
}

@defmethod[(handle-call [msg any/c] [from async-channel?] [state any/c]) any/c]{
  Synchronous message handler that must be overridden. Handles messages sent via @racket[gen-server:call].

  @racket[msg] is the message received.
  @racket[from] is a reply channel for sending the response.
  @racket[state] is the current server state.

  Should return by calling @racket[(reply from response new-state)] to send a response
  and continue with updated state.
}

@defmethod[(handle-cast [msg any/c] [state any/c]) any/c]{
  Asynchronous message handler that must be overridden. Handles messages sent via @racket[gen-server:cast!].

  @racket[msg] is the message received.
  @racket[state] is the current server state.

  Should return by calling @racket[(noreply new-state)] to continue with updated state.
}

@defmethod[(handle-info [msg any/c] [state any/c]) any/c]{
  Handler for info messages. Default implementation calls @racket[(noreply state)].

  @racket[msg] is the info message received.
  @racket[state] is the current server state.

  Can be overridden to handle internal messages.
}

@defmethod[(terminate [reason any/c] [state any/c]) void?]{
  Cleanup callback invoked when the server is stopping. Default implementation does nothing.

  @racket[reason] is the termination reason (e.g., @racket['normal]).
  @racket[state] is the final server state.

  Override to perform cleanup operations.
}

@defmethod[(ok [state any/c]) any/c]{
  Helper method to initialize or continue the server loop with the given state.
  Used in @racket[init] to return the initial state.
}

@defmethod[(reply [from async-channel?] [response any/c] [state any/c]) any/c]{
  Helper method to send a reply to a synchronous call and continue the server loop.

  @racket[from] is the reply channel from @racket[handle-call].
  @racket[response] is the value to send back to the caller.
  @racket[state] is the new state to continue with.
}

@defmethod[(noreply [state any/c]) any/c]{
  Helper method to continue the server loop without sending a reply (used in asynchronous handlers).

  @racket[state] is the new state to continue with.
}

}

@defproc[(gen-server:start [impl (is-a?/c gen-server%)] [init-args any/c]) (is-a?/c gen-server%)]{
  Starts a generic server instance.

  @racket[impl] is an instance of a class derived from @racket[gen-server%].
  @racket[init-args] is passed to the server's @racket[init] method.

  Returns the running server instance.
}

@defproc[(gen-server:call [server (is-a?/c gen-server%)] [msg any/c]) any/c]{
  Sends a synchronous message to the server and waits for a response.

  @racket[server] is the server instance.
  @racket[msg] is the message to send.

  Returns the response from the server's @racket[handle-call] method.
}

@defproc[(gen-server:cast! [server (is-a?/c gen-server%)] [msg any/c]) void?]{
  Sends an asynchronous message to the server without waiting for a response.

  @racket[server] is the server instance.
  @racket[msg] is the message to send.

  The message is handled by the server's @racket[handle-cast] method.
}

@defproc[(gen-server:stop [server (is-a?/c gen-server%)] [reason any/c 'normal]) void?]{
  Stops a running server.

  @racket[server] is the server instance to stop.
  @racket[reason] is the termination reason; defaults to @racket['normal].

  Triggers the server's @racket[terminate] callback before shutting down.
}

@subsection{Example}

Here's a complete example of implementing a counter server:

@racketblock[
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
        [(list 'add n)
         (define new-val (+ (counter-state-value state) n))
         (reply from new-val (counter-state new-val))]))

    (define/override (handle-cast msg state)
      (match msg
        ['inc
         (define new-val (add1 (counter-state-value state)))
         (noreply (counter-state new-val))]
        [_ (noreply state)]))))

(code:comment "Start the counter with initial value 1")
(define counter (gen-server:start (new my-counter%) '(1)))

(code:comment "Synchronous calls that wait for response")
(gen-server:call counter 'get)          (code:comment "=> 1")
(gen-server:call counter '(add 5))      (code:comment "=> 6")

(code:comment "Asynchronous cast that doesn't wait")
(gen-server:cast! counter 'inc)

(code:comment "Stop the server")
(gen-server:stop counter)
]
