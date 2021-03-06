Q = require 'q'

# Wrapper for Q promises that preserves a context along a
# promise chain. A context could be thought of as a logical
# processing thread. E.g. the current http request being processed.
# Simple use case is to have logging report the http request
# associated with the log message, across asynchronous logic.

# TODO: make it prototypically inherit from wrapped promise,
# to inherit most of the methods, as we really only need to wrap then().
class QqPromise
  constructor: (@cxt, @promise) ->
    #if not @cxt
      #throw new Error("No cxt provided")
    if process.DEV != false
      @promise.fail (e) ->
        console.log '(Promise failed, ' + e.toString().substring(0, 50).replace(/\n/, '') + '...)'
        throw e

  then: (fulfilled, rejected, progressed) =>
    if fulfilled
      fulfilled = @_wrap fulfilled
    if rejected
      rejected = @_wrap rejected
    if progressed
      progressed = @_wrap progressed

    new QqPromise(@cxt, @promise.then(fulfilled, rejected, progressed))

  fail: (fn) => @then null, fn, null

  fin: (fn) =>
    @promise.fin @_wrap(fn)

  done: -> @promise.done()

  catch: (rejected) => @promise.catch(rejected)

  _wrap: (fn) ->
    (v) =>
      withContext @cxt, -> fn(v)

withContext = (cxt, block) ->
  orig = process._qq_cxt
  try
    process._qq_cxt = cxt
    return block()
  finally
    process._qq_cxt = orig

# TODO: wrap remaining funcs.
class Qq
  defer: (cxt) =>
    cxt ?= process._qq_cxt
    d = Q.defer()
    d.promise = new QqPromise(cxt, d.promise)
    d

  resolve: (val, cxt) =>
    cxt ?= process._qq_cxt
    new QqPromise(cxt, Q.resolve(val))

  reject: (reason, cxt) =>
    cxt ?= process._qq_cxt
    new QqPromise(cxt, Q.reject(reason))

  nfcall: (fn, args...) =>
    new QqPromise(process._qq_cxt, Q(fn).nfapply(args))

  ninvoke: (args...) =>
    new QqPromise(process._qq_cxt, Q.ninvoke.apply(Q, args))

  npost: (args...) =>
    new QqPromise(process._qq_cxt, Q.npost.apply(Q, args))

  all: (promises, cxt) =>
    cxt ?= process._qq_cxt
    Q.all promises

  when: (promises, cxt) =>
    cxt ?= process._qq_cxt
    Q.when promises

  catch: (object, rejected, cxt) =>
    cxt ?= process._qq_cxt
    Q.catch(object, rejected)

  withContext: withContext

  newThread: (name, block) =>
    if not @log
      @log = require('lib/log')('qq')

    @resolve(null, {_desc:name})
    .then =>
      @log.info 'begin thread', name

      return block()
    .fail (er) ->
      @log.error er
    .fin ->
      @log.info 'finished thread', name

    return

  maybeContext: => process._qq_cxt

  decorate: (obj, methods) =>
    qq = @
    wrapped = {}
    for m in methods
      wrapped[m] = (args...) ->
        qq.npost obj, m, args
    return wrapped

  context: =>
    if process._qq_cxt
      return process._qq_cxt
    else
      throw new Error('No current qq context')

module.exports = qq = new Qq
