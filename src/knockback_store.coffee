###
  knockback_store.js
  (c) 2012 Kevin Malakoff.
  Knockback.Store is freely distributable under the MIT license.
  See the following for full license details:
    https://github.com/kmalakoff/knockback/blob/master/LICENSE
###

class kb.Store
  @useOptionsOrCreate: (options, obj, observable) ->
    if options.store
      store = kb.utils.wrappedStore(observable, options.store)
      options.store.registerObservable(obj, observable, options)
    else
      store = kb.utils.wrappedStore(observable, new kb.Store())
      kb.utils.wrappedStoreIsOwned(observable, true)
    return store

  constructor: ->
    @objects = []
    @observables = []

  destroy: ->
    
    # release the view models
    for index, observable of @observables
      continue unless observable

      observable.releaseReferences?() # release all references to break cycles

      # release
      if observable.release
        observable.release()
      else
        kb.release(observable)

    @objects = null
    @observables = null

  registerObservable: (obj, observable, options={}) ->
    return unless (obj and observable) # nothing to register

    # only store view models not basic ko.observables nor kb.CollectionObservables
    return if ko.isObservable(observable) or observable.__kb_is_co

    @objects.push(obj)
    kb.utils.wrappedObject(observable, obj)
    @observables.push(observable)
    observable.retain?()

    # set the creator
    observable.__kb or= {}
    if (options.creator)
      observable.__kb.creator = options.creator  # save the creator to mark the source of the observable
    else if (options.path and options.factory)
      observable.__kb.creator = options.factory.creatorForPath(obj, options.path)  # save the creator to mark the source of the observable
    else
      observable.__kb.creator = null

  findOrCreateObservable: (obj, path, factory, creator) ->
    if not factory
      observable = if creator then creator(obj, {path: path, store: this, creator: creator}) else kb.Factory.createDefault(obj, {path: path, store: this})
    else
      creator = factory.creatorForPath(obj, path) if not creator
      return ko.observable(obj) unless creator
      return obj if creator.models_only  # do not create an observable

      # check for an existing one of the correct type
      if obj and not (obj instanceof Backbone.Collection) # don't share collection observables
        for test, index in @objects
          observable = @observables[index]
          continue unless observable and observable.__kb
          if (test is obj) and (observable.__kb.creator is creator)
            observable.retain?()
            return observable

      # create
      observable = factory.createForPath(obj, path, this, creator)
      observable = ko.observable(null) unless observable # default to null

    # check if already registered
    index = _.indexOf(@observables, observable)
    @registerObservable(obj, observable, {creator: creator}) if index < 0 # not registered yet, register now
    return observable

  releaseObservable: (observable, owns_store) ->
    return unless observable # something to release and not in destroy
    return if arguments.length is 2 and not owns_store and not observable.release # cares about ownership -> do not clear out observables unless owned or ref count is 0

    # release and exit if references still exist
    kb.release(observable)
    return if observable.refCount and observable.refCount() > 0

    # clear our references
    kb.utils.wrappedObject(observable, null)
    index = _.indexOf(@observables, observable)
    return if index < 0
    @objects[index] = null
    @observables[index] = null