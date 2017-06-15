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
    if @cxt?.logger?
      logger = @cxt.logger
    else
      logger = console

    @promise.fail (e) ->
        logger.log "(Promise failed, #{e.toString().replace(/\n/, ' ')})"
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

  catch: (rejected) => @then null, rejected, null

  finally: (fn) => @promise.finally fn

  spread: (fulfilled, rejected) => @promise.spread fulfilled, rejected

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

  denodeify: (fn) =>
    (args...) =>
      deferred = @defer()
      handler = (err, res) =>
        if err?
          deferred.reject err
        else
          deferred.resolve res

      args.push handler

      Q(fn).fapply(args)

      return deferred.promise

  nfbind: (fn) =>
    @denodeify(fn)

  ninvoke: (args...) =>
    new QqPromise(process._qq_cxt, Q.ninvoke.apply(Q, args))

  npost: (args...) =>
    new QqPromise(process._qq_cxt, Q.npost.apply(Q, args))

  all: (promises, cxt) =>
    cxt ?= process._qq_cxt
    result = Q.all promises
    return new QqPromise(cxt, result)
 
  race: (promises, cxt) =>
    cxt ?= process._qq_cxt
    result = Q.race promises
    return new QqPromise(cxt, result)

  when: (promises, cxt) =>
    cxt ?= process._qq_cxt
    result = Q.when promises
    return new QqPromise(cxt, result)

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

  Promise: (resolver) =>
    deferred = @defer()
    try
      resolver(deferred.resolve, deferred.reject, deferred.notify)
    catch reason
      deferred.reject reason
    return deferred.promise

module.exports = qq = new Qq
