###
  knockback_observable.js
  (c) 2011 Kevin Malakoff.
  Knockback.Observable is freely distributable under the MIT license.
  See the following for full license details:
    https://github.com/kmalakoff/knockback/blob/master/LICENSE
###
throw new Error('Knockback: Dependency alert! knockback_core.js must be included before this file') if not this.Knockback

####################################################
# options
#   * key - required to look up the model's attributes
#   * read - called to get the value and each time the locale changes
#   * write - called to set the value
#   * args - arguments passed to the read and write function
####################################################

class Knockback.Observable
  constructor: (@model, @options, @view_model={}) ->
    throw new Error('Observable: model is missing') if not @model
    throw new Error('Observable: options is missing') if not @options
    @options = {key: @options} if _.isString(@options) or ko.isObservable(@options)
    throw new Error('Observable: options.key is missing') if not @options.key

    @__kb = {}
    @__kb._onModelChange = _.bind(@_onModelChange, @)
    @__kb._onModelLoaded = _.bind(@_onModelLoaded, @)
    @__kb._onModelUnloaded = _.bind(@_onModelUnloaded, @)

    # determine model or model_ref type
    if Backbone.ModelRef and (@model instanceof Backbone.ModelRef)
      @model_ref = @model; @model_ref.retain()
      @model_ref.bind('loaded', @__kb._onModelLoaded)
      @model_ref.bind('unloaded', @__kb._onModelUnloaded)
      @model = @model_ref.getModel()

    # internal state
    @__kb.value_observable = ko.observable()
    @__kb.localizer = new @options.localizer(@_getCurrentValue()) if @options.localizer
    @__kb.observable = ko.dependentObservable({
      read: _.bind(@_onGetValue, @)
      write: if @options.write then _.bind(@_onSetValue, @) else (-> throw new Error("Knockback.Observable: #{@options.key} is read only"))
      owner: @view_model
    })

    # publish public interface on the observable and return instead of this
    @__kb.observable.destroy = _.bind(@destroy, @)
    @__kb.observable.setToDefault = _.bind(@setToDefault, @)

    # start
    @model.bind('change', @__kb._onModelChange) if not @model_ref or @model_ref.isLoaded()

    return kb.unwrapObservable(this)

  destroy: ->
    @__kb.value_observable = null
    @__kb.observable.dispose(); @__kb.observable = null
    @__kb._onModelUnloaded(@model) if @model
    if @model_ref
      @model_ref.unbind('loaded', @__kb._onModelLoaded)
      @model_ref.unbind('unloaded', @__kb._onModelUnloaded)
      @model_ref.release(); @model_ref = null
    @options  = null; @view_model = null
    @__kb = null

  setToDefault: ->
    value = @_getDefaultValue()
    if @__kb.localizer
      @__kb.localizer.observedValue(value)
      value = @__kb.localizer()
    @__kb.value_observable(value) # trigger the dependable

  ####################################################
  # Internal
  ####################################################
  _getDefaultValue: ->
    return '' if not @options.hasOwnProperty('default')
    return if _.isFunction(@options.default) then @options.default() else @options.default

  _getCurrentValue: ->
    return @_getDefaultValue() if not @model
    key = ko.utils.unwrapObservable(@options.key)
    args = [key]
    if not _.isUndefined(@options.args)
      if _.isArray(@options.args) then (args.push(ko.utils.unwrapObservable(arg)) for arg in @options.args) else args.push(ko.utils.unwrapObservable(@options.args))
    return if @options.read then @options.read.apply(@view_model, args) else @model.get.apply(@model, args)

  _onGetValue: ->
    # trigger all the dependables
    @__kb.value_observable()
    ko.utils.unwrapObservable(@options.key)
    if not _.isUndefined(@options.args)
      if _.isArray(@options.args) then (ko.utils.unwrapObservable(arg) for arg in @options.args) else ko.utils.unwrapObservable(@options.args)
    value = @_getCurrentValue()

    if @__kb.localizer
      @__kb.localizer.observedValue(value)
      value = @__kb.localizer()
    return value

  _onSetValue: (value) ->
    if @__kb.localizer
      @__kb.localizer(value)
      value = @__kb.localizer.observedValue()

    if @model
      set_info = {}; set_info[ko.utils.unwrapObservable(@options.key)] = value
      args = if _.isFunction(@options.write) then [value] else [set_info]
      if not _.isUndefined(@options.args)
        if _.isArray(@options.args) then (args.push(ko.utils.unwrapObservable(arg)) for arg in @options.args) else args.push(ko.utils.unwrapObservable(@options.args))
      if _.isFunction(@options.write) then @options.write.apply(@view_model, args) else @model.set.apply(@model, args)
    if @__kb.localizer then @__kb.value_observable(@__kb.localizer()) else @__kb.value_observable(value) # trigger the dependable and store the correct value

  _onModelLoaded: (model) ->
    @model = model
    @model.bind('change', @__kb._onModelChange) # all attributes if it is manually triggered
    @_updateValue()

  _onModelUnloaded: (model) ->
    (@__kb.localizer.destroy(); @__kb.localizer = null) if @__kb.localizer and @__kb.localizer.destroy
    @model.unbind('change', @__kb._onModelChange) # all attributes if it is manually triggered
    @model = null

  _onModelChange: ->
    return if (@model and @model.hasChanged) and not @model.hasChanged(ko.utils.unwrapObservable(@options.key)) # no change, nothing to do
    @_updateValue()

  _updateValue: ->
    value = @_getCurrentValue()
    if @__kb.localizer
      @__kb.localizer.observedValue(value)
      value = @__kb.localizer()
    @__kb.value_observable(value) # trigger the dependable

# factory function
Knockback.observable = (model, options, view_model) -> return new Knockback.Observable(model, options, view_model)